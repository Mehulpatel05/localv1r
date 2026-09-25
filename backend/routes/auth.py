import os
import re
import time
import uuid
import hashlib
import asyncio
import jwt
from typing import Optional, Dict, Any, Tuple
from collections import defaultdict
from fastapi import APIRouter, HTTPException, Header, Request, status
from pydantic import BaseModel, Field

from config import Config
from services.wakit_service import WakitService
from services.d1_service import D1Service

auth_router = APIRouter(prefix="/auth", tags=["Authentication"])

# E.164 phone regex format (+ followed by 7 to 15 digits)
E164_REGEX = re.compile(r"^\+[1-9]\d{6,14}$")

# 🛡️ OTP Request In-Memory Cache
_otp_requests: Dict[str, Dict[str, Any]] = {}
_verify_locks: Dict[str, asyncio.Lock] = {}
_global_verify_lock = asyncio.Lock()

async def _get_verify_lock(request_id: str) -> asyncio.Lock:
    async with _global_verify_lock:
        if request_id not in _verify_locks:
            _verify_locks[request_id] = asyncio.Lock()
        return _verify_locks[request_id]

def _check_is_new_user(handle: Optional[str]) -> bool:
    if handle is None:
        return True
    h = str(handle).strip().lower()
    if not h or h == "guest" or h.startswith("anon#"):
        return True
    return False

# 🛡️ Rate Limiting Data Structures (Phone & IP)
_phone_send_rl = defaultdict(list)
_ip_send_rl = defaultdict(list)

def _get_client_ip(request: Request) -> str:
    cf_ip = request.headers.get("CF-Connecting-IP")
    if cf_ip:
        return cf_ip
    xff = request.headers.get("X-Forwarded-For")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "127.0.0.1"

def _check_send_rate_limits(phone_number: str, client_ip: str):
    now = time.time()
    phone_window = 120.0  # 2 minutes sliding window
    ip_window = 300.0     # 5 minutes sliding window

    # Phone rate limit: max 5 requests per 2 minutes
    _phone_send_rl[phone_number] = [t for t in _phone_send_rl[phone_number] if now - t < phone_window]
    if len(_phone_send_rl[phone_number]) >= 5:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many OTP requests for this phone number. Please wait a moment before trying again."
        )

    # IP rate limit: max 20 requests per 5 minutes
    _ip_send_rl[client_ip] = [t for t in _ip_send_rl[client_ip] if now - t < ip_window]
    if len(_ip_send_rl[client_ip]) >= 20:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many OTP requests from your network. Please wait a moment before trying again."
        )

    _phone_send_rl[phone_number].append(now)
    _ip_send_rl[client_ip].append(now)


# Request & Response Models
class OtpSendRequest(BaseModel):
    phone_number: str = Field(..., description="E.164 formatted phone number, e.g. +919876543210")

class OtpVerifyRequest(BaseModel):
    request_id: str = Field(..., min_length=5, description="Unique OTP request ID returned by send endpoint")
    otp: str = Field(..., min_length=4, max_length=10, description="User submitted OTP code")
    phone_number: Optional[str] = Field(None, description="Optional phone number for session fallback")

class TokenRefreshRequest(BaseModel):
    refresh_token: Optional[str] = Field(None, description="Active refresh token")


def _mint_tokens(
    user_id: str,
    phone_number: str,
    handle: str,
    role: str = "user",
    city_id: str = "surat_gujarat",
    verified: bool = True,
    plan_tier: str = "free",
    banned: bool = False,
    token_version: int = 1,
    device_id: Optional[str] = None
) -> Dict[str, Any]:
    now = int(time.time())
    access_exp = now + (Config.JWT_ACCESS_EXPIRE_MINUTES * 60)
    refresh_exp = now + (Config.JWT_REFRESH_EXPIRE_DAYS * 86400)

    # 🚀 Phase 1 JWT Identity & Decision Layer:
    # Full business logic claims allow 0ms instantaneous client & server decisions with ZERO database lookups.
    access_payload = {
        "uid": user_id,
        "sub": user_id,
        "phone": phone_number,
        "handle": handle,
        "role": role,
        "cityId": city_id,
        "city_id": city_id,
        "verified": verified,
        "planTier": plan_tier,
        "plan_tier": plan_tier,
        "banned": banned,
        "tokenVersion": token_version,
        "token_version": token_version,
        "device_id": device_id or "trusted_device",
        "type": "access",
        "iss": "nearhood-backend",
        "iat": now,
        "exp": access_exp,
    }
    raw_access = jwt.encode(access_payload, Config.JWT_SECRET, algorithm="HS256")
    access_token = raw_access.decode("utf-8") if isinstance(raw_access, bytes) else str(raw_access)

    refresh_jti = uuid.uuid4().hex
    refresh_payload = {
        "uid": user_id,
        "sub": user_id,
        "phone": phone_number,
        "handle": handle,
        "role": role,
        "cityId": city_id,
        "city_id": city_id,
        "verified": verified,
        "planTier": plan_tier,
        "banned": banned,
        "tokenVersion": token_version,
        "type": "refresh",
        "jti": refresh_jti,
        "iss": "nearhood-backend",
        "iat": now,
        "exp": refresh_exp,
    }
    raw_refresh = jwt.encode(refresh_payload, Config.JWT_SECRET, algorithm="HS256")
    refresh_token = raw_refresh.decode("utf-8") if isinstance(raw_refresh, bytes) else str(raw_refresh)

    # Persist refresh token in Cloudflare D1
    try:
        D1Service.save_refresh_token(refresh_jti, user_id, phone_number, refresh_exp)
    except Exception as e:
        print(f"[AUTH] Failed saving refresh token to D1: {e}")

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": Config.JWT_ACCESS_EXPIRE_MINUTES * 60,
        "claims": {
            "uid": user_id,
            "role": role,
            "cityId": city_id,
            "verified": verified,
            "handle": handle,
            "planTier": plan_tier,
            "banned": banned,
            "tokenVersion": token_version,
        }
    }


@auth_router.post("/otp/send")
async def send_otp(req: OtpSendRequest, request: Request):
    """
    Validates E.164 phone format, enforces phone & IP rate limits, and triggers Wakit OTP send.
    """
    phone = req.phone_number.strip()
    if not E164_REGEX.match(phone):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid phone number format. Must be in international E.164 format (e.g., +919876543210)."
        )

    client_ip = _get_client_ip(request)
    _check_send_rate_limits(phone, client_ip)

    # Call Wakit Service
    try:
        result = WakitService.send_otp(phone)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to send OTP via SMS/WhatsApp provider: {str(e)}"
        )

    request_id = result.get("request_id")
    expires_in = result.get("expires_in", 300)

    # Store in cache
    now = time.time()
    _otp_requests[request_id] = {
        "phone": phone,
        "attempts": 0,
        "locked_until": 0,
        "expires_at": now + expires_in,
        "verified": False,
        "created_at": now,
    }

    return {
        "status": "success",
        "message": "OTP sent successfully.",
        "request_id": request_id,
        "expires_in": expires_in,
    }


@auth_router.post("/otp/verify")
async def verify_otp(req: OtpVerifyRequest, request: Request):
    """
    Verifies user-submitted OTP with rate-limiting, lockout on 5 failed attempts, single-use enforcement,
    and atomic concurrency locks to prevent race conditions during duplicate or delayed retries.
    """
    request_id = req.request_id.strip()
    otp_code = req.otp.strip()

    lock = await _get_verify_lock(request_id)
    async with lock:
        try:
            context = _otp_requests.get(request_id)
            now = time.time()

            if not context:
                if req.phone_number and E164_REGEX.match(req.phone_number.strip()):
                    context = {
                        "phone": req.phone_number.strip(),
                        "attempts": 0,
                        "locked_until": 0,
                        "expires_at": now + 600,
                        "verified": False,
                        "created_at": now,
                    }
                    _otp_requests[request_id] = context
                else:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Invalid or expired OTP session. Please request a new OTP."
                    )

            # Check if already verified (idempotency support for retries & concurrent taps)
            if context.get("verified") and context.get("cached_response"):
                return context["cached_response"]

            # Check expiration
            if now > context["expires_at"]:
                _otp_requests.pop(request_id, None)
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="OTP has expired. Please request a new code."
                )

            # Check lockout
            if now < context["locked_until"]:
                remaining_lock = int(context["locked_until"] - now)
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=f"Too many failed attempts. Verification locked for {remaining_lock} seconds."
                )

            # Increment attempts
            context["attempts"] += 1

            if context["attempts"] > 5:
                context["locked_until"] = now + 900 # 15 minutes lockout
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Maximum verification attempts exceeded. Verification temporarily locked for 15 minutes."
                )

            # Verify code directly via Wakit Gateway
            phone_number = context["phone"]
            try:
                is_valid = WakitService.verify_otp(request_id, otp_code, phone_number=phone_number)
            except Exception as e:
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Provider verification service error: {str(e)}"
                )

            if not is_valid:
                remaining_attempts = max(0, 5 - context["attempts"])
                if remaining_attempts == 0:
                    context["locked_until"] = now + 900
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail="Incorrect OTP code. Maximum attempts reached. Locked for 15 minutes."
                    )
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Incorrect OTP code. {remaining_attempts} attempt(s) remaining."
                )

            # User Resolution / Provisioning in Cloudflare D1
            phone_hash = hashlib.sha256(phone_number.encode()).hexdigest()
            anon_handle = f"Anon#{phone_hash[:6].upper()}"
            
            user_record = D1Service.get_or_create_user(phone=phone_number, handle=anon_handle)
            user_id = user_record.get("id", phone_hash)
            handle = user_record.get("handle") or anon_handle
            photo_url = user_record.get("avatar_url", "")
            is_new_user = _check_is_new_user(handle)

            tokens = _mint_tokens(
                user_id=user_id,
                phone_number=phone_number,
                handle=handle,
                role=user_record.get("role", "user"),
                city_id=user_record.get("city_id", "surat_gujarat"),
                verified=bool(user_record.get("verified", 1)),
                plan_tier=user_record.get("plan_tier", "free"),
                banned=bool(user_record.get("banned", 0)),
                token_version=int(user_record.get("token_version", 1))
            )

            res_payload = {
                "status": "success",
                "message": "Phone number verified successfully.",
                **tokens,
                "user": {
                    "userId": user_id,
                    "phoneNumber": phone_number,
                    "handle": handle,
                    "photoUrl": photo_url,
                    "role": user_record.get("role", "user"),
                    "cityId": user_record.get("city_id", "surat_gujarat"),
                    "verified": bool(user_record.get("verified", 1)),
                    "planTier": user_record.get("plan_tier", "free"),
                    "banned": bool(user_record.get("banned", 0)),
                    "tokenVersion": int(user_record.get("token_version", 1)),
                    "isNewUser": is_new_user,
                }
            }

            # Mark as verified and cache response with extended TTL (15 minutes) for idempotent duplicate submissions
            context["verified"] = True
            context["expires_at"] = now + 900
            context["cached_response"] = res_payload

            return res_payload
        except HTTPException:
            raise
        except Exception as e:
            import traceback
            traceback.print_exc()
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Verification error: {str(e)}"
            )


@auth_router.post("/refresh")
async def refresh_token(
    req: Optional[TokenRefreshRequest] = None,
    x_refresh_token: Optional[str] = Header(None, alias="X-Refresh-Token")
):
    """
    Refreshes access token given a valid refresh token verified in Cloudflare D1.
    """
    token_str = (req.refresh_token if req and req.refresh_token else None) or x_refresh_token
    if not token_str:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing refresh token."
        )

    try:
        payload = jwt.decode(token_str, Config.JWT_SECRET, algorithms=["HS256"], issuer="nearhood-backend")
        if payload.get("type") != "refresh":
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token type.")

        user_id = payload.get("uid") or payload.get("sub")
        phone = payload.get("phone", "")
        handle = payload.get("handle", "")
        jti = payload.get("jti")

        # Check D1 status if jti exists
        # Check D1 status if jti exists
        if jti:
            t_doc = D1Service.get_refresh_token(jti)
            if not t_doc or t_doc.get("status") != "active":
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token is revoked or expired.")

        # Pull updated user record to validate session freshness against Cloudflare D1
        user_record = D1Service.get_user_by_id(user_id) if user_id else None
        if not user_record:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User account not found.")

        # If user was banned since token issuance, revoke refresh token and reject
        if bool(user_record.get("banned", 0)):
            if jti:
                D1Service.revoke_refresh_token(jti)
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account has been suspended by administration.")

        # Check token version revocation
        current_db_version = int(user_record.get("token_version", 1))
        claim_version = int(payload.get("tokenVersion") or payload.get("token_version") or 1)
        if claim_version < current_db_version:
            if jti:
                D1Service.revoke_refresh_token(jti)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Session has been revoked due to security/role updates. Please log in again."
            )

        u_role = user_record.get("role", "user")
        u_city = user_record.get("city_id", "surat_gujarat")
        u_ver = bool(user_record.get("verified", 1))
        u_tier = user_record.get("plan_tier", "free")
        u_banned = False
        u_tver = current_db_version

        tokens = _mint_tokens(
            user_id=user_id,
            phone_number=phone or user_record.get("phone", ""),
            handle=handle or user_record.get("handle", ""),
            role=u_role,
            city_id=u_city,
            verified=u_ver,
            plan_tier=u_tier,
            banned=u_banned,
            token_version=u_tver,
            device_id=payload.get("device_id")
        )
        return {
            "status": "success",
            **tokens,
        }
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired. Please login again.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")


def verify_jwt_claims_fast(token: str) -> Dict[str, Any]:
    """
    ⚡ 0ms Zero-DB Hit Fast Decision Helper.
    Validates token signature, expiration, type, and banned status without touching D1.
    """
    raw_token = token.replace("Bearer ", "").strip()
    try:
        payload = jwt.decode(
            raw_token,
            Config.JWT_SECRET,
            algorithms=["HS256"],
            issuer="nearhood-backend"
        )
        if payload.get("type") != "access":
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token type.")
        if payload.get("banned") is True:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account is suspended.")
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session expired.")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session token.")




@auth_router.delete("/account")
@auth_router.post("/delete-account")
async def delete_account(
    authorization: Optional[str] = Header(None, alias="Authorization"),
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
):
    """
    Permanently deletes user account, posts, and auth sessions from Cloudflare D1.
    """
    token = authorization or (f"Bearer {x_session_token}" if x_session_token else None)
    if not token or not token.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing or invalid authorization header.")

    raw_token = token.split("Bearer ")[1].strip()
    user_id = None
    handle = None

    try:
        payload = jwt.decode(
            raw_token,
            Config.JWT_SECRET,
            algorithms=["HS256"],
            issuer="nearhood-backend"
        )
        if payload.get("type") in ("access", "refresh"):
            user_id = payload.get("sub")
            handle = payload.get("handle")
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired session token.")

    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired session token.")

    try:
        if handle:
            D1Service.execute("UPDATE posts SET deleted_at = (strftime('%s', 'now')) WHERE author_handle = ?;", [handle])
            D1Service.execute("DELETE FROM users WHERE handle = ?;", [handle])
        D1Service.execute("DELETE FROM refresh_tokens WHERE user_id = ?;", [user_id])
    except Exception as e:
        print(f"[AUTH] Error deleting user in D1: {e}")

    return {
        "status": "success",
        "message": "User account and associated content successfully deleted."
    }


class UpdateHandleRequest(BaseModel):
    handle: str = Field(..., min_length=3, max_length=30)

class UpdateAvatarRequest(BaseModel):
    avatar_url: str = Field(...)


def _extract_user(authorization: Optional[str], x_session_token: Optional[str]) -> Tuple[str, str]:
    token = authorization or (f"Bearer {x_session_token}" if x_session_token else None)
    if not token or not token.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing authorization header.")
    raw_token = token.split("Bearer ")[1].strip()
    try:
        payload = jwt.decode(raw_token, Config.JWT_SECRET, algorithms=["HS256"], issuer="nearhood-backend")
        return payload.get("sub", ""), payload.get("handle", "")
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session token.")


@auth_router.get("/profile")
async def get_my_profile(
    authorization: Optional[str] = Header(None, alias="Authorization"),
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
):
    user_id, _ = _extract_user(authorization, x_session_token)
    user = D1Service.get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    
    handle = user.get("handle", "")
    total_upvotes = D1Service.get_user_upvotes(handle)
    friend_count = D1Service.get_friend_count(handle)
    
    return {
        "status": "success",
        "user": {
            "userId": user["id"],
            "handle": handle,
            "phoneNumber": user.get("phone", ""),
            "avatarUrl": user.get("avatar_url", ""),
            "reputation": user.get("reputation", 0),
            "upvotes": total_upvotes,
            "friendCount": friend_count,
            "createdAt": user.get("created_at"),
        }
    }


@auth_router.get("/check-handle")
async def check_handle(handle: str):
    clean = handle.replace("@", "").strip().lower()
    if len(clean) < 3 or len(clean) > 30 or not re.match(r"^[a-zA-Z0-9_.]+$", clean):
        return {"available": False, "reason": "Invalid handle format."}
    is_avail = D1Service.is_handle_available(clean)
    return {"available": is_avail, "handle": clean}


@auth_router.post("/profile/handle")
async def update_handle(
    req: UpdateHandleRequest,
    authorization: Optional[str] = Header(None, alias="Authorization"),
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
):
    user_id, _ = _extract_user(authorization, x_session_token)
    clean = req.handle.replace("@", "").strip()
    if len(clean) < 3 or len(clean) > 30 or not re.match(r"^[a-zA-Z0-9_.]+$", clean):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Handle must be 3-30 alphanumeric characters.")

    if not D1Service.is_handle_available(clean, exclude_user_id=user_id):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This handle is already taken.")

    ok = D1Service.update_user_handle(user_id, clean)
    if not ok:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to update handle.")

    user = D1Service.get_user_by_id(user_id)
    phone = user.get("phone", "") if user else ""
    tokens = _mint_tokens(user_id=user_id, phone_number=phone, handle=clean)

    return {
        "status": "success",
        "handle": clean,
        **tokens
    }


@auth_router.post("/profile/avatar")
async def update_avatar(
    req: UpdateAvatarRequest,
    authorization: Optional[str] = Header(None, alias="Authorization"),
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
):
    user_id, _ = _extract_user(authorization, x_session_token)
    avatar_url = req.avatar_url.strip()
    ok = D1Service.update_user_avatar(user_id, avatar_url)
    if not ok:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to update avatar.")

    return {
        "status": "success",
        "avatarUrl": avatar_url
    }


@auth_router.get("/profile/{handle}")
async def get_public_profile(handle: str):
    clean = handle.replace("@", "").strip().lower()
    user = D1Service.get_user_by_handle(clean)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    
    total_upvotes = D1Service.get_user_upvotes(clean)
    friend_count = D1Service.get_friend_count(clean)

    return {
        "status": "success",
        "user": {
            "handle": user["handle"],
            "avatarUrl": user.get("avatar_url", ""),
            "reputation": user.get("reputation", 0),
            "upvotes": total_upvotes,
            "friendCount": friend_count,
            "createdAt": user.get("created_at"),
        }
    }

