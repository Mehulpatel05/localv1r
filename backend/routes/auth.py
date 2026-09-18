import os
import re
import time
import uuid
import hashlib
import jwt
from typing import Optional, Dict, Any
from collections import defaultdict
from fastapi import APIRouter, HTTPException, Header, Request, status
from pydantic import BaseModel, Field

from config import Config
from services.wakit_service import WakitService
from services.firebase_service import db

auth_router = APIRouter(prefix="/auth", tags=["Authentication"])

# E.164 phone regex format (+ followed by 7 to 15 digits)
E164_REGEX = re.compile(r"^\+[1-9]\d{6,14}$")

# 🛡️ OTP Request In-Memory Cache (Stores request context, expiration, attempts, single-use flag)
# Schema: request_id -> { "phone": str, "attempts": int, "locked_until": float, "expires_at": float, "verified": bool }
_otp_requests: Dict[str, Dict[str, Any]] = {}

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


def _mint_tokens(user_id: str, phone_number: str, handle: str) -> Dict[str, Any]:
    now = int(time.time())
    access_exp = now + (Config.JWT_ACCESS_EXPIRE_MINUTES * 60)
    refresh_exp = now + (Config.JWT_REFRESH_EXPIRE_DAYS * 86400)

    access_payload = {
        "sub": user_id,
        "phone": phone_number,
        "handle": handle,
        "type": "access",
        "iss": "nearhood-backend",
        "iat": now,
        "exp": access_exp,
    }
    access_token = jwt.encode(access_payload, Config.JWT_SECRET, algorithm="HS256")

    refresh_jti = uuid.uuid4().hex
    refresh_payload = {
        "sub": user_id,
        "phone": phone_number,
        "handle": handle,
        "type": "refresh",
        "jti": refresh_jti,
        "iss": "nearhood-backend",
        "iat": now,
        "exp": refresh_exp,
    }
    refresh_token = jwt.encode(refresh_payload, Config.JWT_SECRET, algorithm="HS256")

    # Persist refresh token in Firestore if db is active
    if db is not None:
        try:
            db.collection("refresh_tokens").document(refresh_jti).set({
                "userId": user_id,
                "phone": phone_number,
                "jti": refresh_jti,
                "status": "active",
                "createdAt": now,
                "expiresAt": refresh_exp,
            })
        except Exception as e:
            print(f"[AUTH] Failed saving refresh token to DB: {e}")

    # Generate Firebase Custom Token for seamless Firestore/RTDB integration if needed
    firebase_token = None
    try:
        from firebase_admin import auth as firebase_auth
        firebase_token = firebase_auth.create_custom_token(user_id).decode("utf-8") if isinstance(firebase_auth.create_custom_token(user_id), bytes) else str(firebase_auth.create_custom_token(user_id))
    except Exception:
        firebase_token = None

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": Config.JWT_ACCESS_EXPIRE_MINUTES * 60,
        "firebase_custom_token": firebase_token,
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
    Verifies user-submitted OTP with rate-limiting, lockout on 5 failed attempts, and single-use enforcement.
    On success, looks up or creates user in database and issues JWT session tokens.
    """
    request_id = req.request_id.strip()
    otp_code = req.otp.strip()

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

    # Check expiration
    if now > context["expires_at"]:
        _otp_requests.pop(request_id, None)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="OTP has expired. Please request a new code."
        )

    # Check single-use
    if context["verified"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This OTP has already been verified. Please request a new code."
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

    # Verify code via Wakit
    phone_number = context["phone"]
    is_valid = WakitService.verify_otp(request_id, otp_code, phone_number=phone_number)

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

    # Mark as verified immediately to prevent replay attacks
    context["verified"] = True

    # User Resolution / Provisioning
    phone_hash = hashlib.sha256(phone_number.encode()).hexdigest()
    user_id = phone_hash
    handle = ""
    is_new_user = True

    if db is not None:
        try:
            from google.cloud import firestore
            user_ref = db.collection("users").document(phone_hash)
            user_doc = user_ref.get()

            if user_doc.exists:
                data = user_doc.to_dict() or {}
                handle = data.get("handle", "")
                is_new_user = (handle == "")
                user_ref.update({
                    "lastLoginAt": firestore.SERVER_TIMESTAMP,
                    "phoneNumber": phone_number,
                })
            else:
                # First time registration
                user_ref.set({
                    "userId": user_id,
                    "phoneNumber": phone_number,
                    "phoneNumberHash": phone_hash,
                    "handle": "",
                    "createdAt": firestore.SERVER_TIMESTAMP,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                    "lastLoginAt": firestore.SERVER_TIMESTAMP,
                })
        except Exception as e:
            print(f"[AUTH] Error during user record creation/lookup: {e}")

    tokens = _mint_tokens(user_id=user_id, phone_number=phone_number, handle=handle)

    return {
        "status": "success",
        "message": "Phone number verified successfully.",
        **tokens,
        "user": {
            "userId": user_id,
            "phoneNumber": phone_number,
            "handle": handle,
            "isNewUser": is_new_user,
        }
    }


@auth_router.post("/refresh")
async def refresh_token(
    req: Optional[TokenRefreshRequest] = None,
    x_refresh_token: Optional[str] = Header(None, alias="X-Refresh-Token")
):
    """
    Refreshes access token given a valid refresh token.
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

        user_id = payload.get("sub")
        phone = payload.get("phone", "")
        handle = payload.get("handle", "")
        jti = payload.get("jti")

        # Check DB status if active
        if db is not None and jti:
            t_doc = db.collection("refresh_tokens").document(jti).get()
            if not t_doc.exists or t_doc.to_dict().get("status") != "active":
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token is revoked or expired.")

        tokens = _mint_tokens(user_id=user_id, phone_number=phone, handle=handle)
        return {
            "status": "success",
            **tokens,
        }
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired. Please login again.")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")
