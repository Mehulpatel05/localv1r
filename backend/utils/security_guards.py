import jwt
import time
from typing import Optional, Dict, Any, List
from fastapi import Header, HTTPException, status, Depends
from config import Config
from services.d1_service import D1Service

class SecurityDecisionEngine:
    """
    🛡️ Phase 1 Server-Side Security Gatekeeper (FastAPI + Cloudflare D1/R2)
    
    ARCHITECTURE PRINCIPLE:
    - Normal requests are 100% DB-FREE: Identity, roles, verified status, and permissions
      are validated entirely via cryptographic JWT signature and claims verification (0ms latency).
    - Client-side UI decoding is for fast UX rendering only and is NEVER trusted as a security boundary.
    - Token revocation is enforced at the short-lived access token boundary (15-30 min) and
      strictly validated against Cloudflare D1 during refresh-token requests (/auth/refresh).
    """

    @staticmethod
    def extract_token_from_headers(
        authorization: Optional[str] = Header(None, alias="Authorization"),
        x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
    ) -> str:
        token = authorization or (f"Bearer {x_session_token}" if x_session_token else None)
        if not token:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required. Please provide a valid Bearer token."
            )
        return token.replace("Bearer ", "").strip()

    @classmethod
    def get_current_claims(
        cls,
        authorization: Optional[str] = Header(None, alias="Authorization"),
        x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
    ) -> Dict[str, Any]:
        """
        ⚡ 0ms Zero-DB Fast Token Decision Engine.
        Validates cryptographic signature, issuer, expiration, token type, and required claims.
        """
        raw_token = cls.extract_token_from_headers(authorization, x_session_token)
        try:
            # 1. Cryptographic signature and issuer verification
            payload = jwt.decode(
                raw_token,
                Config.JWT_SECRET,
                algorithms=["HS256"],
                issuer="nearhood-backend"
            )
            
            # 2. Token type validation
            if payload.get("type") != "access":
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid token type. Access token expected."
                )

            # 3. Required claims validation
            user_id = payload.get("uid") or payload.get("sub")
            handle = payload.get("handle")
            if not user_id or not handle:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Malformed token: missing user identity claims."
                )

            # 4. Instant Ban Rejection (Zero-DB check from signed claims)
            if payload.get("banned") is True:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="This account has been suspended by administration."
                )

            return payload
        except jwt.ExpiredSignatureError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Session token expired. Please refresh your session."
            )
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or forged session token signature."
            )

    @classmethod
    def require_verified_active_user(
        cls,
        claims: Dict[str, Any] = Depends(get_current_claims)
    ) -> Dict[str, Any]:
        """
        Server Gatekeeper: Enforces verified mobile/KYC status and active account.
        """
        if not claims.get("verified", False):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Phone number verification required before performing this action."
            )
        return claims

    @classmethod
    def require_admin_or_moderator(
        cls,
        claims: Dict[str, Any] = Depends(get_current_claims)
    ) -> Dict[str, Any]:
        """
        Server Gatekeeper: Enforces administrative or moderator privileges.
        """
        role = claims.get("role", "user")
        if role not in ["admin", "moderator"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Administrative privileges required."
            )
        return claims

    @classmethod
    def require_shop_owner_or_admin(
        cls,
        claims: Dict[str, Any] = Depends(get_current_claims)
    ) -> Dict[str, Any]:
        """
        Server Gatekeeper: Enforces merchant / shop owner role for catalog mutations.
        """
        role = claims.get("role", "user")
        if role not in ["shop_owner", "admin", "moderator"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Shop owner privileges required to publish product catalogs."
            )
        return claims

    @classmethod
    def require_pro_plan(
        cls,
        claims: Dict[str, Any] = Depends(get_current_claims)
    ) -> Dict[str, Any]:
        """
        Server Gatekeeper: Enforces Pro subscription tier for boosted visibility.
        """
        plan = claims.get("planTier") or claims.get("plan_tier", "free")
        if plan != "pro" and claims.get("role") not in ["admin", "moderator"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Pro plan subscription required for listing boost."
            )
        return claims

    @classmethod
    def verify_ownership_or_admin(cls, resource_owner_handle: str, claims: Dict[str, Any]) -> bool:
        """
        Server Gatekeeper: Enforces resource ownership or admin bypass on content edits/deletions.
        """
        user_handle = (claims.get("handle") or "").replace("@", "").strip().lower()
        target_owner = (resource_owner_handle or "").replace("@", "").strip().lower()
        is_admin = claims.get("role") in ["admin", "moderator"]

        if user_handle == target_owner or is_admin:
            return True
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Permission denied. You can only modify your own content."
        )
