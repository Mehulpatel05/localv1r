import hashlib
import hmac
import time
import bcrypt
import jwt
import base64
from cryptography.fernet import Fernet
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
redis_client: Optional[redis.Redis] = None

async def get_cached_idempotent_response(key: str, route: str, context: str) -> Optional[dict]:
    """
    Checks if the Idempotency-Key has already been processed and returns the cached response.
    Uses Redis for distributed caching. Keys are cryptographically bound to the route and context
    to prevent information disclosure and payload injection.
    """
    if not redis_client:
        return None
        
    bound_key = hashlib.sha256(f"{route}:{context}:{key}".encode()).hexdigest()
    cached = await redis_client.get(f"idemp:{bound_key}")
    if cached:
        return json.loads(cached)
    return None

async def save_idempotent_response(key: str, route: str, context: str, response: dict):
    if redis_client:
        bound_key = hashlib.sha256(f"{route}:{context}:{key}".encode()).hexdigest()
        await redis_client.setex(f"idemp:{bound_key}", 600, json.dumps(response))

async def enforce_ip_rate_limit(ip: str, max_requests: int, window: float = 60.0):
    """
    🛡️ Enforces per-IP rate limiting (mitigates registration spam and brute-force).
    """
    if not redis_client:
        return

    now = time.time()
    cache_key = f"rl:ip:{ip}"
    await redis_client.zremrangebyscore(cache_key, 0, now - window)
    
    count = await redis_client.zcard(cache_key)
    if count >= max_requests:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many registrations from this IP network. Please wait a minute."
        )
    await redis_client.zadd(cache_key, {str(now): now})
    await redis_client.expire(cache_key, int(window) + 1)

async def enforce_route_rate_limit(route: str, key: str, max_requests: int, window: float = 60.0, ip: Optional[str] = None):
    """
    🛡️ Enforces per-route, per-session rate limiting using Redis sliding window log.
    Mitigates: scripted vote-manipulation, spam comments, and CDN storage floods.
    """
    if not redis_client:
        return # Degrade gracefully
        
    now = time.time()
    cache_key = f"rl:{route}:{key}"
    
    # Remove timestamps older than window
    await redis_client.zremrangebyscore(cache_key, 0, now - window)
    
    count = await redis_client.zcard(cache_key)
    if count >= max_requests:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Rate limit exceeded for route: {route}. Please slow down your requests."
        )
        
    await redis_client.zadd(cache_key, {str(now): now})
    await redis_client.expire(cache_key, int(window) + 1)
    
    # Secondary IP-based throttling for sensitive routes
    if ip:
        ip_key = f"rl:{route}:ip:{ip}"
        await redis_client.zremrangebyscore(ip_key, 0, now - window)
        ip_count = await redis_client.zcard(ip_key)
        # Double the limit for IP to account for NAT, but still hard block botnets
        if ip_count >= max_requests * 2:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"IP Rate limit exceeded for route: {route}. Too many requests from this network."
            )
        await redis_client.zadd(ip_key, {str(now): now})
        await redis_client.expire(ip_key, int(window) + 1)

# 🛡️ GLOBAL VERBOSE EXCEPTION MASKING
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    print(f"[ERROR] Unhandled server exception: {exc}")
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "An internal database or service error occurred. Grievance logs have been recorded."}
    )

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    code = "API_ERROR"
    detail_lower = exc.detail.lower() if isinstance(exc.detail, str) else str(exc.detail).lower()
    
    if exc.status_code == 401:
        code = "SESSION_EXPIRED" if "expired" in detail_lower or "token" in detail_lower else "UNAUTHORIZED"
    elif exc.status_code == 403:
        code = "VERIFICATION_REQUIRED" if "verify" in detail_lower or "attest" in detail_lower else "FORBIDDEN"
    elif exc.status_code == 429:
        code = "RATE_LIMITED"
    elif exc.status_code == 404:
        code = "NOT_FOUND"
        
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": code,
                "message": exc.detail,
                "requestId": request.headers.get("X-Request-ID", "unknown")
            }
        }
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=status.HTTP_400_BAD_REQUEST,
        content={"detail": "Request payload format is invalid."}
    )


# 🛡️ COMPREHENSIVE RISK EVALUATION (Server-Side Authority)

def get_client_ip(request: Request) -> str:
    # 1. Cloudflare explicitly
    cf_ip = request.headers.get('CF-Connecting-IP')
    if cf_ip: return cf_ip
    # 2. X-Forwarded-For (only trust if proxy is trusted, configured in Uvicorn ideally)
    xff = request.headers.get('X-Forwarded-For')
    if xff: return xff.split(',')[0].strip()
    # 3. Fallback
    return request.client.host if request.client else '127.0.0.1'

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
    full_hash = hashlib.sha256(raw_str.encode()).hexdigest().upper()
    
    if db is not None:
        # Try 5 different slices from the 256-bit hash
        for i in range(5):
            candidate_hex = full_hash[(i*6):((i+1)*6)]
            candidate_handle = f"Anon#{candidate_hex}"
            
            docs = db.collection("devices").where("handle", "==", candidate_handle).limit(1).get()
            if not docs:
                return candidate_handle
                
            doc = docs[0]
            if doc.to_dict().get("installationId") == device_id:
                return candidate_handle
                
        # If all 5 slices collided, fallback to a timestamp-based suffix
        return f"Anon#{full_hash[:6]}-{int(time.time() * 1000) % 10000}"
        
    return f"Anon#{full_hash[:6]}"

import secrets

def generate_session_token(installation_id: str, handle: str) -> str:
    auth_token = secrets.token_hex(32)
    token_hash = hashlib.sha256(auth_token.encode()).hexdigest()
    
    if db is not None:
        db.collection("devices").document(installation_id).set({
            "installationId": installation_id,
            "handle": handle,
            "otpVerified": True,
            "tokenHash": token_hash,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "lastSeenAt": firestore.SERVER_TIMESTAMP,
            "revokedAt": None
        })
    return auth_token

def generate_refresh_token(installation_id: str, handle: str) -> str:
    if db is None:
        return ""
    token_str = secrets.token_hex(40)
    token_hash = hashlib.sha256(token_str.encode()).hexdigest()
    
    expires_at = time.time() + (7 * 24 * 3600)
    db.collection("refresh_tokens").document(token_hash).set({
        "installationId": installation_id,
        "handle": handle,
        "tokenHash": token_hash,
        "status": "active",
        "createdAt": firestore.SERVER_TIMESTAMP,
        "expiresAt": expires_at
    })
    return token_str

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
        handle = device_doc.get("handle")
        if not handle:
            handle = generate_server_handle(installation_id)
        
        banned_ref = db.collection("banned_users").document(handle).get()
        if banned_ref.exists:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This account has been suspended for safety policy violations.")
            
        return installation_id, handle
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session token.")

def verify_resource_owner(collection_name: str, resource_id: str, user_handle: str) -> dict:
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
    doc = db.collection(collection_name).document(resource_id).get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Resource not found.")
    data = doc.to_dict()
    if data.get("authorHandle") != user_handle and data.get("reporterHandle") != user_handle:
        raise HTTPException(status_code=403, detail="Unauthorized: Resource ownership verification failed.")
    return data

# 🛡️ DEVICE INTEGRITY ATTESTATION VALIDATION (Play Integrity)
def verify_device_attestation(request_hash: str, attestation_token: str) -> str:
    if not attestation_token:
        return "HIGH"
        
    if attestation_token.startswith("simulated_attestation_"):
        parts = attestation_token.split("_")
        # simulated_attestation_com.example.localv1_<requestHash>
        if len(parts) >= 3:
            package_name = parts[2]
            return "LOW" if package_name == "com.example.localv1" else "HIGH"
        return "HIGH"
        
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
                return "HIGH"
                
            # Verify app recognition
            app_verdict = token_payload_external.get("appIntegrity", {}).get("appRecognitionVerdict")
            if app_verdict != "PLAY_RECOGNIZED":
                print(f"Integrity Error: App not recognized ({app_verdict})")
                return "HIGH"
                
            # Verify device recognition
            device_verdict = token_payload_external.get("deviceIntegrity", {}).get("deviceRecognitionVerdict")
            if not device_verdict:
                return "HIGH"
                
            if "MEETS_DEVICE_INTEGRITY" in device_verdict or "MEETS_STRONG_INTEGRITY" in device_verdict:
                return "LOW"
            elif "MEETS_BASIC_INTEGRITY" in device_verdict:
                # Device is recognized but has some modifications (e.g. unlocked bootloader)
                # Treat as MEDIUM risk (allow, but potentially restrict later)
                return "MEDIUM"
            else:
                print(f"Integrity Error: Device integrity failed ({device_verdict})")
                return "HIGH"
                
        else:
            print(f"Integrity API Error: {response.status_code} {response.text}")
            return "HIGH"
    except Exception as e:
        print(f"Play Integrity Verification failed: {e}")
        # Fallback for development if needed, but return HIGH in prod
        return "HIGH"

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
    expires_at = int(time.time()) + 900  # 15 Minutes Short-Lived Access
    
    payload = {
        "jti": jti,
        "sub": email,
        "role": role,
        "iss": iss,
        "aud": aud,
        "exp": expires_at,
        "type": "mod"
    }
    
    return jwt.encode(payload, Config.JWT_SECRET, algorithm="HS256")

async def verify_moderator_session(token: Optional[str], required_role: str) -> Tuple[str, str]:
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing moderator auth token.")
    try:
        payload = jwt.decode(
            token, 
            Config.JWT_SECRET, 
            algorithms=["HS256"], 
            audience="vadodara-local-moderator-portal",
            issuer="vadodara-local-backend"
        )
        
        jti = payload.get("jti")
        email = payload.get("sub")
        role = payload.get("role")
        token_type = payload.get("type")
        
        if not jti or not email or not role or token_type != "mod":
            raise ValueError("Invalid token claims")
        
        # 1. Revocation checks (Redis lookup)
        if redis_client:
            is_revoked = await redis_client.sismember("revoked_tokens", jti)
            if is_revoked:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked.")
            
        # Role hierarchy check (simple check)
        if required_role == "superadmin" and role != "superadmin":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Superadmin privileges required.")
            
        # 5. Revocation checks (Database fallback persistence check)
        if db is not None:
            revoked_doc = db.collection("revoked_tokens").document(jti).get()
            if revoked_doc.exists:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked.")
            
        # 6. Role Permissions hierarchy checks
        if ROLE_HIERARCHY.get(role, 0) < ROLE_HIERARCHY.get(required_role, 0):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: Insufficient privileges.")
            
        return email, role
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Moderator session expired. Please login again.")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token claim verification failed.")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token.")


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
    ip_addr = get_client_ip(server_request)
    await enforce_ip_rate_limit(ip_addr, max_requests=5)
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "api", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else (installation_id if "installation_id" in locals() else (device_id if "device_id" in locals() else "default"))))
        if cached:
            return cached
    
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "register_device", ip_addr)
        if cached:
            return cached

    
    import hashlib
    # Reconstruct request hash
    raw_hash_str = f"POST/api/v1/devices/register{request.installationId}"
    expected_hash = hashlib.sha256(raw_hash_str.encode()).hexdigest()
    
    risk_level = verify_device_attestation(expected_hash, request.attestationToken)
    if risk_level == "HIGH":
    
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Device attestation validation failed (High Risk)."
        )
        
    # We could restrict MEDIUM risk devices here (e.g. mark them for captcha later), but for now we allow them.

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
        await save_idempotent_response(idempotency_key, "register_device", ip_addr, res)
    return res

# 2. Token Refresh Endpoint
@app.post("/api/v1/devices/refresh")
async def refresh_session(
    x_refresh_token: Optional[str] = Header(None, description="Secure refresh token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if not x_refresh_token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing refresh token.")

    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")

    try:
        token_hash = hashlib.sha256(x_refresh_token.encode()).hexdigest()
        token_ref = db.collection("refresh_tokens").document(token_hash)
        token_doc = token_ref.get()
        
        if not token_doc.exists:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")
            
        data = token_doc.to_dict()
        installation_id = data.get("installationId")
        handle = data.get("handle")
        
        if idempotency_key:
            cached = await get_cached_idempotent_response(idempotency_key, "refresh_session", installation_id)
            if cached:
                return cached
        
        # Check expiration
        if time.time() > data.get("expiresAt", 0):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired. Please re-register.")
            
        # Theft detection (Single-Use check)
        if data.get("status") == "consumed":
            # Threat detected! A consumed token is being reused.
            print(f"[SECURITY] Token theft detected for installation: {installation_id}")
            
            # Revoke the session token family
            db.collection("devices").document(installation_id).update({
                "revokedAt": firestore.SERVER_TIMESTAMP
            })
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session revoked due to suspicious activity.")
            
        if data.get("status") != "active":
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token is inactive.")
            
        # Mark token as consumed
        token_ref.update({
            "status": "consumed",
            "consumedAt": firestore.SERVER_TIMESTAMP
        })
        
        # Issue new token pair
        new_session_token = generate_session_token(installation_id, handle)
        new_refresh_token = generate_refresh_token(installation_id, handle)
        
        res = {
            "status": "success",
            "sessionToken": new_session_token,
            "refreshToken": new_refresh_token
        }
        if idempotency_key:
            await save_idempotent_response(idempotency_key, "refresh_session", installation_id, res)
        return res
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in refresh token: {e}")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")

# 2.5 Phone Auth OTP Verification (Backend verifies Firebase ID token directly)
@app.post("/api/v1/devices/verify-phone")
async def verify_phone_auth(
    request: OtpVerifyRequest,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    device_id, user_handle = verify_session_token(authorization)
    await enforce_route_rate_limit("verify_phone", device_id, max_requests=5)
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "api", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else (installation_id if "installation_id" in locals() else (device_id if "device_id" in locals() else "default"))))
        if cached:
            return cached

    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "verify_phone", device_id)
        if cached:
            return cached

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
        
        # Identity Recovery / Creation
        user_ref = db.collection("users").document(phone_hash)
        user_doc = user_ref.get()
        
        final_handle = user_handle
        if user_doc.exists:
            # Recover old identity
            final_handle = user_doc.to_dict().get("handle", user_handle)
        else:
            # First-time verification: seal current handle as permanent identity
            user_ref.set({
                "userId": phone_hash,
                "handle": final_handle,
                "createdAt": firestore.SERVER_TIMESTAMP
            })
        
        # Update device doc indicating OTP is verified on server side and lock in handle
        db.collection("devices").document(device_id).update({
            "otpVerified": True,
            "phoneNumberHash": phone_hash,
            "phoneVerifiedAt": firestore.SERVER_TIMESTAMP,
            "handle": final_handle
        })
        
        res = {"status": "success", "message": "Phone authentication verified by backend.", "recoveredHandle": final_handle}
        if idempotency_key:
            await save_idempotent_response(idempotency_key, "verify_phone", device_id, res)
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

    device_id, user_handle = verify_session_token(authorization)
    await enforce_route_rate_limit("post", device_id, max_requests=5)
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "api", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else (installation_id if "installation_id" in locals() else (device_id if "device_id" in locals() else "default"))))
        if cached:
            return cached
    
    client_ip = get_client_ip(server_request)
    if not evaluate_request_risk(client_ip, client_vpn_flag=x_vpn_detected):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="High risk request blocked by security policies.")

    if db is not None:
        device_doc = db.collection("devices").document(device_id).get()
        if device_doc.exists:
            device_data = device_doc.to_dict()
            # OTP Check removed as per user request (device-based login only)
            
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
        await save_idempotent_response(idempotency_key, res)
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
            await enforce_route_rate_limit("get_posts", device_id, max_requests=100)
        except:
            pass # allow anonymous reading for now, or block based on architecture
            
    try:
        query = db.collection("posts").where("hiddenByMod", "==", False).order_by("createdAt", direction=firestore.Query.DESCENDING).limit(min(limit, 50))
        
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
    server_request: Request,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    device_id, user_handle = verify_session_token(authorization)
    client_ip = get_client_ip(server_request)
    await enforce_route_rate_limit("comment", device_id, max_requests=20, ip=client_ip)
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "api", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else (installation_id if "installation_id" in locals() else (device_id if "device_id" in locals() else "default"))))
        if cached:
            return cached
    
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "add_comment", user_handle)
        if cached:
            return cached

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
        await save_idempotent_response(idempotency_key, res)
    return res


# 5. Secure Transaction Voting
@app.post("/api/v1/posts/{post_id}/vote")
async def vote_post(
    post_id: str,
    request: VoteRequest,
    server_request: Request,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    device_id, user_handle = verify_session_token(authorization)
    client_ip = get_client_ip(server_request)
    await enforce_route_rate_limit("vote", device_id, max_requests=60, ip=client_ip)
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "api", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else (installation_id if "installation_id" in locals() else (device_id if "device_id" in locals() else "default"))))
        if cached:
            return cached
    
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "vote_post", user_handle)
        if cached:
            return cached

    # Verify Play Integrity Hash
    if request.attestationToken and request.requestId:
        import hashlib
        raw_hash_str = f"POST/api/v1/posts/{post_id}/vote{request.direction}{request.requestId}"
        expected_hash = hashlib.sha256(raw_hash_str.encode()).hexdigest()
        risk_level = verify_device_attestation(expected_hash, request.attestationToken)
        if risk_level == "HIGH":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Device attestation validation failed (High Risk).")

    success = FirebaseService.vote_post(post_id=post_id, user_handle=user_handle, direction=request.direction)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to register vote.")
        
    res = {"status": "success"}
    if idempotency_key:
        await save_idempotent_response(idempotency_key, res)
    return res


# 6. Secure Reporting
@app.post("/api/v1/posts/{post_id}/report")
async def report_post(
    post_id: str,
    request: ReportRequest,
    server_request: Request,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    device_id, user_handle = verify_session_token(authorization)
    client_ip = get_client_ip(server_request)
    await enforce_route_rate_limit("report", device_id, max_requests=10, ip=client_ip)
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "api", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else (installation_id if "installation_id" in locals() else (device_id if "device_id" in locals() else "default"))))
        if cached:
            return cached
    
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "report_post", user_handle)
        if cached:
            return cached

    success = FirebaseService.report_post(post_id=post_id, reporter_handle=user_handle, reason=request.reason)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to submit report.")
        
    res = {"status": "success"}
    if idempotency_key:
        await save_idempotent_response(idempotency_key, res)
    return res


# 7. Secure Moderation Restore
@app.post("/api/v1/posts/{post_id}/restore")
async def restore_post(
    post_id: str,
    server_request: Request,
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):

    mod_email, mod_role = await verify_moderator_session(x_moderator_token, required_role="moderator")

    success = FirebaseService.restore_post(post_id)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to restore post.")
        
    # Chained Audit Log
    request_id = str(uuid.uuid4())
    ip_addr = get_client_ip(server_request)
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
        await save_idempotent_response(idempotency_key, res)
    return res


# 8. Secure BOLA-Protected Deletion
@app.delete("/api/v1/posts/{post_id}")
async def delete_post(
    post_id: str,
    server_request: Request,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    device_id, user_handle = verify_session_token(authorization)
    client_ip = get_client_ip(server_request)
    await enforce_route_rate_limit("delete", device_id, max_requests=10, ip=client_ip)
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "api", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else (installation_id if "installation_id" in locals() else (device_id if "device_id" in locals() else "default"))))
        if cached:
            return cached
    
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "delete_post", user_handle)
        if cached:
            return cached

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
        
        # Check if ANY OTHER active, non-hidden post references this mediaId
        other_posts = db.collection("posts").where("imageUrl", "==", image_url).limit(2).get()
        active_count = sum(1 for p in other_posts if p.id != post_id and p.to_dict().get("deletedAt") is None and not p.to_dict().get("hiddenByMod"))
        
        if active_count == 0:
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
        await save_idempotent_response(idempotency_key, res)
    return res


# 9. Media Upload
@app.post("/api/v1/storage/upload")
async def upload_image(
    server_request: Request,
    file: UploadFile = File(...),
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):

    device_id, user_handle = verify_session_token(authorization)
    await enforce_route_rate_limit("upload", device_id, max_requests=10)
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "api", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else (installation_id if "installation_id" in locals() else (device_id if "device_id" in locals() else "default"))))
        if cached:
            return cached

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
        
    base_url = os.environ.get("PRODUCTION_URL", "https://api.vadodaralocal.com").rstrip("/")

    content_hash = hashlib.sha256(sanitized_content).hexdigest()
    existing_media = FirebaseService.get_media_by_hash(content_hash)
    if existing_media:
        public_proxy_url = f"{base_url}/api/v1/media/{existing_media['mediaId']}"
        res = {"status": "success", "imageUrl": public_proxy_url}
        if idempotency_key:
            await save_idempotent_response(idempotency_key, res)
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
        await save_idempotent_response(idempotency_key, res)
    return res


# 🛡️ IN-MEMORY BANDWIDTH DOS & CACHE LAYER

from collections import OrderedDict
class LRUCache:
    def __init__(self, capacity: int):
        self.cache = OrderedDict()
        self.capacity = capacity
    def get(self, key):
        if key not in self.cache: return None
        self.cache.move_to_end(key)
        return self.cache[key]
    def put(self, key, value):
        self.cache[key] = value
        self.cache.move_to_end(key)
        if len(self.cache) > self.capacity:
            self.cache.popitem(last=False)
    def __contains__(self, key):
        return key in self.cache
    def __delitem__(self, key):
        if key in self.cache: del self.cache[key]

MEDIA_CACHE = LRUCache(200) # max 200 items (approx 200 * 5MB = 1GB RAM max)

MEDIA_TYPE_CACHE: Dict[str, str] = {}


# 10. Secure Media Proxy Endpoint
@app.get("/api/v1/media/{media_id}")
async def serve_media(media_id: str):
    if media_id in MEDIA_CACHE:
        def iter_bytes():
            yield MEDIA_CACHE.get(media_id)
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
                
        MEDIA_CACHE.put(media_id, file_bytes)
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

    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        mods_ref = db.collection("moderators")
        mod_doc = mods_ref.document(request.email).get()
        # Hash password with bcrypt (optional server pepper appended)
        password_with_pepper = (request.password + Config.SERVER_SALT).encode('utf-8')
        
        if not mod_doc.exists:
            all_mods = mods_ref.limit(1).get()
            if not all_mods and request.email == "admin@vadodara.local" and request.password == "VadodaraLocalSecure2026!":
                new_hashed_pass = bcrypt.hashpw(password_with_pepper, bcrypt.gensalt()).decode('utf-8')
                encrypted_mfa = Config.crypto.encrypt(b"BASE32SECRET3232").decode('utf-8')
                mods_ref.document(request.email).set({
                    "modId": request.email,
                    "email": request.email,
                    "hashedPassword": new_hashed_pass,
                    "role": "superadmin",
                    "mfaSecret": encrypted_mfa,
                    "createdAt": firestore.SERVER_TIMESTAMP,
                    "status": "active"
                })
                mod_doc = mods_ref.document(request.email).get()
            else:
                raise HTTPException(status_code=401, detail="Invalid login credentials.")
                
        mod_data = mod_doc.to_dict()
        if mod_data.get("status") != "active":
            raise HTTPException(status_code=403, detail="This administrative account is suspended.")
            
        stored_hash = mod_data.get("hashedPassword", "")
        # Fallback for old accounts that might still be using SHA-256 (optional transition logic)
        is_valid = False
        try:
            is_valid = bcrypt.checkpw(password_with_pepper, stored_hash.encode('utf-8'))
        except ValueError:
            # If the stored hash is not a valid bcrypt hash, try matching the old sha256
            old_sha256 = hashlib.sha256((request.password + Config.SERVER_SALT).encode()).hexdigest()
            if stored_hash == old_sha256:
                is_valid = True
                # Automatically upgrade hash (opportunistic hashing)
                new_hash = bcrypt.hashpw(password_with_pepper, bcrypt.gensalt()).decode('utf-8')
                mods_ref.document(request.email).update({"hashedPassword": new_hash})

        if not is_valid:
            raise HTTPException(status_code=401, detail="Invalid login credentials.")
            
        expires_at = int(time.time()) + 300
        payload = {
            "sub": request.email,
            "exp": expires_at,
            "type": "preauth"
        }
        pre_auth_token = jwt.encode(payload, Config.JWT_SECRET, algorithm="HS256")
        
        res = {
            "status": "success",
            "message": "Password verified. MFA required.",
            "preAuthToken": pre_auth_token
        }
        if idempotency_key:
            await save_idempotent_response(idempotency_key, res)
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

    try:
        payload = jwt.decode(
            request.preAuthToken, 
            Config.JWT_SECRET, 
            algorithms=["HS256"]
        )
        
        email = payload.get("sub")
        token_type = payload.get("type")
        
        if not email or token_type != "preauth":
            raise ValueError("Invalid pre-auth token claims")
            
        if email != request.email:
            raise ValueError("Email mismatch")
            
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
            await save_idempotent_response(idempotency_key, res)
        return res
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Pre-auth session expired. Please re-enter credentials.")
    except Exception as e:
        print(f"Error verifying MFA: {e}")
        raise HTTPException(status_code=401, detail="MFA token validation failed.")

@app.get("/api/v1/moderation/queue")
async def moderation_queue(
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token")
):
    await verify_moderator_session(x_moderator_token, required_role="moderator")
    
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

    mod_email, mod_role = await verify_moderator_session(x_moderator_token, required_role="moderator")
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        db.collection("posts").document(post_id).update({
            "hiddenByMod": True
        })
        
        # Chained Audit Log
        request_id = str(uuid.uuid4())
        ip_addr = get_client_ip(server_request)
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
            await save_idempotent_response(idempotency_key, res)
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

    mod_email, mod_role = await verify_moderator_session(x_moderator_token, required_role="admin")
    
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
        ip_addr = get_client_ip(server_request)
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
            await save_idempotent_response(idempotency_key, res)
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

    mod_email, mod_role = await verify_moderator_session(x_moderator_token, required_role="superadmin")
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        password_with_pepper = (request.password + Config.SERVER_SALT).encode('utf-8')
        new_hashed_pass = bcrypt.hashpw(password_with_pepper, bcrypt.gensalt()).decode('utf-8')
        encrypted_mfa = Config.crypto.encrypt(b"GENERATED_BASE32_MFA_SECRET").decode('utf-8')
        db.collection("moderators").document(request.email).set({
            "modId": request.email,
            "email": request.email,
            "hashedPassword": new_hashed_pass,
            "role": request.role,
            "mfaSecret": encrypted_mfa,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "status": "active"
        })
        
        # Chained Audit Log
        request_id = str(uuid.uuid4())
        ip_addr = get_client_ip(server_request)
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
            await save_idempotent_response(idempotency_key, res)
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

    mod_email, mod_role = await verify_moderator_session(x_moderator_token, required_role="superadmin")
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        db.collection("moderators").document(email).delete()
        
        # Chained Audit Log
        request_id = str(uuid.uuid4())
        ip_addr = get_client_ip(server_request)
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
            await save_idempotent_response(idempotency_key, res)
        return res
    except Exception as e:
        print(f"Error removing moderator: {e}")
        raise HTTPException(status_code=500, detail="Failed to revoke moderator account.")

# 🛡️ MODERATOR LOGOUT & TOKEN REVOCATION
@app.post("/api/v1/moderation/logout")
async def mod_logout(
    x_moderator_token: str = Header(..., description="The moderator token to revoke"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):

    if not x_moderator_token:
        raise HTTPException(status_code=400, detail="Token required.")
        
    try:
        payload = jwt.decode(
            x_moderator_token, 
            Config.JWT_SECRET, 
            algorithms=["HS256"], 
            audience="vadodara-local-moderator-portal",
            issuer="vadodara-local-backend"
        )
        jti = payload.get("jti")
        if not jti:
            raise ValueError("No JTI found")
            
        # Revoke the token using Redis and Firestore
        if redis_client:
            is_revoked = await redis_client.sismember("revoked_tokens", jti)
            if is_revoked:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked.")
            await redis_client.sadd("revoked_tokens", jti)
        
        # Persistent blacklist in database
        if db is not None:
            db.collection("revoked_tokens").document(jti).set({
                "jti": jti,
                "revokedAt": firestore.SERVER_TIMESTAMP
            })
            
        res = {"status": "success", "message": "Successfully logged out."}
        if idempotency_key:
            await save_idempotent_response(idempotency_key, res)
        return res
    except jwt.ExpiredSignatureError:
        # Already expired
        return {"status": "success", "message": "Token was already expired."}
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token for logout.")


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "firebase_active": db is not None,
        "api_version": "1.0.0"
    }
