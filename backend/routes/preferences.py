from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, Dict, Any, List
from services.d1_service import D1Service

router = APIRouter(prefix="/preferences", tags=["User Preferences & Call Privacy"])

class SavePreferencesRequest(BaseModel):
    handle: str
    preferences: Dict[str, Any] = {}
    callPrivacy: Optional[str] = "everyone"

class PinChatsRequest(BaseModel):
    handle: str
    chat_ids: List[str]
    action: str = "pin"  # "pin" or "unpin"

class MuteChatsRequest(BaseModel):
    handle: str
    chat_ids: List[str]
    action: str = "mute"  # "mute" or "unmute"
    duration_enum: Optional[str] = None  # "8h", "1w", "always"
    duration_seconds: Optional[int] = None  # fallback if duration_enum not set

@router.get("/{handle}")
def get_preferences(handle: str):
    """
    Get preferences and call privacy for user.
    """
    prefs = D1Service.get_user_preferences(handle)
    return {"preferences": prefs}

@router.post("")
def save_preferences(req: SavePreferencesRequest):
    """
    Save user preferences and call privacy to D1 with server timestamp validation and mutex lock.
    """
    if not req.handle:
        raise HTTPException(status_code=400, detail="Handle is required")
    ok = D1Service.save_user_preferences(
        handle=req.handle,
        preferences_dict=req.preferences,
        call_privacy=req.callPrivacy
    )
    return {"success": ok}

@router.post("/pin")
def pin_chats(req: PinChatsRequest):
    """
    Atomically pin or unpin chats using server-calculated timestamps and row lock.
    """
    if not req.handle:
        raise HTTPException(status_code=400, detail="Handle is required")
    res = D1Service.pin_user_chats(req.handle, req.chat_ids, action=req.action)
    return {"success": True, **res}

@router.post("/mute")
def mute_chats(req: MuteChatsRequest):
    """
    Atomically mute or unmute chats using server-calculated timestamps and row lock.
    """
    if not req.handle:
        raise HTTPException(status_code=400, detail="Handle is required")
    res = D1Service.mute_user_chats(
        req.handle,
        req.chat_ids,
        action=req.action,
        duration_enum=req.duration_enum,
        duration_seconds=req.duration_seconds
    )
    return {"success": True, **res}
