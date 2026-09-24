from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from services.d1_service import D1Service

router = APIRouter(prefix="/presence", tags=["Online Presence & Last Seen"])

class UpdatePresenceRequest(BaseModel):
    handle: str
    isOnline: bool

class BulkPresenceRequest(BaseModel):
    handles: List[str]

@router.post("/heartbeat")
def heartbeat(req: UpdatePresenceRequest):
    """
    Update online presence heartbeat for user in D1.
    """
    if not req.handle:
        raise HTTPException(status_code=400, detail="Handle is required")
    ok = D1Service.update_presence(req.handle, req.isOnline)
    return {"success": ok}

@router.get("/{handle}")
def get_user_presence(handle: str):
    """
    Get online presence and last seen for a user.
    """
    presence = D1Service.get_presence(handle)
    return presence

@router.post("/bulk")
def get_bulk_presence(req: BulkPresenceRequest):
    """
    Get presence status for multiple users simultaneously.
    """
    presence_map = D1Service.get_bulk_presence(req.handles)
    return {"presence": presence_map}
