import time
import jwt
from typing import Optional, Dict, Any, List, Tuple
from fastapi import APIRouter, HTTPException, Header, Request, status, Query
from pydantic import BaseModel, Field

from config import Config
from services.d1_service import D1Service

communities_router = APIRouter(prefix="/communities", tags=["Communities & General Chat"])

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


class CreateCommunityModel(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    description: str = Field(..., max_length=500)
    isChannel: bool = False
    imageUrl: Optional[str] = None

class UpdateCommunityModel(BaseModel):
    name: Optional[str] = Field(None, min_length=2, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    imageUrl: Optional[str] = None

class SendMessageModel(BaseModel):
    content: str = Field(..., min_length=1, max_length=4000)
    imageUrl: Optional[str] = None
    mediaUrls: Optional[List[str]] = None
    type: str = "text"

class ReactMessageModel(BaseModel):
    emoji: str = Field(..., min_length=1, max_length=10)


@communities_router.get("")
@communities_router.get("/")
async def list_communities(
    filter: str = Query("all", pattern="^(all|joined|discover)$"),
    authorization: Optional[str] = Header(None)
):
    user_handle = None
    if authorization and authorization.startswith("Bearer "):
        try:
            _, user_handle = _get_auth_user(authorization)
        except:
            pass

    communities = D1Service.get_communities(user_handle=user_handle, filter_mode=filter)
    return {
        "status": "success",
        "communities": communities
    }


@communities_router.post("", status_code=status.HTTP_201_CREATED)
@communities_router.post("/", status_code=status.HTTP_201_CREATED)
async def create_community(
    body: CreateCommunityModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    comm_id = D1Service.create_community(
        name=body.name,
        description=body.description,
        admin_handle=handle,
        is_channel=body.isChannel,
        image_url=body.imageUrl
    )
    if not comm_id:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to create community.")

    return {
        "status": "success",
        "communityId": comm_id,
        "message": "Community created successfully."
    }


@communities_router.get("/{community_id}")
async def get_community(community_id: str):
    comm = D1Service.get_community_by_id(community_id)
    if not comm:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found.")
    return {
        "status": "success",
        "community": comm
    }


@communities_router.put("/{community_id}")
async def update_community(
    community_id: str,
    body: UpdateCommunityModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.update_community(
        community_id=community_id,
        admin_handle=handle,
        name=body.name,
        description=body.description,
        image_url=body.imageUrl
    )
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admin can update community.")
    return {
        "status": "success",
        "message": "Community updated successfully."
    }


@communities_router.post("/{community_id}/join")
async def join_community(
    community_id: str,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.join_community(community_id, handle)
    if not ok:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Failed to join community.")
    return {
        "status": "success",
        "message": "Joined community successfully."
    }


@communities_router.post("/{community_id}/leave")
async def leave_community(
    community_id: str,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.leave_community(community_id, handle)
    if not ok:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Failed to leave community.")
    return {
        "status": "success",
        "message": "Left community successfully."
    }


@communities_router.get("/{community_id}/members")
async def get_members(community_id: str):
    members = D1Service.get_community_members(community_id)
    return {
        "status": "success",
        "members": members
    }


@communities_router.get("/{community_id}/messages")
async def get_messages(
    community_id: str,
    limit: int = Query(50, ge=1, le=100),
    before: Optional[int] = Query(None)
):
    messages = D1Service.get_community_messages(community_id, limit=limit, before_ts=before)
    return {
        "status": "success",
        "messages": messages
    }


@communities_router.post("/{community_id}/messages", status_code=status.HTTP_201_CREATED)
async def send_message(
    community_id: str,
    body: SendMessageModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    msg_id = D1Service.send_community_message(
        community_id=community_id,
        author_handle=handle,
        content=body.content,
        image_url=body.imageUrl,
        media_urls=body.mediaUrls,
        message_type=body.type
    )
    if not msg_id:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to send message.")

    return {
        "status": "success",
        "messageId": msg_id,
        "message": "Message sent successfully."
    }


@communities_router.post("/{community_id}/messages/{message_id}/react")
async def react_to_message(
    community_id: str,
    message_id: str,
    body: ReactMessageModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    res = D1Service.react_community_message(message_id, handle, body.emoji)
    return {
        "status": "success",
        **res
    }


@communities_router.delete("/{community_id}/messages/{message_id}")
async def delete_message(
    community_id: str,
    message_id: str,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.delete_community_message(message_id, handle)
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Failed to delete message. Only author can delete.")
    return {
        "status": "success",
        "message": "Message deleted."
    }


@communities_router.post("/{community_id}/read")
async def mark_read(
    community_id: str,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    D1Service.mark_community_read(community_id, handle)
    return {
        "status": "success"
    }
