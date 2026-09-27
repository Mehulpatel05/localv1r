import jwt
from fastapi import APIRouter, HTTPException, Query, Header, status
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any, Tuple
from config import Config
from services.d1_service import D1Service
from services.fcm_service import send_push_to_token

router = APIRouter(prefix="/chats", tags=["1-on-1 Direct Chats"])

def _get_optional_auth_user(authorization: Optional[str]) -> Optional[Tuple[str, str]]:
    if not authorization or not authorization.startswith("Bearer "):
        return None
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
            return uid, handle
    except Exception:
        pass
    return None

class SendDirectMessageRequest(BaseModel):
    sender: str
    receiver: str
    content: Optional[str] = Field(default="", max_length=4000)
    imageUrl: Optional[str] = None
    mediaUrls: Optional[List[str]] = None
    messageType: str = "text"

class MarkReadRequest(BaseModel):
    user_handle: str

class EditMessageRequest(BaseModel):
    user_handle: str
    content: str = Field(..., min_length=1, max_length=4000)

class DeleteMessageRequest(BaseModel):
    user_handle: str
    for_everyone: bool = False

@router.get("")
def get_user_chats(
    handle: str = Query(..., description="User handle"),
    authorization: Optional[str] = Header(None, alias="Authorization")
):
    """
    Get all direct chat conversations for a given user.
    """
    auth = _get_optional_auth_user(authorization)
    if auth:
        _, auth_handle = auth
        if auth_handle and auth_handle.replace("@", "").lower() != handle.replace("@", "").lower():
            # Defense-in-depth: enforce token handle
            handle = auth_handle
    chats = D1Service.get_user_direct_chats(handle)
    return {"chats": chats}

@router.get("/ids")
def get_user_chat_ids(
    handle: str = Query(..., description="User handle"),
    query: Optional[str] = Query(None, description="Optional search query filter"),
    authorization: Optional[str] = Header(None, alias="Authorization")
):
    """
    ⚡ Backend query-bound select-all: fetch all conversation IDs matching active query/filters.
    """
    auth = _get_optional_auth_user(authorization)
    if auth:
        _, auth_handle = auth
        if auth_handle and auth_handle.replace("@", "").lower() != handle.replace("@", "").lower():
            handle = auth_handle
    chat_ids = D1Service.get_user_chat_ids(handle, query=query)
    return {"chatIds": chat_ids, "total": len(chat_ids)}

@router.get("/{chat_id}/messages")
def get_direct_messages(
    chat_id: str,
    limit: int = Query(50, ge=1, le=100),
    before: Optional[int] = Query(None, description="Timestamp to fetch older messages before")
):
    """
    Get messages for a direct chat conversation.
    """
    messages = D1Service.get_direct_messages(chat_id, limit=limit, before_ts=before)
    return {"messages": messages}

@router.post("/message")
def send_direct_message(
    req: SendDirectMessageRequest,
    authorization: Optional[str] = Header(None, alias="Authorization")
):
    """
    Send a direct 1-on-1 message.
    """
    auth = _get_optional_auth_user(authorization)
    if auth:
        _, auth_handle = auth
        if auth_handle and auth_handle.replace("@", "").lower() != req.sender.replace("@", "").lower():
            req.sender = auth_handle

    if not req.sender or not req.receiver:
        raise HTTPException(status_code=400, detail="Sender and receiver are required")
    if not (req.content or "").strip() and not req.imageUrl and not req.mediaUrls:
        raise HTTPException(status_code=400, detail="Message content or media is required")

    msg_id = D1Service.send_direct_message(
        sender=req.sender,
        receiver=req.receiver,
        content=req.content or "",
        image_url=req.imageUrl,
        media_urls=req.mediaUrls,
        message_type=req.messageType
    )
    if not msg_id:
        raise HTTPException(status_code=500, detail="Failed to send direct message")

    p1, p2 = D1Service.canonical_pair(req.sender, req.receiver)
    chat_id = f"{p1}_{p2}"

    # 🚀 INSTANT BACKGROUND PUSH: Send FCM Push Notification to Receiver Phone!
    try:
        receiver_token = D1Service.get_user_fcm_token(req.receiver)
        if receiver_token:
            sender_clean = req.sender.replace("@", "").strip()
            body_text = (req.content or "").strip() or ("[Image]" if (req.imageUrl or req.mediaUrls) else "New message")
            send_push_to_token(
                receiver_token,
                title=f"@{sender_clean}",
                body=body_text,
                data_payload={
                    "type": "chat",
                    "senderHandle": sender_clean,
                    "partnerHandle": sender_clean,
                    "chatId": chat_id
                }
            )
    except Exception as e:
        print(f"[Chat Push Notice] {e}")

    return {
        "success": True,
        "messageId": msg_id,
        "chatId": chat_id
    }

@router.put("/message/{message_id}")
def edit_direct_message(
    message_id: str,
    req: EditMessageRequest,
    authorization: Optional[str] = Header(None, alias="Authorization")
):
    """
    Edit a direct message sent by user. Enforces 15-minute hard limit.
    """
    auth = _get_optional_auth_user(authorization)
    if auth:
        _, auth_handle = auth
        if auth_handle:
            req.user_handle = auth_handle

    ok, reason = D1Service.edit_direct_message(message_id, req.user_handle, req.content)
    if not ok:
        raise HTTPException(status_code=400, detail=reason)
    return {"success": True, "detail": reason, "messageId": message_id}

@router.post("/{chat_id}/read")
def mark_direct_chat_read(
    chat_id: str,
    req: MarkReadRequest,
    authorization: Optional[str] = Header(None, alias="Authorization")
):
    """
    Mark all unread messages in direct chat as read for this user.
    """
    auth = _get_optional_auth_user(authorization)
    if auth:
        _, auth_handle = auth
        if auth_handle:
            req.user_handle = auth_handle

    ok = D1Service.mark_direct_chat_read(chat_id, req.user_handle)
    return {"success": ok}

@router.delete("/message/{message_id}")
def delete_direct_message(
    message_id: str,
    req: DeleteMessageRequest,
    authorization: Optional[str] = Header(None, alias="Authorization")
):
    """
    Delete a direct message. Supports 'delete for me' and 'delete for everyone' (with 48-hr limit and tombstone).
    """
    auth = _get_optional_auth_user(authorization)
    if auth:
        _, auth_handle = auth
        if auth_handle:
            req.user_handle = auth_handle

    ok, reason = D1Service.delete_direct_message(message_id, req.user_handle, for_everyone=req.for_everyone)
    if not ok:
        raise HTTPException(status_code=400, detail=reason)
    return {"success": True, "detail": reason}
