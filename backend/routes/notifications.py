from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from services.d1_service import D1Service

router = APIRouter(prefix="/notifications", tags=["In-App Notifications"])

class CreateNotificationRequest(BaseModel):
    target_handle: str
    title: str
    body: str
    type: str
    sender_handle: Optional[str] = None
    data: Optional[Dict[str, Any]] = None

@router.get("")
def get_notifications(
    handle: str = Query(..., description="Target user handle"),
    limit: int = Query(50, ge=1, le=100)
):
    """
    Get notifications for a user.
    """
    notifs = D1Service.get_notifications(handle, limit=limit)
    return {"notifications": notifs}

@router.post("")
def create_notification(req: CreateNotificationRequest):
    """
    Create a new in-app notification.
    """
    notif_id = D1Service.create_notification(
        target_handle=req.target_handle,
        title=req.title,
        body=req.body,
        type=req.type,
        sender_handle=req.sender_handle,
        data=req.data
    )
    if not notif_id:
        raise HTTPException(status_code=500, detail="Failed to create notification")
    return {"success": True, "notificationId": notif_id}

@router.post("/{notification_id}/read")
def mark_notification_read(notification_id: str, handle: str = Query(..., description="User handle")):
    """
    Mark a notification as read.
    """
    ok = D1Service.mark_notification_read(notification_id, handle)
    return {"success": ok}

@router.post("/read-all")
def mark_all_notifications_read(handle: str = Query(..., description="User handle")):
    """
    Mark all notifications for a user as read.
    """
    ok = D1Service.mark_all_notifications_read(handle)
    return {"success": ok}
