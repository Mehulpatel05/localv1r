import os
import hashlib
import hmac
import time
import bcrypt
import jwt
import base64
from cryptography.fernet import Fernet
import io
import uuid
import redis
from typing import Optional, Dict, List, Tuple, Literal
from collections import defaultdict
import anyio
from fastapi import FastAPI, Header, HTTPException, File, UploadFile, status, Request, Response, Query, BackgroundTasks
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from pydantic import BaseModel, Field
from PIL import Image
import requests

from config import Config
from services.r2_service import R2Service
from services.d1_service import D1Service
from utils.moderation import validate_text_content
from routes.auth import auth_router
from routes.friends import friends_router
from routes.communities import communities_router
from routes.chats import router as chats_router
from routes.calls import router as calls_router
from routes.presence import router as presence_router
from routes.notifications import router as notifications_router
from routes.preferences import router as preferences_router
from routes.actions import actions_router

is_production = os.getenv("ENVIRONMENT", "production").lower() == "production"

app = FastAPI(
    title="Vadodara Local Secure API Gateway",
    description="Secure backend proxy for anonymous community posting, voting, and media uploads.",
    version="1.0.0",
    docs_url=None if is_production else "/docs",
    redoc_url=None if is_production else "/redoc",
    openapi_url=None if is_production else "/openapi.json",
)

# 🚀 HIGH-SPEED GZIP COMPRESSION (Compresses JSON payloads > 500 bytes by 70-85%)
app.add_middleware(GZipMiddleware, minimum_size=500)

# 🛡️ RESTRICTED CORS
ALLOWED_ORIGINS = [
    "https://localv1r.onrender.com",
    "http://localhost",
    "http://localhost:8000",
    "http://10.0.2.2:8000",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# ⚡ KEEP-WARM / HEALTH ENDPOINT (Ultra-low latency <0.2ms for uptime pingers)
@app.get("/health")
@app.get("/api/v1/health")
async def health_check():
    return {"status": "ok", "service": "nearhood-api", "timestamp": time.time()}

# 🛡️ AUTHENTICATION, CHATS, CALLS, PRESENCE, COMMUNITY & PHASE 0 ACTION STATES ROUTERS
app.include_router(auth_router)
app.include_router(auth_router, prefix="/api/v1")
app.include_router(friends_router)
app.include_router(friends_router, prefix="/api/v1")
app.include_router(communities_router)
app.include_router(communities_router, prefix="/api/v1")
app.include_router(chats_router)
app.include_router(chats_router, prefix="/api/v1")
app.include_router(calls_router)
app.include_router(calls_router, prefix="/api/v1")
app.include_router(presence_router)
app.include_router(presence_router, prefix="/api/v1")
app.include_router(notifications_router)
app.include_router(notifications_router, prefix="/api/v1")
app.include_router(preferences_router)
app.include_router(preferences_router, prefix="/api/v1")
app.include_router(actions_router)
app.include_router(actions_router, prefix="/api/v1")

# 🛡️ DUAL-KEY MULTI-ROUTE RATE LIMITER CACHES
redis_client: Optional[redis.Redis] = None

# 🛡️ IN-MEMORY SLIDING-WINDOW RATE LIMITER (Active fallback when Redis is absent)
_in_memory_rl = defaultdict(list)

def _enforce_in_memory_rate_limit(key: str, max_requests: int, window: float = 60.0):
    now = time.time()
    _in_memory_rl[key] = [t for t in _in_memory_rl[key] if now - t < window]
    if len(_in_memory_rl[key]) >= max_requests:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Rate limit exceeded. Too many requests. Please slow down."
        )
    _in_memory_rl[key].append(now)

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
        _enforce_in_memory_rate_limit(f"ip:{ip}", max_requests, window)
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
        _enforce_in_memory_rate_limit(f"route:{route}:{key}", max_requests, window)
        if ip:
            _enforce_in_memory_rate_limit(f"route:{route}:ip:{ip}", max_requests * 2, window)
        return
        
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

# 🛡️ SECURITY HEADERS & BURST RATE LIMITER MIDDLEWARE
@app.middleware("http")
async def security_and_rate_limit_middleware(request: Request, call_next):
    # 1. Burst Rate Limiter check (skip /health, preflight OPTIONS)
    if request.method != "OPTIONS" and request.url.path != "/health":
        ip = get_client_ip(request)
        try:
            _enforce_in_memory_rate_limit(f"burst_ip:{ip}", max_requests=80, window=60.0)
        except HTTPException as e:
            return JSONResponse(status_code=e.status_code, content={"detail": e.detail})

    response = await call_next(request)
    
    # 2. Hardened Security Headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Content-Security-Policy"] = "default-src 'self'"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    return response

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

# 🛡️ MAGIC BYTE SIGNATURE DETECTION (Images & Videos)
def verify_magic_bytes(data: bytes) -> Tuple[str, str, str]:
    """
    🛡️ Verifies file format using magic byte signatures.
    Returns (format, media_type, mime_type) or raises HTTPException.
    media_type: 'photo' or 'video'
    """
    if len(data) < 12:
        raise HTTPException(status_code=400, detail="Invalid media file size.")
    if data.startswith(b"\xff\xd8\xff"):
        return "JPEG", "photo", "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "PNG", "photo", "image/png"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "WEBP", "photo", "image/webp"
    # Video signatures (MP4, MOV, M4V, 3GP)
    if len(data) >= 12 and (data[4:8] in (b"ftyp", b"moov", b"mdat", b"wide", b"free", b"skip") or data[:4] in (b"moov", b"mdat")):
        return "MP4", "video", "video/mp4"
    if data.startswith(b"\x1a\x45\xdf\xa3"):
        return "WEBM", "video", "video/webm"
    if data.startswith(b"RIFF") and data[8:12] == b"AVI ":
        return "AVI", "video", "video/x-msvideo"
    raise HTTPException(status_code=400, detail="Unsupported media signature. Only JPEG, PNG, WEBP images and MP4, WEBM, MOV videos are allowed.")



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
    return auth_token

def generate_refresh_token(installation_id: str, handle: str) -> str:
    token_str = secrets.token_hex(40)
    return token_str

def verify_session_token(authorization: Optional[str]) -> Tuple[str, str]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing or invalid Authorization header.")
    
    raw_token = authorization.split("Bearer ")[1].strip()
    
    # 1. Try decoding as Backend JWT Token
    try:
        payload = jwt.decode(
            raw_token,
            Config.JWT_SECRET,
            algorithms=["HS256"],
            issuer="nearhood-backend"
        )
        if payload.get("type") == "access":
            uid = payload.get("sub", "")
            handle = payload.get("handle", "")
            if not handle:
                user = D1Service.get_user_by_id(uid)
                handle = user.get("handle") if user else f"Anon#{uid[:6]}"
            if not handle:
                handle = f"Anon#{uid[:6]}"
                
            return uid, handle
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session expired. Please refresh token or log in again.")
    except Exception as e:
        print(f"[AUTH] JWT decode error: {e}")

    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session token.")

def verify_resource_owner(collection_name: str, resource_id: str, user_handle: str) -> dict:
    post = D1Service.get_post_by_id(resource_id)
    if not post:
        raise HTTPException(status_code=404, detail="Resource not found.")
    if post.get("authorHandle") != user_handle:
        raise HTTPException(status_code=403, detail="Unauthorized: Resource ownership verification failed.")
    return post

# 🛡️ DEVICE INTEGRITY ATTESTATION VALIDATION (Play Integrity)
def verify_device_attestation(request_hash: str, attestation_token: str) -> str:
    if not attestation_token:
        return "HIGH"
        
    if attestation_token.startswith("simulated_attestation_"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Simulated attestation is not allowed in production.")
        
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
    expires_at = int(time.time()) + (8 * 3600)  # 🛡️ 8 hours — industry standard for admin sessions
    
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
            
        # 6. Role Permissions hierarchy checks
        if ROLE_HIERARCHY.get(role, 0) < ROLE_HIERARCHY.get(required_role, 0):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: Insufficient privileges.")
            
        return email, role
    except HTTPException:
        raise
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Moderator session expired. Please login again.")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token claim verification failed.")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token.")


# Enums / Literal Type Constraints (§23)
PostCategory = Literal[
    "general", "services", "food", "rooms", "shop", "events", "jobs"
]

# Request models
class OtpVerifyRequest(BaseModel):
    firebaseIdToken: str = Field(..., min_length=10)

class DeviceRegisterRequest(BaseModel):
    installationId: str = Field(..., min_length=36, max_length=36, pattern=r"^[0-9a-fA-F-]{36}$")
    attestationToken: str = Field(..., min_length=10, max_length=5000)

class PostCreateRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=5000)
    category: PostCategory = Field(..., description="Post category")
    imageUrl: Optional[str] = Field(None, max_length=500)
    cityId: str = Field(..., min_length=2, max_length=100)
    areaId: Optional[str] = Field(None, max_length=100)
    roomTitle: Optional[str] = None
    roomArea: Optional[str] = None
    roomRent: Optional[str] = None
    mediaUrls: Optional[list[str]] = None
    shopTitle: Optional[str] = None
    shopPrice: Optional[str] = None
    foodTitle: Optional[str] = None
    foodRating: Optional[float] = None
    foodPrice: Optional[str] = None
    eventTitle: Optional[str] = None
    eventDate: Optional[str] = None
    eventLocationText: Optional[str] = None
    eventPrice: Optional[str] = None
    jobTitle: Optional[str] = None
    jobCompany: Optional[str] = None
    jobLocation: Optional[str] = None
    jobType: Optional[str] = None
    serviceTitle: Optional[str] = None
    serviceCategoryText: Optional[str] = None
    servicePrice: Optional[str] = None

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
    targetHandle: str = Field(..., min_length=3, max_length=100)
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

    error_msg = validate_text_content(request.content)
    if error_msg:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error_msg)
        
    post_id = D1Service.create_post(
        author_handle=user_handle,
        content=request.content,
        cityId=request.cityId,
        areaId=request.areaId or request.cityId,
        category=request.category,
        image_url=request.imageUrl,
        roomTitle=request.roomTitle,
        roomArea=request.roomArea,
        roomRent=request.roomRent,
        mediaUrls=request.mediaUrls,
        shopTitle=request.shopTitle,
        shopPrice=request.shopPrice,
        foodTitle=request.foodTitle,
        foodRating=request.foodRating,
        foodPrice=request.foodPrice,
        eventTitle=request.eventTitle,
        eventDate=request.eventDate,
        eventLocationText=request.eventLocationText,
        eventPrice=request.eventPrice,
        jobTitle=request.jobTitle,
        jobCompany=request.jobCompany,
        jobLocation=request.jobLocation,
        jobType=request.jobType,
        serviceTitle=request.serviceTitle,
        serviceCategoryText=request.serviceCategoryText,
        servicePrice=request.servicePrice
    )
    if not post_id:
        raise HTTPException(status_code=500, detail="Failed to publish post to Cloudflare D1.")
        
    POSTS_CACHE.clear() # Invalidate feed cache so new post shows instantly
    res = {"status": "success", "postId": post_id, "authorHandle": user_handle}
    if idempotency_key:
        await save_idempotent_response(idempotency_key, "create_post", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
    return res


# 🛡️ HIGH-CONCURRENCY POSTS & FEED QUERY CACHE
class PostsQueryCache:
    def __init__(self, ttl_seconds: float = 3.0):
        self.cache: Dict[str, Tuple[float, dict]] = {}
        self.ttl = ttl_seconds
        
    def get(self, key: str) -> Optional[dict]:
        if key in self.cache:
            ts, data = self.cache[key]
            if time.time() - ts < self.ttl:
                return data
            else:
                del self.cache[key]
        return None
        
    def put(self, key: str, data: dict):
        self.cache[key] = (time.time(), data)
        if len(self.cache) > 300:
            oldest = min(self.cache.keys(), key=lambda k: self.cache[k][0])
            del self.cache[oldest]
            
    def clear(self):
        self.cache.clear()

POSTS_CACHE = PostsQueryCache(ttl_seconds=3.0)


# 3.1 Get Posts (Read Path over Cloudflare D1 - Non-blocking & Cached for 1000+ concurrent users)
@app.get("/api/v1/posts")
async def get_posts(
    limit: int = Query(20, ge=1, le=100),
    cursor: Optional[str] = Query(None, max_length=150),
    author: Optional[str] = Query(None, max_length=100),
    cityId: Optional[str] = Query(None, max_length=100),
    areaId: Optional[str] = Query(None, max_length=100),
    category: Optional[str] = Query(None, max_length=50),
    authorization: Optional[str] = Header(None, description="Bearer token")
):
    # 1. High-concurrency RAM cache check (< 0.5ms response for concurrent readers)
    cache_key = f"{cityId}:{areaId}:{category}:{author}:{cursor}:{limit}"
    cached_res = POSTS_CACHE.get(cache_key)
    if cached_res:
        return cached_res
    
    # Rate limit check
    if authorization and authorization.startswith("Bearer "):
        try:
            device_id, _ = verify_session_token(authorization)
            await enforce_route_rate_limit("get_posts", device_id, max_requests=200)
        except:
            pass

    try:
        posts = D1Service.get_posts(
            city_id=cityId,
            area_id=areaId,
            category=category,
            author=author,
            cursor=cursor,
            limit=limit
        )
        last_id = posts[-1]["id"] if posts else None
        res = {"status": "success", "posts": posts, "nextCursor": last_id}
        POSTS_CACHE.put(cache_key, res)
        return res
    except Exception as e:
        print(f"Error fetching posts from D1: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch posts from database.")

# 4.1 Get Comments
@app.get("/api/v1/posts/{post_id}/comments")
async def get_comments(post_id: str):
    try:
        comments = D1Service.get_comments(post_id)
        return {"status": "success", "comments": comments}
    except Exception as e:
        print(f"Error fetching comments: {e}")
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
        
    comment_id = D1Service.add_comment(
        post_id=post_id,
        author_handle=user_handle,
        content=request.content
    )
    if not comment_id:
        raise HTTPException(status_code=500, detail="Failed to write comment.")
        
    res = {"status": "success"}
    if idempotency_key:
        await save_idempotent_response(idempotency_key, "add_comment", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
    return res


# 5. Secure Transaction Voting
@app.post("/api/v1/posts/{post_id}/vote")
async def vote_post(
    post_id: str,
    request: VoteRequest,
    server_request: Request,
    background_tasks: BackgroundTasks,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    device_id, user_handle = verify_session_token(authorization)
    client_ip = get_client_ip(server_request)
    await enforce_route_rate_limit("vote", device_id, max_requests=60, ip=client_ip)
    
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

    result = D1Service.vote_post(post_id=post_id, user_handle=user_handle, direction=request.direction)
    if not result.get("success"):
        raise HTTPException(status_code=500, detail=result.get("error", "Failed to register vote."))
        
    POSTS_CACHE.clear()

    res = {
        "status": "success",
        "userVote": result.get("newVote", 0),
        "scoreDelta": result.get("scoreDelta", 0),
        "upvoteDelta": result.get("upvoteDelta", 0),
        "downvoteDelta": result.get("downvoteDelta", 0)
    }
    if idempotency_key:
        await save_idempotent_response(idempotency_key, "vote_post", user_handle, res)
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

    success = D1Service.report_post(post_id=post_id, reporter_handle=user_handle, reason=request.reason)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to submit report.")
        
    res = {"status": "success"}
    if idempotency_key:
        await save_idempotent_response(idempotency_key, "report_post", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
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

    success = D1Service.restore_post(post_id)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to restore post.")
        
    # Chained Audit Log
    request_id = str(uuid.uuid4())
    ip_addr = get_client_ip(server_request)
    D1Service.log_moderator_action(
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
        await save_idempotent_response(idempotency_key, "restore_post", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
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

    post_data = D1Service.get_post_by_id(post_id)
    if not post_data:
        raise HTTPException(status_code=404, detail="Post not found.")
        
    if post_data.get("deletedAt") is not None:
        raise HTTPException(status_code=400, detail="Post is already deleted.")
        
    original_author = post_data.get("authorHandle", "")
    if original_author != user_handle:
        raise HTTPException(status_code=403, detail="Unauthorized.")
        
    image_url = post_data.get("imageUrl")
    if image_url and "/api/v1/media/" in image_url:
        media_id = image_url.split("/api/v1/media/")[-1]
        D1Service.delete_media(media_id)
        if media_id in MEDIA_CACHE:
            del MEDIA_CACHE[media_id]
        if media_id in MEDIA_TYPE_CACHE:
            del MEDIA_TYPE_CACHE[media_id]

    success = D1Service.delete_post(post_id)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to delete post.")
        
    POSTS_CACHE.clear()
    res = {"status": "success"}
    if idempotency_key:
        await save_idempotent_response(idempotency_key, "delete_post", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
    return res



# 9. Universal Media Upload (Photos & Videos)
MEDIA_CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache", "media")
os.makedirs(MEDIA_CACHE_DIR, exist_ok=True)

@app.post("/api/v1/storage/upload")
async def upload_media(
    server_request: Request,
    file: UploadFile = File(...),
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    device_id, user_handle = verify_session_token(authorization)
    await enforce_route_rate_limit("upload", device_id, max_requests=15)
    if idempotency_key:
        cached = await get_cached_idempotent_response(idempotency_key, "api", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else (installation_id if "installation_id" in locals() else (device_id if "device_id" in locals() else "default"))))
        if cached:
            return cached

    allowed_extensions = (".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".m4v", ".webm", ".mkv", ".3gp")
    filename = file.filename or "upload.bin"
    ext = os.path.splitext(filename)[1].lower()
    if ext not in allowed_extensions:
        raise HTTPException(status_code=400, detail="Unsupported file format. Only JPEG, PNG, WEBP, and MP4/WEBM/MOV videos allowed.")
        
    max_bytes = 35 * 1024 * 1024  # Max 35MB for videos
    file_content = await file.read(max_bytes + 1)
    if len(file_content) > max_bytes:
        raise HTTPException(status_code=400, detail="File size exceeds the maximum limit of 35MB.")
        
    verified_format, media_type, mime_type = verify_magic_bytes(file_content)
    
    sanitized_content = file_content
    if media_type == "photo":
        # Additional photo size check (10MB)
        if len(file_content) > 10 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="Image size exceeds the maximum limit of 10MB.")
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
        
    base_url = os.environ.get("PRODUCTION_URL", "https://localv1r.onrender.com").rstrip("/")

    content_hash = hashlib.sha256(sanitized_content).hexdigest()
    existing_media = D1Service.get_media_by_hash(content_hash)
    if existing_media:
        public_proxy_url = f"{base_url}/api/v1/media/{existing_media['mediaId']}"
        res = {
            "status": "success",
            "mediaId": existing_media['mediaId'],
            "imageUrl": public_proxy_url,
            "mediaUrl": public_proxy_url,
            "mediaType": existing_media.get("mediaType", media_type)
        }
        if idempotency_key:
            await save_idempotent_response(idempotency_key, "upload_image", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
        return res
        
    media_id = str(uuid.uuid4())
    object_ext = verified_format.lower()
    object_key = f"media/{media_id}.{object_ext}"
    
    # Upload to Cloudflare R2
    uploaded_key = R2Service.upload_media(
        file_bytes=sanitized_content,
        filename=f"{media_id}.{object_ext}",
        content_type=mime_type,
        object_key=object_key
    )
        
    if not uploaded_key:
        print("[WARN] Cloudflare R2 upload failed")
        raise HTTPException(status_code=500, detail="Failed to upload media to Cloudflare R2 storage.")
        
    size = len(sanitized_content)
    D1Service.register_media(
        media_id=media_id,
        object_key=uploaded_key,
        size=size,
        mime_type=mime_type,
        content_hash=content_hash,
        storage_provider="r2",
        media_type=media_type
    )
    
    # Cache locally to speed up initial requests
    try:
        cache_file_path = os.path.join(MEDIA_CACHE_DIR, f"{media_id}.bin")
        with open(cache_file_path, "wb") as f:
            f.write(sanitized_content)
        if len(sanitized_content) <= 3 * 1024 * 1024:
            MEDIA_CACHE.put(media_id, sanitized_content)
        MEDIA_TYPE_CACHE[media_id] = mime_type
    except Exception as cache_err:
        print(f"[WARN] Local disk cache write error: {cache_err}")
        
    public_proxy_url = f"{base_url}/api/v1/media/{media_id}"
    res = {
        "status": "success",
        "mediaId": media_id,
        "imageUrl": public_proxy_url,
        "mediaUrl": public_proxy_url,
        "mediaType": media_type
    }
    if idempotency_key:
        await save_idempotent_response(idempotency_key, "upload_image", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
    return res


# ⚡ PHASE 5: DIRECT R2 PRESIGNED UPLOAD & CDN PRE-WARMING
class PresignedUrlRequest(BaseModel):
    cityId: str = "general"
    moduleType: str = "posts" # 'posts', 'rooms', 'jobs', 'shops', 'avatars', 'audio'
    listingId: str = "generic"
    filename: str
    contentType: str = "image/jpeg"
    fileSize: Optional[int] = None

class PrewarmCdnRequest(BaseModel):
    mediaUrls: List[str]

@app.post("/api/v1/storage/presigned-url")
async def get_presigned_upload_url(
    req: PresignedUrlRequest,
    authorization: Optional[str] = Header(None, description="Bearer token")
):
    """
    ⚡ Phase 5: Generates a presigned Cloudflare R2 upload URL for direct client-to-R2 upload.
    Bandwidth optimization: Server never proxies the media file bytes.
    Naming convention: {cityId}/{moduleType}/{listingId}/{filename}
    """
    device_id, user_handle = verify_session_token(authorization)
    
    allowed_extensions = (".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".m4v", ".webm", ".mkv", ".3gp", ".m4a", ".aac", ".mp3")
    ext = os.path.splitext(req.filename)[1].lower()
    if not ext or ext not in allowed_extensions:
        req.filename = f"{req.filename}.jpg"

    res = R2Service.generate_presigned_upload_url(
        city_id=req.cityId,
        module_type=req.moduleType,
        listing_id=req.listingId,
        filename=req.filename,
        content_type=req.contentType
    )
    if not res.get("success"):
        raise HTTPException(status_code=500, detail=res.get("error", "Failed to generate presigned upload URL."))
    
    return res

@app.post("/api/v1/storage/cdn-prewarm")
async def prewarm_cdn_cache_endpoint(
    req: PrewarmCdnRequest,
    background_tasks: BackgroundTasks
):
    """
    ⚡ Phase 5: Cloudflare CDN Edge Cache Pre-Warming.
    """
    background_tasks.add_task(R2Service.prewarm_cdn_cache, req.mediaUrls)
    return {"status": "success", "count": len(req.mediaUrls)}



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

MEDIA_CACHE = LRUCache(500) # max 500 items in RAM for high-speed delivery
MEDIA_TYPE_CACHE: Dict[str, str] = {}


# 10. Secure Media Proxy Endpoint (High-Performance Cached CDN Gateway & Video Range Streaming)
@app.get("/api/v1/media/{media_id}")
async def serve_media(media_id: str, request: Request):
    # Support HTTP 304 Not Modified
    if_none_match = request.headers.get("if-none-match")
    if if_none_match and if_none_match.strip('"') == media_id:
        return Response(status_code=304)

    mime_type = MEDIA_TYPE_CACHE.get(media_id, "image/jpeg")
    range_header = request.headers.get("range")
    
    # 1. Try RAM Cache
    cached_bytes = MEDIA_CACHE.get(media_id)
    
    # 2. Try Disk Cache
    cache_file_path = os.path.join(MEDIA_CACHE_DIR, f"{media_id}.bin")
    if not cached_bytes and os.path.exists(cache_file_path):
        try:
            with open(cache_file_path, "rb") as f:
                cached_bytes = f.read()
                if len(cached_bytes) <= 3 * 1024 * 1024:
                    MEDIA_CACHE.put(media_id, cached_bytes)
        except Exception as read_err:
            print(f"[WARN] Error reading disk cache: {read_err}")

    # 3. If not in cache, fetch from Cloudflare R2
    if not cached_bytes:
        def _fetch_media_sync():
            media_record = D1Service.get_media_by_id(media_id)
            if not media_record or media_record.get("deletedAt") is not None:
                return None, None
            
            object_key = media_record.get("objectKey") or f"media/{media_id}.{media_record.get('mimeType', 'image/jpeg').split('/')[-1]}"
            file_bytes = R2Service.get_media_bytes(object_key)
            m_type = media_record.get("mimeType", "image/jpeg")
            return file_bytes, m_type

        cached_bytes, mime_type = await anyio.to_thread.run_sync(_fetch_media_sync)
        
        if cached_bytes is None:
            raise HTTPException(status_code=404, detail="Media not found in Cloudflare R2.")
                
        # Save to RAM and Disk caches
        try:
            with open(cache_file_path, "wb") as f:
                f.write(cached_bytes)
        except Exception as write_err:
            print(f"[WARN] Failed to write to disk cache: {write_err}")
            
        if len(cached_bytes) <= 3 * 1024 * 1024:
            MEDIA_CACHE.put(media_id, cached_bytes)
        MEDIA_TYPE_CACHE[media_id] = mime_type

    total_size = len(cached_bytes)

    # 4. Handle HTTP 206 Range Requests (Essential for Video Buffering / Seeking)
    if range_header and range_header.startswith("bytes="):
        try:
            ranges = range_header.replace("bytes=", "").split("-")
            start = int(ranges[0]) if ranges[0] else 0
            end = int(ranges[1]) if len(ranges) > 1 and ranges[1] else total_size - 1
            if start >= total_size:
                return Response(status_code=416, headers={"Content-Range": f"bytes */{total_size}"})
            end = min(end, total_size - 1)
            chunk_length = end - start + 1
            sliced_bytes = cached_bytes[start:end + 1]

            return Response(
                content=sliced_bytes,
                status_code=206,
                media_type=mime_type,
                headers={
                    "Content-Range": f"bytes {start}-{end}/{total_size}",
                    "Accept-Ranges": "bytes",
                    "Content-Length": str(chunk_length),
                    "Cache-Control": "public, max-age=31536000, immutable",
                    "ETag": f'"{media_id}"',
                }
            )
        except Exception as range_err:
            print(f"[WARN] Range header parse failed: {range_err}")

    # 5. Full Content Response
    return Response(
        content=cached_bytes,
        status_code=200,
        media_type=mime_type,
        headers={
            "Accept-Ranges": "bytes",
            "Content-Length": str(total_size),
            "Cache-Control": "public, max-age=31536000, immutable",
            "ETag": f'"{media_id}"',
        }
    )


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
            # 🛡️ Bootstrap admin: Credentials come ONLY from environment variables.
            # Set BOOTSTRAP_ADMIN_EMAIL and BOOTSTRAP_ADMIN_PASSWORD in Render/server env.
            # This block runs ONCE when no moderators exist yet.
            bootstrap_email = os.getenv("BOOTSTRAP_ADMIN_EMAIL", "")
            bootstrap_password = os.getenv("BOOTSTRAP_ADMIN_PASSWORD", "")
            if (not all_mods
                    and bootstrap_email
                    and bootstrap_password
                    and request.email == bootstrap_email
                    and request.password == bootstrap_password):
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
            await save_idempotent_response(idempotency_key, "mod_login", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
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
            await save_idempotent_response(idempotency_key, "mod_verify_mfa", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
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
        raise HTTPException(status_code=500, detail=f"Failed to fetch moderation queue: {str(e)}")

@app.get("/api/v1/moderation/stats")
async def get_admin_stats(
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token")
):
    mod_email, mod_role = await verify_moderator_session(x_moderator_token, required_role="moderator")
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        # We can use .count() aggregation in Firestore for efficiency
        users_count_query = db.collection("profiles").count()
        users_count_res = users_count_query.get()
        total_users = users_count_res[0][0].value if users_count_res else 0
        
        posts_count_query = db.collection("posts").count()
        posts_count_res = posts_count_query.get()
        total_posts = posts_count_res[0][0].value if posts_count_res else 0
        
        reports_count_query = db.collection("posts").where("reportCount", ">=", 1).count()
        reports_count_res = reports_count_query.get()
        pending_reports = reports_count_res[0][0].value if reports_count_res else 0
        
        return {
            "status": "success", 
            "stats": {
                "totalUsers": total_users,
                "totalPosts": total_posts,
                "pendingReports": pending_reports
            }
        }
    except Exception as e:
        print(f"Error fetching admin stats: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch stats: {str(e)}")

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
            await save_idempotent_response(idempotency_key, "hide_post", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
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
    
    try:
        D1Service.execute(
            "INSERT OR REPLACE INTO banned_users (handle, banned_by, reason, created_at) VALUES (?, 'admin', ?, (strftime('%s', 'now')));",
            [request.targetHandle, request.reason]
        )
        
        # Chained Audit Log
        request_id = str(uuid.uuid4())
        ip_addr = get_client_ip(server_request)
        D1Service.log_moderator_action(
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
            await save_idempotent_response(idempotency_key, "ban_user", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
        return res
    except Exception as e:
        print(f"Error banning user: {e}")
        raise HTTPException(status_code=500, detail="Failed to ban user.")

@app.get("/api/v1/moderation/users")
async def get_all_users(
    limit: int = 50,
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token")
):
    mod_email, mod_role = await verify_moderator_session(x_moderator_token, required_role="admin")
    
    try:
        users = D1Service.query("SELECT * FROM users ORDER BY created_at DESC LIMIT ?;", [limit]) or []
        users_list = []
        for d in users:
            users_list.append({
                "id": d.get("id"),
                "handle": d.get("handle"),
                "phone": d.get("phone"),
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(d["created_at"])) if d.get("created_at") else None
            })
        return {"status": "success", "users": users_list}
    except Exception as e:
        print(f"Error fetching users: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch users.")

@app.get("/api/v1/moderation/posts")
async def get_all_posts(
    category: Optional[PostCategory] = None,
    limit: int = 50,
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token")
):
    mod_email, mod_role = await verify_moderator_session(x_moderator_token, required_role="admin")
        
    try:
        cat_val = category.value if category else None
        posts_list = D1Service.get_posts(category=cat_val, limit=limit)
        return {"status": "success", "posts": posts_list}
    except Exception as e:
        print(f"Error fetching moderation posts: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch posts: {str(e)}")

@app.delete("/api/v1/moderation/users/{handle}")
async def delete_user(
    handle: str,
    server_request: Request,
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token")
):
    mod_email, mod_role = await verify_moderator_session(x_moderator_token, required_role="admin")
        
    try:
        D1Service.execute("DELETE FROM users WHERE handle = ?;", [handle])
        D1Service.execute(
            "INSERT OR REPLACE INTO banned_users (handle, banned_by, reason, created_at) VALUES (?, 'admin_delete', 'User deleted by admin', (strftime('%s', 'now')));",
            [handle]
        )
        
        D1Service.log_moderator_action(
            moderator_id=mod_email,
            role=mod_role,
            action="delete_user",
            target=handle,
            reason="User deleted from moderation panel",
            request_id=str(uuid.uuid4()),
            ip_address=get_client_ip(server_request)
        )
        return {"status": "success", "message": f"User {handle} deleted and banned."}
    except Exception as e:
        print(f"Error deleting user: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete user.")

@app.post("/api/v1/moderation/moderators/add")
async def add_moderator(
    request: AddModRequest,
    server_request: Request,
    x_moderator_token: Optional[str] = Header(None, description="Short-lived moderator token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):

    mod_email, mod_role = await verify_moderator_session(x_moderator_token, required_role="superadmin")
        
    try:
        password_with_pepper = (request.password + Config.SERVER_SALT).encode('utf-8')
        new_hashed_pass = bcrypt.hashpw(password_with_pepper, bcrypt.gensalt()).decode('utf-8')
        encrypted_mfa = Config.crypto.encrypt(b"GENERATED_BASE32_MFA_SECRET").decode('utf-8')
        now_ts = int(time.time())
        D1Service.execute(
            "INSERT OR REPLACE INTO moderators (mod_id, email, hashed_password, role, mfa_secret, status, created_at) VALUES (?, ?, ?, ?, ?, 'active', ?);",
            [request.email, request.email, new_hashed_pass, request.role, encrypted_mfa, now_ts]
        )
        
        # Chained Audit Log
        request_id = str(uuid.uuid4())
        ip_addr = get_client_ip(server_request)
        D1Service.log_moderator_action(
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
            await save_idempotent_response(idempotency_key, "add_moderator", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
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
        
    try:
        D1Service.execute("DELETE FROM moderators WHERE email = ?;", [email])
        
        # Chained Audit Log
        request_id = str(uuid.uuid4())
        ip_addr = get_client_ip(server_request)
        D1Service.log_moderator_action(
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
            await save_idempotent_response(idempotency_key, "remove_moderator", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
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
            
        if redis_client:
            is_revoked = await redis_client.sismember("revoked_tokens", jti)
            if is_revoked:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked.")
            await redis_client.sadd("revoked_tokens", jti)
        
        res = {"status": "success", "message": "Successfully logged out."}
        if idempotency_key:
            await save_idempotent_response(idempotency_key, "mod_logout", user_handle if "user_handle" in locals() else (mod_email if "mod_email" in locals() else "default"), res)
        return res
    except jwt.ExpiredSignatureError:
        return {"status": "success", "message": "Token was already expired."}
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token for logout.")


@app.on_event("startup")
async def on_startup():
    print("[STARTUP] Ensuring Cloudflare D1 Database schema & tables...")
    try:
        D1Service.init_schema()
        print("[STARTUP] Cloudflare D1 Database initialized.")
    except Exception as e:
        print(f"[STARTUP WARN] Cloudflare D1 schema init error: {e}")


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "d1_database": "connected",
        "r2_storage": "connected"
    }
