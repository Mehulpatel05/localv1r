from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from services.d1_service import D1Service
from services.fcm_service import send_push_to_token

router = APIRouter(prefix="/notifications", tags=["In-App Notifications"])

class CreateNotificationRequest(BaseModel):
    target_handle: str
    title: str
    body: str
    type: str
    sender_handle: Optional[str] = None
    data: Optional[Dict[str, Any]] = None

class FCMTokenRequest(BaseModel):
    handle: str
    fcm_token: str

@router.post("/fcm-token")
def register_fcm_token(req: FCMTokenRequest):
    """
    Save or update device FCM push token for user handle.
    """
    clean_handle = req.handle.replace("@", "").strip().lower()
    if clean_handle and req.fcm_token:
        D1Service.save_user_fcm_token(clean_handle, req.fcm_token)
    return {"success": True}

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
    Create a new in-app notification & send instant FCM push to target device!
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

    # 🚀 INSTANT BACKGROUND PUSH: Send Google FCM Push to target user's device!
    try:
        fcm_token = D1Service.get_user_fcm_token(req.target_handle)
        if fcm_token:
            payload = req.data or {}
            payload["type"] = req.type
            if req.sender_handle:
                payload["senderHandle"] = req.sender_handle
            send_push_to_token(fcm_token, req.title, req.body, payload)
    except Exception as e:
        print(f"[FCM Push Notice] {e}")

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
