from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, Dict, Any
from services.d1_service import D1Service

router = APIRouter(prefix="/preferences", tags=["User Preferences & Call Privacy"])

class SavePreferencesRequest(BaseModel):
    handle: str
    preferences: Dict[str, Any] = {}
    callPrivacy: Optional[str] = "everyone"

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
    Save user preferences and call privacy to D1.
    """
    if not req.handle:
        raise HTTPException(status_code=400, detail="Handle is required")
    ok = D1Service.save_user_preferences(
        handle=req.handle,
        preferences_dict=req.preferences,
        call_privacy=req.callPrivacy
    )
    return {"success": ok}
