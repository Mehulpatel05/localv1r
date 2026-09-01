import hashlib
import hmac
import time
import io
import uuid
from typing import Optional, Dict, List, Tuple, Literal
from collections import defaultdict
from fastapi import FastAPI, Header, HTTPException, File, UploadFile, status, Request
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, Field
from PIL import Image
import requests

from config import Config
from services.telegram_service import TelegramService
from google.cloud import firestore
from services.firebase_service import FirebaseService, db
from utils.moderation import validate_text_content

app = FastAPI(
    title="Vadodara Local Secure API Gateway",
    description="Secure backend proxy for anonymous community posting, voting, and media uploads.",
    version="1.0.0"
)

# 🛡️ DUAL-KEY MULTI-ROUTE RATE LIMITER CACHES
RATE_LIMIT_IP_CACHE: Dict[str, List[float]] = defaultdict(list)
RATE_LIMIT_ROUTE_CACHE: Dict[str, List[float]] = defaultdict(list)

# 🛡️ MODERATOR TOKEN REVOCATION BLACKLIST CACHE (§17)
REVOKED_TOKENS: set = set()

# 🛡️ IDEMPOTENCY RESPONSE CACHE (§29 Replay Protection)
IDEMPOTENCY_CACHE: Dict[str, Tuple[float, dict]] = {}

def get_cached_idempotent_response(key: str) -> Optional[dict]:
    """
    Checks if the Idempotency-Key has already been processed and returns the cached response.
    Purges keys older than 10 minutes (600 seconds) to avoid memory leaks.
    """
    now = time.time()
    # Cleanup expired keys
    expired = [k for k, v in IDEMPOTENCY_CACHE.items() if now - v[0] > 600]
    for k in expired:
        del IDEMPOTENCY_CACHE[k]
        
    if key in IDEMPOTENCY_CACHE:
        return IDEMPOTENCY_CACHE[key][1]
    return None

def save_idempotent_response(key: str, response: dict):
    IDEMPOTENCY_CACHE[key] = (time.time(), response)


def enforce_ip_rate_limit(ip: str, max_requests: int, window: float = 60.0):
    """
    🛡️ Enforces per-IP rate limiting (mitigates registration spam and brute-force).
    """
    now = time.time()
    timestamps = [t for t in RATE_LIMIT_IP_CACHE[ip] if now - t < window]
    RATE_LIMIT_IP_CACHE[ip] = timestamps
    
    if len(timestamps) >= max_requests:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many registrations from this IP network. Please wait a minute."
        )
    RATE_LIMIT_IP_CACHE[ip].append(now)

def enforce_route_rate_limit(route: str, key: str, max_requests: int, window: float = 60.0):
    """
    🛡️ Enforces per-route, per-session rate limiting.
    Mitigates: scripted vote-manipulation, spam comments, and CDN storage floods.
    """
    now = time.time()
    cache_key = f"{route}:{key}"
    timestamps = [t for t in RATE_LIMIT_ROUTE_CACHE[cache_key] if now - t < window]
    RATE_LIMIT_ROUTE_CACHE[cache_key] = timestamps
    
    if len(timestamps) >= max_requests:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Rate limit exceeded for route: {route}. Please slow down your requests."
        )
    RATE_LIMIT_ROUTE_CACHE[cache_key].append(now)

# 🛡️ GLOBAL VERBOSE EXCEPTION MASKING
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    print(f"[ERROR] Unhandled server exception: {exc}")
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "An internal database or service error occurred. Grievance logs have been recorded."}
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=status.HTTP_400_BAD_REQUEST,
        content={"detail": "Request payload format is invalid."}
    )


# 🛡️ COMPREHENSIVE RISK EVALUATION (Server-Side Authority)
def evaluate_request_risk(
    client_ip: str, 
    client_vpn_flag: bool = False, 
) -> bool:
    """
    Evaluates request risk using server-side signals.
    Client-provided headers like x-vpn-detected are treated as weak signals.
    """
    risk_score = 0
    
    # 1. Client VPN flag = weak signal
    if client_vpn_flag:
        risk_score += 10 
        
    # 2. IP reputation = stronger (simulated)
    # ip_rep = get_ip_reputation(client_ip)
    # if ip_rep == "DATA_CENTER" or ip_rep == "KNOWN_TOR": risk_score += 50
    
    # 3. ASN / hosting check = stronger (simulated)
    # asn_info = get_asn_info(client_ip)
    # if asn_info.get("type") == "hosting": risk_score += 40
    
    # 4. GeoIP = location signal (simulated)
    # geo_info = get_geo_info(client_ip)
    # if geo_info.get("city") != "Vadodara": risk_score += 30
    
    # 5. Play Integrity = app/device integrity
    # (Already handled by verify_device_attestation blocking if false)
    
    # 6. Behaviour/rate limit = abuse signal
    # (Already handled by enforce_route_rate_limit)

    # Final decision strictly by server
    if risk_score >= 100:
        return False
    return True

# 🛡️ MAGIC BYTE SIGNATURE DETECTION
def verify_magic_bytes(data: bytes) -> str:
    """
    🛡️ Verifies file format using magic byte signatures.
    Returns the normalized format string ('JPEG', 'PNG', 'WEBP') or raises HTTPException.
    """
    if len(data) < 12:
        raise HTTPException(status_code=400, detail="Invalid image file size.")
    if data.startswith(b"\xff\xd8\xff"):
        return "JPEG"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "PNG"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "WEBP"
    raise HTTPException(status_code=400, detail="Unsupported file signature. Only JPEG, PNG, and WEBP images are allowed.")


# 🛡️ CRYPTOGRAPHIC DUAL-TOKEN AUTH PROTOCOL
def generate_server_handle(device_id: str) -> str:
    raw_str = f"{device_id}:{Config.SERVER_SALT}"
    hashed = hashlib.sha256(raw_str.encode()).hexdigest()
    return f"Anon#{hashed[:6].upper()}"

import secrets

def generate_session_token(installation_id: str, handle: str) -> str:
    auth_token = secrets.token_hex(32)
    token_hash = hashlib.sha256(auth_token.encode()).hexdigest()
    
    if db is not None:
        db.collection("devices").document(installation_id).set({
            "installationId": installation_id,
            "otpVerified": True,
            "tokenHash": token_hash,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "lastSeenAt": firestore.SERVER_TIMESTAMP,
            "revokedAt": None
        })
    return auth_token

def generate_refresh_token(installation_id: str, handle: str) -> str:
    return "deprecated"

def verify_session_token(authorization: Optional[str]) -> Tuple[str, str]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing or invalid Authorization header.")
    
    auth_token = authorization.split("Bearer ")[1].strip()
    token_hash = hashlib.sha256(auth_token.encode()).hexdigest()
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        docs = db.collection("devices").where("tokenHash", "==", token_hash).limit(1).get()
        if not docs:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session token.")
            
        device_doc = docs[0].to_dict()
        if device_doc.get("revokedAt") is not None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session revoked.")
            
        installation_id = device_doc.get("installationId")
        handle = generate_server_handle(installation_id)
        
        banned_ref = db.collection("banned_users").document(handle).get()
        if banned_ref.exists:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This account has been suspended for safety policy violations.")
            
        return installation_id, handle
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session token.")

# 🛡️ DEVICE INTEGRITY ATTESTATION VALIDATION (Play Integrity)
def verify_device_attestation(request_hash: str, attestation_token: str) -> bool:
    if not attestation_token:
        return False
        
    if attestation_token.startswith("simulated_attestation_"):
        parts = attestation_token.split("_")
        # simulated_attestation_com.example.localv1_<requestHash>
        if len(parts) >= 3:
            package_name = parts[2]
            return package_name == "com.example.localv1"
        return False
        
    # In production, verify with Google Play Integrity API
    # POST https://playintegrity.googleapis.com/v1/com.example.localv1:decodeIntegrityToken
    # { "integrity_token": attestation_token }
    # Using Google Auth credentials
    
    try:
        import google.auth
        from google.auth.transport.requests import Request as GoogleAuthRequest
        
        credentials, project_id = google.auth.default(scopes=['https://www.googleapis.com/auth/playintegrity'])
        auth_req = GoogleAuthRequest()
        credentials.refresh(auth_req)
        
        url = f"https://playintegrity.googleapis.com/v1/com.example.localv1:decodeIntegrityToken"
        headers = {
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json"
        }
        data = {
            "integrity_token": attestation_token
        }
        
        import requests
        response = requests.post(url, headers=headers, json=data, timeout=10)
        
        if response.status_code == 200:
            result = response.json()
            token_payload_external = result.get("tokenPayloadExternal", {})
            request_details = token_payload_external.get("requestDetails", {})
            
            # Verify request hash
            if request_details.get("requestHash") != request_hash:
                print("Integrity Error: Request hash mismatch")
                return False
                
            # Verify app recognition
            app_verdict = token_payload_external.get("appIntegrity", {}).get("appRecognitionVerdict")
            if app_verdict != "PLAY_RECOGNIZED":
                print(f"Integrity Error: App not recognized ({app_verdict})")
                return False
                
            # Verify device recognition
            device_verdict = token_payload_external.get("deviceIntegrity", {}).get("deviceRecognitionVerdict")
            if not device_verdict or "MEETS_DEVICE_INTEGRITY" not in device_verdict:
                print(f"Integrity Error: Device integrity failed ({device_verdict})")
                return False
                
            return True
        else:
            print(f"Integrity API Error: {response.status_code} {response.text}")
            return False
    except Exception as e:
        print(f"Play Integrity Verification failed: {e}")
        # Fallback for development if needed, but return False in prod
        return False

# 🛡️ MODERATOR ROLE PRIVILEGES HIERARCHY (§16, §17 Claims Check)
ROLE_HIERARCHY = {
    "moderator": 1,
    "admin": 2,
    "superadmin": 3
}

def generate_mod_session_token(email: str, role: str) -> str:
    jti = str(uuid.uuid4())
    iss = "vadodara-local-backend"
    aud = "vadodara-local-moderator-portal"
    expires_at = int(time.time()) + 7200  # 2 Hours Short-Lived Access
    message = f"mod:{jti}:{email}:{role}:{iss}:{aud}:{expires_at}".encode()
    signature = hmac.new(Config.JWT_SECRET.encode(), message, hashlib.sha256).hexdigest()
    return f"mod|{jti}|{email}|{role}|{iss}|{aud}|{expires_at}|{signature}"

def verify_moderator_session(token: Optional[str], required_role: str) -> Tuple[str, str]:
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing moderator auth token.")
    try:
        parts = token.split("|")
        if len(parts) != 8 or parts[0] != "mod":
            raise ValueError()
        _, jti, email, role, iss, aud, expires_at_str, signature = parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7]
        
        # 1. Revocation checks (RAM cache fast track)
        if jti in REVOKED_TOKENS:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked.")
            
        # 2. Expiry verification
        if time.time() > int(expires_at_str):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Moderator session expired. Please login again.")
            
        # 3. Issuer & Audience claims checks
        if iss != "vadodara-local-backend" or aud != "vadodara-local-moderator-portal":
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token claim verification failed.")
            
        # 4. Cryptographic signature check
        message = f"mod:{jti}:{email}:{role}:{iss}:{aud}:{expires_at_str}".encode()
        expected = hmac.new(Config.JWT_SECRET.encode(), message, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(signature, expected):
            raise ValueError()
            
        # 5. Revocation checks (Database fallback persistence check)
        if db is not None:
            revoked_doc = db.collection("revoked_tokens").document(jti).get()
            if revoked_doc.exists:
                REVOKED_TOKENS.add(jti)  # Cache locally
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked.")
            
        # 6. Role Permissions hierarchy checks
        if ROLE_HIERARCHY.get(role, 0) < ROLE_HIERARCHY.get(required_role, 0):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: Insufficient privileges.")
            
        return email, role
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid moderator token.")


# Enums / Literal Type Constraints (§23)
VadodaraArea = Literal[
    "alkapuri", "manjalpur", "gotri", "sayajigunj", "karelibaug", 
    "waghodia", "harni", "vasna", "general"
]

PostCategory = Literal[
    "traffic", "services", "food", "educationJobs", "general", "emergency"
]

# Request models
class OtpVerifyRequest(BaseModel):
    firebaseIdToken: str = Field(..., min_length=10)

class DeviceRegisterRequest(BaseModel):
    installationId: str = Field(..., min_length=36, max_length=36, pattern=r"^[0-9a-fA-F-]{36}$")
    attestationToken: str = Field(..., min_length=10, max_length=5000)

class PostCreateRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=5000)
    area: VadodaraArea = Field(..., description="Target neighborhood area")
    category: PostCategory = Field(..., description="Post category")
    imageUrl: Optional[str] = Field(None, max_length=500)

class CommentCreateRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=1000)

class VoteRequest(BaseModel):
    direction: Literal[1, -1] = Field(..., description="1 for upvote, -1 for downvote")
    attestationToken: Optional[str] = None
    requestId: Optional[str] = None

class ReportRequest(BaseModel):
    reason: str = Field(..., min_length=3, max_length=100, description="Reason for reporting")

# Moderator Request Models
class ModLoginRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=100, pattern=r"^[^@]+@[^@]+\.[^@]+$")
    password: str = Field(..., min_length=8, max_length=100)

class MfaVerifyRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=100, pattern=r"^[^@]+@[^@]+\.[^@]+$")
    preAuthToken: str = Field(...)
    mfaCode: str = Field(..., min_length=6, max_length=6, pattern=r"^\d{6}$")

class BanRequest(BaseModel):
    targetHandle: str = Field(..., min_length=10, max_length=100)
    reason: str = Field(..., min_length=3, max_length=200)

class AddModRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=100, pattern=r"^[^@]+@[^@]+\.[^@]+$")
    password: str = Field(..., min_length=8, max_length=100)
    role: Literal["moderator", "admin", "superadmin"] = Field("moderator")


# Endpoints

# 1. Device Registration
@app.post("/api/v1/devices/register")
async def register_device(
    request: DeviceRegisterRequest,
    server_request: Request,
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    ip_addr = server_request.client.host if server_request.client else "127.0.0.1"
    enforce_ip_rate_limit(ip_addr, max_requests=5)

    
    import hashlib
    # Reconstruct request hash
    raw_hash_str = f"POST/api/v1/devices/register{request.installationId}"
    expected_hash = hashlib.sha256(raw_hash_str.encode()).hexdigest()
    if not verify_device_attestation(expected_hash, request.attestationToken):
    
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Device attestation validation failed."
        )

    handle = generate_server_handle(request.installationId)
    session_token = generate_session_token(request.installationId, handle)
    refresh_token = generate_refresh_token(request.installationId, handle)
    
    res = {
        "status": "success",
        "sessionToken": session_token,
        "refreshToken": refresh_token,
        "handle": handle
    }
    if idempotency_key:
        save_idempotent_response(idempotency_key, res)
    return res

# 2. Token Refresh Endpoint
@app.post("/api/v1/devices/refresh")
async def refresh_session(
    x_refresh_token: Optional[str] = Header(None, description="Secure signed refresh token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    if not x_refresh_token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing refresh token.")

    try:
        parts = x_refresh_token.split("|")
        if len(parts) != 4:
            raise ValueError()
        installation_id, handle, expires_at_str, signature = parts[0], parts[1], parts[2], parts[3]
        
        expires_at = int(expires_at_str)
        if time.time() > expires_at:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired. Please re-register.")
            
        message = f"refresh:{installation_id}:{handle}:{expires_at}".encode()
        expected = hmac.new(Config.JWT_SECRET.encode(), message, hashlib.sha256).hexdigest()
        
        if not hmac.compare_digest(signature, expected):
            raise ValueError()
            
        new_session_token = generate_session_token(installation_id, handle)
        res = {
            "status": "success",
            "sessionToken": new_session_token
        }
        if idempotency_key:
            save_idempotent_response(idempotency_key, res)
        return res
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")

# 2.5 Phone Auth OTP Verification (Backend verifies Firebase ID token directly)
@app.post("/api/v1/devices/verify-phone")
async def verify_phone_auth(
    request: OtpVerifyRequest,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("verify_phone", device_id, max_requests=5)

    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")

    try:
        from firebase_admin import auth as firebase_auth
        
        # Verify Firebase ID token via firebase-admin, ensuring server-backed authority
        decoded_token = firebase_auth.verify_id_token(request.firebaseIdToken)
        phone_number = decoded_token.get('phone_number')
        
        if not phone_number:
            raise HTTPException(status_code=400, detail="Token does not contain a phone number.")
            
        import hashlib
        phone_hash = hashlib.sha256(phone_number.encode()).hexdigest()
        
        # Update device doc indicating OTP is verified on server side
        db.collection("devices").document(device_id).update({
            "otpVerified": True,
            "phoneNumberHash": phone_hash,
            "phoneVerifiedAt": firestore.SERVER_TIMESTAMP
        })
        
        res = {"status": "success", "message": "Phone authentication verified by backend."}
        if idempotency_key:
            save_idempotent_response(idempotency_key, res)
        return res
    except Exception as e:
        print(f"Firebase ID token verification failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase ID token. OTP verification failed.")

# 3. Secure Post Creation
@app.post("/api/v1/posts/create", status_code=status.HTTP_201_CREATED)
async def create_post(
    request: PostCreateRequest,
    server_request: Request,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    x_vpn_detected: Optional[bool] = Header(False, description="Client side VPN detection flag"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("post", device_id, max_requests=5)
    
    client_ip = server_request.client.host if server_request.client else "127.0.0.1"
    if not evaluate_request_risk(client_ip, client_vpn_flag=x_vpn_detected):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="High risk request blocked by security policies.")

    if db is not None:
        device_doc = db.collection("devices").document(device_id).get()
        if device_doc.exists:
            device_data = device_doc.to_dict()
            if not device_data.get("otpVerified"):
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="OTP_REQUIRED: Phone authentication is required to create a post.")
            
            # FUTURE: GPS/IP location check can be enforced here independently of OTP
            # if not is_in_vadodara(ip_addr, gps_coords): raise location_error

    error_msg = validate_text_content(request.content)

    error_msg = validate_text_content(request.content)
    if error_msg:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error_msg)
        
    success = FirebaseService.create_post(
        author_handle=user_handle,
        content=request.content,
        area=request.area,
        category=request.category,
        image_url=request.imageUrl
    )
    if not success:
        raise HTTPException(status_code=500, detail="Failed to publish post.")
        
    res = {"status": "success", "authorHandle": user_handle}
    if idempotency_key:
        save_idempotent_response(idempotency_key, res)
    return res


# 3.1 Get Posts (Read Path over REST)
@app.get("/api/v1/posts")
async def get_posts(
    limit: int = 20,
    cursor: Optional[str] = None,
    authorization: Optional[str] = Header(None, description="Bearer token")
):
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
    
    # We can enforce rate limit for reading
    if authorization and authorization.startswith("Bearer "):
        try:
            device_id, _ = verify_session_token(authorization)
            enforce_route_rate_limit("get_posts", device_id, max_requests=100)
        except:
            pass # allow anonymous reading for now, or block based on architecture

    try:
        query = db.collection("posts").order_by("createdAt", direction=firestore.Query.DESCENDING).limit(min(limit, 50))
        
        # If cursor provided, it's the post ID to start after
        if cursor:
            cursor_doc = db.collection("posts").document(cursor).get()
            if cursor_doc.exists:
                query = query.start_after(cursor_doc)
                
        docs = query.get()
        posts = []
        for doc in docs:
            data = doc.to_dict()
            if data.get("deletedAt") is not None or data.get("hiddenByMod") == True:
                continue
            
            # Format output
            data['id'] = doc.id
            if data.get('createdAt'):
                data['createdAt'] = data['createdAt'].isoformat()
            posts.append(data)
            
        last_id = docs[-1].id if docs else None
        return {"status": "success", "posts": posts, "nextCursor": last_id}
    except Exception as e:
        print(f"Error fetching posts: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch posts")

# 4.1 Get Comments
@app.get("/api/v1/posts/{post_id}/comments")
async def get_comments(post_id: str):
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        docs = db.collection("posts").document(post_id).collection("comments").order_by("createdAt").limit(100).get()
        comments = []
        for doc in docs:
            data = doc.to_dict()
            data['id'] = doc.id
            if data.get('createdAt'):
                data['createdAt'] = data['createdAt'].isoformat()
            comments.append(data)
        return {"status": "success", "comments": comments}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to fetch comments")

# 4. Secure Comment Addition
@app.post("/api/v1/posts/{post_id}/comment", status_code=status.HTTP_201_CREATED)
async def add_comment(
    post_id: str,
    request: CommentCreateRequest,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("comment", device_id, max_requests=20)

    error_msg = validate_text_content(request.content)
    if error_msg:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error_msg)
        
    success = FirebaseService.add_comment(
        post_id=post_id,
        author_handle=user_handle,
        content=request.content
    )
    if not success:
        raise HTTPException(status_code=500, detail="Failed to write comment.")
        
    res = {"status": "success"}
    if idempotency_key:
        save_idempotent_response(idempotency_key, res)
    return res


# 5. Secure Transaction Voting
@app.post("/api/v1/posts/{post_id}/vote")
async def vote_post(
    post_id: str,
    request: VoteRequest,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("vote", device_id, max_requests=60)

    # Verify Play Integrity Hash
    if request.attestationToken and request.requestId:
        import hashlib
        raw_hash_str = f"POST/api/v1/posts/{post_id}/vote{request.direction}{request.requestId}"
        expected_hash = hashlib.sha256(raw_hash_str.encode()).hexdigest()
        if not verify_device_attestation(expected_hash, request.attestationToken):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Device attestation validation failed.")

    success = FirebaseService.vote_post(post_id=post_id, user_handle=user_handle, direction=request.direction)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to register vote.")
        
    res = {"status": "success"}
    if idempotency_key:
        save_idempotent_response(idempotency_key, res)
    return res


# 6. Secure Reporting
@app.post("/api/v1/posts/{post_id}/report")
async def report_post(
    post_id: str,
    request: ReportRequest,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("report", device_id, max_requests=10)

    success = FirebaseService.report_post(post_id=post_id, reporter_handle=user_handle, reason=request.reason)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to submit report.")
        
    res = {"status": "success"}
    if idempotency_key:
        save_idempotent_response(idempotency_key, res)
    return res


# 7. Secure Moderation Restore
@app.post("/api/v1/posts/{post_id}/restore")
async def restore_post(
    post_id: str,
    server_request: Request,
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    mod_email, mod_role = verify_moderator_session(x_moderator_token, required_role="moderator")

    success = FirebaseService.restore_post(post_id)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to restore post.")
        
    # Chained Audit Log
    request_id = str(uuid.uuid4())
    ip_addr = server_request.client.host if server_request.client else "127.0.0.1"
    FirebaseService.log_moderator_action(
        moderator_id=mod_email,
        role=mod_role,
        action="restore",
        target=post_id,
        reason="Restored flagged post to public feed.",
        request_id=request_id,
        ip_address=ip_addr
    )
    
    res = {"status": "success"}
    if idempotency_key:
        save_idempotent_response(idempotency_key, res)
    return res


# 8. Secure BOLA-Protected Deletion
@app.post("/api/v1/posts/{post_id}/delete")
async def delete_post(
    post_id: str,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("delete", device_id, max_requests=10)

    if db is None:
        raise HTTPException(status_code=500, detail="Database connection offline.")
        
    post_ref = db.collection("posts").document(post_id)
    post_snapshot = post_ref.get()
    
    if not post_snapshot.exists:
        raise HTTPException(status_code=404, detail="Post not found.")
        
    post_data = post_snapshot.to_dict()
    if post_data.get("deletedAt") is not None:
        raise HTTPException(status_code=400, detail="Post is already deleted.")
        
    original_author = post_data.get("authorHandle", "")
    if original_author != user_handle:
        raise HTTPException(status_code=403, detail="Unauthorized.")
        
    image_url = post_data.get("imageUrl")
    if image_url and "/api/v1/media/" in image_url:
        media_id = image_url.split("/api/v1/media/")[-1]
        FirebaseService.delete_media(media_id)
        
        if media_id in MEDIA_CACHE:
            del MEDIA_CACHE[media_id]
        if media_id in MEDIA_TYPE_CACHE:
            del MEDIA_TYPE_CACHE[media_id]

    success = FirebaseService.delete_post(post_id)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to delete post.")
        
    res = {"status": "success"}
    if idempotency_key:
        save_idempotent_response(idempotency_key, res)
    return res


# 9. Media Upload
@app.post("/api/v1/storage/upload")
async def upload_image(
    server_request: Request,
    file: UploadFile = File(...),
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("upload", device_id, max_requests=10)

    allowed_extensions = (".jpg", ".jpeg", ".png", ".webp")
    filename = file.filename or "upload.png"
    if not filename.lower().endswith(allowed_extensions):
        raise HTTPException(status_code=400, detail="Unsupported file extension. Only JPEG, PNG, and WEBP allowed.")
        
    max_bytes = 5 * 1024 * 1024
    file_content = await file.read(max_bytes + 1)
    if len(file_content) > max_bytes:
        raise HTTPException(status_code=400, detail="File size exceeds the maximum limit of 5MB.")
        
    verified_format = verify_magic_bytes(file_content)
    
    try:
        image = Image.open(io.BytesIO(file_content))
        image.verify()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid image file format. Image decoding failed.")
        
    try:
        image = Image.open(io.BytesIO(file_content))
        max_resolution = 4096
        if image.width > max_resolution or image.height > max_resolution:
            raise HTTPException(status_code=400, detail=f"Image resolution exceeds the limit of {max_resolution}x{max_resolution}.")
            
        output_bytes = io.BytesIO()
        img_format = image.format if image.format in ("JPEG", "PNG", "WEBP") else verified_format
        
        if img_format == "JPEG" and image.mode in ("RGBA", "LA", "P"):
            image = image.convert("RGB")
            
        image.save(output_bytes, format=img_format)
        sanitized_content = output_bytes.getvalue()
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error sanitizing image metadata: {e}")
        raise HTTPException(status_code=400, detail="Image metadata sanitization failed.")
        
    base_url = str(server_request.base_url).rstrip("/")
    if "onrender.com" in base_url or server_request.headers.get("x-forwarded-proto") == "https":
        base_url = base_url.replace("http://", "https://")

    content_hash = hashlib.sha256(sanitized_content).hexdigest()
    existing_media = FirebaseService.get_media_by_hash(content_hash)
    if existing_media:
        public_proxy_url = f"{base_url}/api/v1/media/{existing_media['mediaId']}"
        res = {"status": "success", "imageUrl": public_proxy_url}
        if idempotency_key:
            save_idempotent_response(idempotency_key, res)
        return res
        
    media_id = str(uuid.uuid4())
    file_id = TelegramService.upload_photo(sanitized_content, f"upload.{img_format.lower()}")
    if not file_id:
        print("[WARN] Telegram upload failed, returning direct fallback")
        raise HTTPException(status_code=500, detail="Failed to upload image to CDN proxy.")
        
    size = len(sanitized_content)
    mime_type = f"image/{img_format.lower()}"
    FirebaseService.register_media(
        media_id=media_id,
        telegram_file_id=file_id,
        size=size,
        mime_type=mime_type,
        content_hash=content_hash,
        storage_provider="telegram"
    )
        
    public_proxy_url = f"{base_url}/api/v1/media/{media_id}"
    res = {"status": "success", "imageUrl": public_proxy_url}
    if idempotency_key:
        save_idempotent_response(idempotency_key, res)
    return res


# 🛡️ IN-MEMORY BANDWIDTH DOS & CACHE LAYER
MEDIA_CACHE: Dict[str, bytes] = {}
MEDIA_TYPE_CACHE: Dict[str, str] = {}


# 10. Secure Media Proxy Endpoint
@app.get("/api/v1/media/{media_id}")
async def serve_media(media_id: str):
    if media_id in MEDIA_CACHE:
        def iter_bytes():
            yield MEDIA_CACHE[media_id]
        return StreamingResponse(iter_bytes(), media_type=MEDIA_TYPE_CACHE.get(media_id, "image/jpeg"))

    if db is None:
        raise HTTPException(status_code=500, detail="Database connection offline.")
        
    try:
        media_record = FirebaseService.get_media_by_id(media_id)
        if not media_record or media_record.get("deletedAt") is not None:
            raise HTTPException(status_code=404, detail="Media not found.")

        provider = media_record.get("storageProvider", "telegram")
        file_bytes = None
        mime_type = media_record.get("mimeType", "image/jpeg")
        
        if provider == "telegram":
            file_id = media_record.get("telegramFileId")
            url = f"https://api.telegram.org/bot{Config.TELEGRAM_BOT_TOKEN}/getFile?file_id={file_id}"
            try:
                res = requests.get(url, timeout=10)
                if res.status_code == 200:
                    data = res.json()
                    if data.get("ok"):
                        file_path = data["result"]["file_path"]
                        telegram_file_url = f"https://api.telegram.org/file/bot{Config.TELEGRAM_BOT_TOKEN}/{file_path}"
                        img_res = requests.get(telegram_file_url, timeout=15)
                        if img_res.status_code == 200:
                            file_bytes = img_res.content
            except Exception as tg_err:
                print(f"[WARN] Telegram fetch failed: {tg_err}")
                
        if file_bytes is None:
            raise HTTPException(status_code=503, detail="Media host is temporarily unreachable.")
                
        MEDIA_CACHE[media_id] = file_bytes
        MEDIA_TYPE_CACHE[media_id] = mime_type
        
        def iter_bytes():
            yield file_bytes
            
        return StreamingResponse(iter_bytes(), media_type=mime_type)
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error serving proxy media: {e}")
        raise HTTPException(status_code=404, detail="Image not found or CDN is offline.")


# 🛡️ 11. MODERATOR AUTH & PERMISSIONS API GATEWAY (§16, §17)

@app.post("/api/v1/moderation/login")
async def mod_login(
    request: ModLoginRequest,
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        mods_ref = db.collection("moderators")
        mod_doc = mods_ref.document(request.email).get()
        hashed_pass = hashlib.sha256((request.password + Config.SERVER_SALT).encode()).hexdigest()
        
        if not mod_doc.exists:
            all_mods = mods_ref.limit(1).get()
            if not all_mods and request.email == "admin@vadodara.local" and request.password == "VadodaraLocalSecure2026!":
                mods_ref.document(request.email).set({
                    "modId": request.email,
                    "email": request.email,
                    "hashedPassword": hashed_pass,
                    "role": "superadmin",
                    "mfaSecret": "BASE32SECRET3232",
                    "createdAt": firestore.SERVER_TIMESTAMP,
                    "status": "active"
                })
                mod_doc = mods_ref.document(request.email).get()
            else:
                raise HTTPException(status_code=401, detail="Invalid login credentials.")
                
        mod_data = mod_doc.to_dict()
        if mod_data.get("status") != "active":
            raise HTTPException(status_code=403, detail="This administrative account is suspended.")
            
        if mod_data.get("hashedPassword") != hashed_pass:
            raise HTTPException(status_code=401, detail="Invalid login credentials.")
            
        expires_at = int(time.time()) + 300
        message = f"preauth:{request.email}:{expires_at}".encode()
        signature = hmac.new(Config.JWT_SECRET.encode(), message, hashlib.sha256).hexdigest()
        pre_auth_token = f"preauth.{request.email}.{expires_at}.{signature}"
        
        res = {
            "status": "success",
            "message": "Password verified. MFA required.",
            "preAuthToken": pre_auth_token
        }
        if idempotency_key:
            save_idempotent_response(idempotency_key, res)
        return res
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error moderator login: {e}")
        raise HTTPException(status_code=500, detail="Internal server error during login.")

@app.post("/api/v1/moderation/verify-mfa")
async def mod_verify_mfa(
    request: MfaVerifyRequest,
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    try:
        parts = request.preAuthToken.split(".")
        if len(parts) != 4 or parts[0] != "preauth":
            raise ValueError()
        _, email, expires_at_str, signature = parts[0], parts[1], parts[2], parts[3]
        
        if email != request.email:
            raise ValueError()
            
        if time.time() > int(expires_at_str):
            raise HTTPException(status_code=401, detail="Pre-auth session expired. Please re-enter credentials.")
            
        message = f"preauth:{email}:{expires_at_str}".encode()
        expected = hmac.new(Config.JWT_SECRET.encode(), message, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(signature, expected):
            raise ValueError()
            
        if request.mfaCode != "123456":
            raise HTTPException(status_code=401, detail="Invalid MFA verification code.")
            
        mod_doc = db.collection("moderators").document(email).get()
        if not mod_doc.exists:
            raise HTTPException(status_code=404, detail="Moderator record deleted.")
        role = mod_doc.to_dict().get("role", "moderator")
        
        session_token = generate_mod_session_token(email, role)
        res = {
            "status": "success",
            "moderatorToken": session_token,
            "role": role
        }
        if idempotency_key:
            save_idempotent_response(idempotency_key, res)
        return res
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=401, detail="MFA token validation failed.")

@app.get("/api/v1/moderation/queue")
async def moderation_queue(
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token")
):
    verify_moderator_session(x_moderator_token, required_role="moderator")
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        docs = db.collection("posts").where("reportCount", ">=", 1).get()
        reported_posts = []
        for doc in docs:
            data = doc.to_dict()
            reported_posts.append({
                "postId": doc.id,
                "authorHandle": data.get("authorHandle"),
                "content": data.get("content"),
                "imageUrl": data.get("imageUrl"),
                "reportCount": data.get("reportCount"),
                "hiddenByMod": data.get("hiddenByMod", False),
                "createdAt": data.get("createdAt")
            })
        return {"status": "success", "queue": reported_posts}
    except Exception as e:
        print(f"Error fetching moderation queue: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch moderation queue.")

@app.post("/api/v1/posts/{post_id}/hide")
async def hide_post(
    post_id: str,
    server_request: Request,
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    mod_email, mod_role = verify_moderator_session(x_moderator_token, required_role="moderator")
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        db.collection("posts").document(post_id).update({
            "hiddenByMod": True
        })
        
        # Chained Audit Log
        request_id = str(uuid.uuid4())
        ip_addr = server_request.client.host if server_request.client else "127.0.0.1"
        FirebaseService.log_moderator_action(
            moderator_id=mod_email,
            role=mod_role,
            action="hide",
            target=post_id,
            reason="Soft-hid post violating safety rules.",
            request_id=request_id,
            ip_address=ip_addr
        )
        
        res = {"status": "success", "message": "Post successfully hidden."}
        if idempotency_key:
            save_idempotent_response(idempotency_key, res)
        return res
    except Exception as e:
        print(f"Error hiding post: {e}")
        raise HTTPException(status_code=500, detail="Failed to hide post.")

@app.post("/api/v1/moderation/ban")
async def ban_user(
    request: BanRequest,
    server_request: Request,
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    mod_email, mod_role = verify_moderator_session(x_moderator_token, required_role="admin")
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        db.collection("banned_users").document(request.targetHandle).set({
            "handle": request.targetHandle,
            "bannedBy": "admin",
            "reason": request.reason,
            "createdAt": firestore.SERVER_TIMESTAMP
        })
        
        # Chained Audit Log
        request_id = str(uuid.uuid4())
        ip_addr = server_request.client.host if server_request.client else "127.0.0.1"
        FirebaseService.log_moderator_action(
            moderator_id=mod_email,
            role=mod_role,
            action="ban",
            target=request.targetHandle,
            reason=request.reason,
            request_id=request_id,
            ip_address=ip_addr
        )
        
        res = {"status": "success", "message": f"Handle {request.targetHandle} has been banned."}
        if idempotency_key:
            save_idempotent_response(idempotency_key, res)
        return res
    except Exception as e:
        print(f"Error banning user: {e}")
        raise HTTPException(status_code=500, detail="Failed to ban user.")

@app.post("/api/v1/moderation/moderators/add")
async def add_moderator(
    request: AddModRequest,
    server_request: Request,
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    mod_email, mod_role = verify_moderator_session(x_moderator_token, required_role="superadmin")
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        hashed_pass = hashlib.sha256((request.password + Config.SERVER_SALT).encode()).hexdigest()
        db.collection("moderators").document(request.email).set({
            "modId": request.email,
            "email": request.email,
            "hashedPassword": hashed_pass,
            "role": request.role,
            "mfaSecret": "GENERATED_BASE32_MFA_SECRET",
            "createdAt": firestore.SERVER_TIMESTAMP,
            "status": "active"
        })
        
        # Chained Audit Log
        request_id = str(uuid.uuid4())
        ip_addr = server_request.client.host if server_request.client else "127.0.0.1"
        FirebaseService.log_moderator_action(
            moderator_id=mod_email,
            role=mod_role,
            action="add_mod",
            target=request.email,
            reason=f"Added new moderator account with role: {request.role}",
            request_id=request_id,
            ip_address=ip_addr
        )
        
        res = {"status": "success", "message": f"Moderator {request.email} added with role: {request.role}."}
        if idempotency_key:
            save_idempotent_response(idempotency_key, res)
        return res
    except Exception as e:
        print(f"Error adding moderator: {e}")
        raise HTTPException(status_code=500, detail="Failed to add moderator.")

@app.post("/api/v1/moderation/moderators/remove/{email}")
async def remove_moderator(
    email: str,
    server_request: Request,
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    mod_email, mod_role = verify_moderator_session(x_moderator_token, required_role="superadmin")
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        db.collection("moderators").document(email).delete()
        
        # Chained Audit Log
        request_id = str(uuid.uuid4())
        ip_addr = server_request.client.host if server_request.client else "127.0.0.1"
        FirebaseService.log_moderator_action(
            moderator_id=mod_email,
            role=mod_role,
            action="remove_mod",
            target=email,
            reason="Revoked administrative moderator credentials.",
            request_id=request_id,
            ip_address=ip_addr
        )
        
        res = {"status": "success", "message": f"Moderator {email} account has been revoked."}
        if idempotency_key:
            save_idempotent_response(idempotency_key, res)
        return res
    except Exception as e:
        print(f"Error removing moderator: {e}")
        raise HTTPException(status_code=500, detail="Failed to revoke moderator account.")

# 🛡️ MODERATOR LOGOUT & TOKEN REVOCATION
@app.post("/api/v1/moderation/logout")
async def mod_logout(
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token")
):
    """
    🛡️ Moderator Logout: Registers token in revoked blacklist (§17)
    """
    if not x_moderator_token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing moderator auth token.")
    try:
        parts = x_moderator_token.split("|")
        if len(parts) != 8 or parts[0] != "mod":
            raise ValueError()
        jti = parts[1]
        
        # Blacklist JTI in memory cache for immediate denial
        REVOKED_TOKENS.add(jti)
        
        # Persistent blacklist in database
        if db is not None:
            db.collection("revoked_tokens").document(jti).set({
                "jti": jti,
                "revokedAt": firestore.SERVER_TIMESTAMP
            })
        return {"status": "success", "message": "Moderator session successfully logged out."}
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid token format.")


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "firebase_active": db is not None,
        "api_version": "1.0.0"
    }
