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
    name: str = Field(..., min_length=1, max_length=100)
    description: str = Field("", max_length=500)
    isChannel: bool = False
    visibility: str = Field("public", pattern="^(public|private)$")
    username: Optional[str] = None
    inviteLink: Optional[str] = None
    settings: Optional[Dict[str, Any]] = None
    imageUrl: Optional[str] = None
    initialMembers: Optional[List[str]] = None

class UpdateCommunityModel(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    imageUrl: Optional[str] = None
    visibility: Optional[str] = Field(None, pattern="^(public|private)$")
    username: Optional[str] = None
    settings: Optional[Dict[str, Any]] = None

class SendMessageModel(BaseModel):
    content: str = Field(..., min_length=1, max_length=4000)
    imageUrl: Optional[str] = None
    mediaUrls: Optional[List[str]] = None
    type: str = "text"

class EditMessageModel(BaseModel):
    content: str = Field(..., min_length=1, max_length=4000)

class ReactMessageModel(BaseModel):
    emoji: str = Field(..., min_length=1, max_length=10)

class RespondJoinRequestModel(BaseModel):
    approve: bool

class UpdateRoleModel(BaseModel):
    role: str = Field(..., pattern="^(admin|member)$")
    permissions: Optional[Dict[str, Any]] = None

class TransferOwnershipModel(BaseModel):
    newOwnerHandle: str

class MuteModel(BaseModel):
    mutedUntil: int = 0  # 0 to unmute, -1 for forever, or unix timestamp

class ArchiveModel(BaseModel):
    isArchived: bool = True

class PinMessageModel(BaseModel):
    pin: bool = True


@communities_router.get("/check-username")
async def check_username(username: str = Query(..., min_length=3, max_length=30)):
    available = D1Service.check_community_username_available(username)
    return {
        "status": "success",
        "username": username,
        "available": available
    }


@communities_router.get("/by-identifier/{identifier}")
async def get_by_identifier(identifier: str):
    comm = D1Service.get_community_by_username_or_link(identifier)
    if not comm:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found.")
    return {
        "status": "success",
        "community": comm
    }


@communities_router.get("")
@communities_router.get("/")
async def list_communities(
    filter: str = Query("all", pattern="^(all|joined|discover|directory)$"),
    q: Optional[str] = Query(None),
    type: Optional[str] = Query(None, pattern="^(group|channel)$"),
    authorization: Optional[str] = Header(None)
):
    user_handle = None
    if filter == "joined":
        # Authentication is required for joined list. Raises 401 if token is expired/invalid.
        _, user_handle = _get_auth_user(authorization)
    elif authorization and authorization.startswith("Bearer "):
        try:
            _, user_handle = _get_auth_user(authorization)
        except:
            pass

    communities = D1Service.get_communities(
        user_handle=user_handle,
        filter_mode=filter,
        search_query=q,
        type_filter=type
    )
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
        visibility=body.visibility,
        username=body.username,
        invite_link=body.inviteLink,
        settings=body.settings,
        image_url=body.imageUrl,
        initial_members=body.initialMembers
    )
    if not comm_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Failed to create community. Username might be taken.")

    return {
        "status": "success",
        "communityId": comm_id,
        "message": "Community created successfully."
    }


@communities_router.get("/{community_id}")
async def get_community(
    community_id: str,
    authorization: Optional[str] = Header(None)
):
    user_handle = None
    if authorization and authorization.startswith("Bearer "):
        try:
            _, user_handle = _get_auth_user(authorization)
        except:
            pass

    comm = D1Service.get_community_by_id(community_id, user_handle=user_handle)
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
    ok = D1Service.update_community_settings(
        community_id=community_id,
        user_handle=handle,
        name=body.name,
        description=body.description,
        image_url=body.imageUrl,
        visibility=body.visibility,
        username=body.username,
        settings=body.settings
    )
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only owner or admin with permission can update settings.")
    return {
        "status": "success",
        "message": "Community updated successfully."
    }


@communities_router.delete("/{community_id}")
async def delete_community(
    community_id: str,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.delete_community(community_id, handle)
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the community owner can delete the community.")
    return {
        "status": "success",
        "message": "Community deleted successfully."
    }


@communities_router.post("/{community_id}/join")
async def join_community(
    community_id: str,
    invite_code: Optional[str] = Query(None),
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    res = D1Service.join_community(community_id, handle, invite_code=invite_code)
    if not res.get("success"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=res.get("error", "Failed to join community."))
    return {
        "status": "success",
        "joinStatus": res.get("status", "joined"),
        "message": res.get("message", "Joined community successfully.")
    }


@communities_router.post("/{community_id}/leave")
async def leave_community(
    community_id: str,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    res = D1Service.leave_community(community_id, handle)
    if not res.get("success"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=res.get("error", "Failed to leave community."))
    return {
        "status": "success",
        "message": res.get("message", "Left community successfully.")
    }


@communities_router.get("/{community_id}/requests")
async def get_join_requests(
    community_id: str,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    requests = D1Service.get_join_requests(community_id, handle)
    return {
        "status": "success",
        "requests": requests
    }


@communities_router.post("/{community_id}/requests/{request_id}/respond")
async def respond_to_join_request(
    community_id: str,
    request_id: str,
    body: RespondJoinRequestModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.respond_join_request(community_id, request_id, handle, approve=body.approve)
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Permission denied or request not found.")
    return {
        "status": "success",
        "message": "Join request processed successfully."
    }


@communities_router.get("/{community_id}/members")
async def get_members(community_id: str):
    members = D1Service.get_community_members(community_id)
    return {
        "status": "success",
        "members": members
    }


@communities_router.put("/{community_id}/members/{target_handle}/role")
async def update_member_role(
    community_id: str,
    target_handle: str,
    body: UpdateRoleModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.update_member_role_and_permissions(
        community_id=community_id,
        admin_handle=handle,
        target_handle=target_handle,
        role=body.role,
        permissions=body.permissions
    )
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Permission denied to update member role.")
    return {
        "status": "success",
        "message": "Member role updated successfully."
    }


@communities_router.post("/{community_id}/transfer-ownership")
async def transfer_ownership(
    community_id: str,
    body: TransferOwnershipModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.transfer_community_ownership(community_id, handle, body.newOwnerHandle)
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only owner can transfer ownership.")
    return {
        "status": "success",
        "message": "Ownership transferred successfully."
    }


@communities_router.delete("/{community_id}/members/{target_handle}")
async def remove_member(
    community_id: str,
    target_handle: str,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.remove_community_member(community_id, handle, target_handle)
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Permission denied to remove member.")
    return {
        "status": "success",
        "message": "Member removed successfully."
    }


@communities_router.post("/{community_id}/regenerate-invite-link")
async def regenerate_invite_link(
    community_id: str,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    new_link = D1Service.regenerate_community_invite_link(community_id, handle)
    if not new_link:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only owner or admin with permission can regenerate invite link.")
    return {
        "status": "success",
        "inviteLink": new_link,
        "message": "Invite link regenerated successfully."
    }


@communities_router.post("/{community_id}/mute")
async def mute_community(
    community_id: str,
    body: MuteModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    D1Service.mute_community(community_id, handle, body.mutedUntil)
    return {
        "status": "success",
        "message": "Mute settings updated."
    }


@communities_router.post("/{community_id}/archive")
async def archive_community(
    community_id: str,
    body: ArchiveModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    D1Service.archive_community(community_id, handle, body.isArchived)
    return {
        "status": "success",
        "message": "Archive settings updated."
    }


@communities_router.get("/{community_id}/messages")
async def get_messages(
    community_id: str,
    limit: int = Query(50, ge=1, le=100),
    before: Optional[int] = Query(None),
    authorization: Optional[str] = Header(None)
):
    user_handle = None
    if authorization and authorization.startswith("Bearer "):
        try:
            _, user_handle = _get_auth_user(authorization)
        except:
            pass

    messages = D1Service.get_community_messages(community_id, user_handle=user_handle, limit=limit, before_ts=before)
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
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You do not have permission to post in this community.")

    return {
        "status": "success",
        "messageId": msg_id,
        "message": "Message sent successfully."
    }


@communities_router.put("/{community_id}/messages/{message_id}")
async def edit_message(
    community_id: str,
    message_id: str,
    body: EditMessageModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.edit_community_message(community_id, message_id, handle, body.content)
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Failed to edit message. You can only edit your own messages within 48 hours.")
    return {
        "status": "success",
        "message": "Message edited successfully."
    }


@communities_router.delete("/{community_id}/messages/{message_id}")
async def delete_message(
    community_id: str,
    message_id: str,
    mode: str = Query("everyone", pattern="^(everyone|for_me)$"),
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.delete_community_message(community_id, message_id, handle, mode=mode)
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Failed to delete message. Permission denied.")
    return {
        "status": "success",
        "message": "Message deleted."
    }


@communities_router.post("/{community_id}/messages/{message_id}/pin")
async def pin_message(
    community_id: str,
    message_id: str,
    body: PinMessageModel,
    authorization: Optional[str] = Header(None)
):
    _, handle = _get_auth_user(authorization)
    ok = D1Service.pin_community_message(community_id, message_id, handle, pin=body.pin)
    if not ok:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins and owners can pin messages.")
    return {
        "status": "success",
        "message": f"Message {'pinned' if body.pin else 'unpinned'} successfully."
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
