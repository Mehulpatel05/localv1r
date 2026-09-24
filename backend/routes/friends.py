import time
import jwt
from typing import Optional, Dict, Any, List, Tuple
from fastapi import APIRouter, HTTPException, Header, Request, status, Query
from pydantic import BaseModel, Field

from config import Config
from services.d1_service import D1Service

friends_router = APIRouter(prefix="/friends", tags=["Friends"])

def _get_auth_user(authorization: Optional[str]) -> Tuple[str, str]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header."
        )
    raw_token = authorization.split("Bearer ")[1].strip()
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
            return uid, handle
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session expired. Please refresh token or log in again.")
    except Exception as e:
        print(f"[AUTH] JWT error: {e}")

    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session token.")


class SendRequestModel(BaseModel):
    receiverHandle: str = Field(..., min_length=1, max_length=50)

class ActionRequestModel(BaseModel):
    senderHandle: str = Field(..., min_length=1, max_length=50)

class CancelRequestModel(BaseModel):
    receiverHandle: str = Field(..., min_length=1, max_length=50)

class UnfriendModel(BaseModel):
    otherHandle: str = Field(..., min_length=1, max_length=50)

class BlockModel(BaseModel):
    blockedHandle: str = Field(..., min_length=1, max_length=50)


@friends_router.get("")
@friends_router.get("/")
async def list_friends(
    limit: int = Query(100, ge=1, le=200),
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    friends = D1Service.get_friends(handle, limit=limit)
    return {
        "status": "success",
        "count": len(friends),
        "friends": friends
    }


@friends_router.get("/requests")
async def list_friend_requests(
    type: str = Query("all", pattern="^(received|sent|all)$"),
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    
    received = []
    sent = []
    
    if type in ["received", "all"]:
        received = D1Service.get_pending_requests(handle, direction="received")
    if type in ["sent", "all"]:
        sent = D1Service.get_pending_requests(handle, direction="sent")
        
    return {
        "status": "success",
        "received": received,
        "sent": sent,
        "pendingCount": len(received)
    }


@friends_router.get("/status/{target_handle}")
async def get_relationship(
    target_handle: str,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    status_str = D1Service.get_relationship_status(handle, target_handle)
    return {
        "status": "success",
        "relationship": status_str
    }


@friends_router.post("/request")
async def send_request(
    body: SendRequestModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok, msg = D1Service.send_friend_request(handle, body.receiverHandle)
    if not ok:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=msg)
    return {
        "status": "success",
        "message": msg
    }


@friends_router.post("/accept")
async def accept_request(
    body: ActionRequestModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.accept_friend_request(body.senderHandle, handle)
    if not ok:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Failed to accept friend request.")
    return {
        "status": "success",
        "message": "Friend request accepted."
    }


@friends_router.post("/reject")
async def reject_request(
    body: ActionRequestModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.reject_friend_request(body.senderHandle, handle)
    if not ok:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Failed to reject friend request.")
    return {
        "status": "success",
        "message": "Friend request rejected."
    }


@friends_router.post("/cancel")
async def cancel_request(
    body: CancelRequestModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.cancel_friend_request(handle, body.receiverHandle)
    return {
        "status": "success",
        "message": "Friend request cancelled."
    }


@friends_router.post("/unfriend")
@friends_router.delete("/{other_handle}")
async def unfriend_user(
    other_handle: Optional[str] = None,
    body: Optional[UnfriendModel] = None,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    target = other_handle or (body.otherHandle if body else None)
    if not target:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Target user handle is required.")
    
    D1Service.unfriend(handle, target)
    return {
        "status": "success",
        "message": "Successfully unfriended."
    }


@friends_router.post("/block")
async def block_user_endpoint(
    body: BlockModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    D1Service.block_user(handle, body.blockedHandle)
    return {
        "status": "success",
        "message": "User blocked."
    }


@friends_router.post("/unblock")
async def unblock_user_endpoint(
    body: BlockModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    D1Service.unblock_user(handle, body.blockedHandle)
    return {
        "status": "success",
        "message": "User unblocked."
    }


@friends_router.get("/blocked")
async def list_blocked_users(
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    blocked = D1Service.get_blocked_users(handle)
    return {
        "status": "success",
        "blocked": blocked
    }
