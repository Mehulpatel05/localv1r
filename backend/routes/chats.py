from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from services.d1_service import D1Service

router = APIRouter(prefix="/chats", tags=["1-on-1 Direct Chats"])

class SendDirectMessageRequest(BaseModel):
    sender: str
    receiver: str
    content: str
    imageUrl: Optional[str] = None
    mediaUrls: Optional[List[str]] = None
    messageType: str = "text"

class MarkReadRequest(BaseModel):
    user_handle: str

class DeleteMessageRequest(BaseModel):
    user_handle: str

@router.get("")
def get_user_chats(handle: str = Query(..., description="User handle")):
    """
    Get all direct chat conversations for a given user.
    """
    chats = D1Service.get_user_direct_chats(handle)
    return {"chats": chats}

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
def send_direct_message(req: SendDirectMessageRequest):
    """
    Send a direct 1-on-1 message.
    """
    if not req.sender or not req.receiver:
        raise HTTPException(status_code=400, detail="Sender and receiver are required")
    if not req.content and not req.imageUrl and not req.mediaUrls:
        raise HTTPException(status_code=400, detail="Message content or media is required")

    msg_id = D1Service.send_direct_message(
        sender=req.sender,
        receiver=req.receiver,
        content=req.content,
        image_url=req.imageUrl,
        media_urls=req.mediaUrls,
        message_type=req.messageType
    )
    if not msg_id:
        raise HTTPException(status_code=500, detail="Failed to send direct message")

    p1, p2 = D1Service.canonical_pair(req.sender, req.receiver)
    chat_id = f"{p1}_{p2}"

    return {
        "success": True,
        "messageId": msg_id,
        "chatId": chat_id
    }

@router.post("/{chat_id}/read")
def mark_direct_chat_read(chat_id: str, req: MarkReadRequest):
    """
    Mark all unread messages in direct chat as read for this user.
    """
    ok = D1Service.mark_direct_chat_read(chat_id, req.user_handle)
    return {"success": ok}

@router.delete("/message/{message_id}")
def delete_direct_message(message_id: str, req: DeleteMessageRequest):
    """
    Soft-delete a direct message sent by user.
    """
    ok = D1Service.delete_direct_message(message_id, req.user_handle)
    if not ok:
        raise HTTPException(status_code=400, detail="Unable to delete message")
    return {"success": True}
