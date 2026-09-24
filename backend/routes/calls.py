from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from services.d1_service import D1Service

router = APIRouter(prefix="/calls", tags=["WebRTC Calls Signaling"])

class InitiateCallRequest(BaseModel):
    caller: str
    receiver: str
    callType: str = "audio"
    sdpOffer: str

class AnswerCallRequest(BaseModel):
    receiver: str
    sdpAnswer: str

class AddIceCandidateRequest(BaseModel):
    handle: str
    candidate: Dict[str, Any]

class UpdateCallStatusRequest(BaseModel):
    status: str

@router.post("/initiate")
def initiate_call(req: InitiateCallRequest):
    """
    Initiate a WebRTC call (creates call with SDP offer in D1).
    """
    if not req.caller or not req.receiver:
        raise HTTPException(status_code=400, detail="Caller and receiver required")

    call_id = D1Service.initiate_call(
        caller=req.caller,
        receiver=req.receiver,
        call_type=req.callType,
        sdp_offer=req.sdpOffer
    )
    if not call_id:
        raise HTTPException(status_code=500, detail="Failed to initiate call")

    return {
        "success": True,
        "callId": call_id
    }

@router.get("/active")
def get_active_call(handle: str = Query(..., description="User handle")):
    """
    Check for any active ringing/accepted incoming or outgoing call for this user.
    """
    call = D1Service.get_active_call_for_user(handle)
    return {"call": call}

@router.get("/{call_id}")
def get_call_by_id(call_id: str):
    """
    Fetch call metadata, SDP answer, and ICE candidates for WebRTC peer connection.
    """
    call = D1Service.get_call_by_id(call_id)
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    return {"call": call}

@router.post("/{call_id}/answer")
def answer_call(call_id: str, req: AnswerCallRequest):
    """
    Accept an incoming call and attach SDP answer.
    """
    ok = D1Service.answer_call(call_id, req.receiver, req.sdpAnswer)
    if not ok:
        raise HTTPException(status_code=400, detail="Failed to answer call")
    return {"success": True}

@router.post("/{call_id}/ice")
def add_ice_candidate(call_id: str, req: AddIceCandidateRequest):
    """
    Add a WebRTC ICE candidate to call in D1.
    """
    ok = D1Service.add_call_ice_candidate(call_id, req.handle, req.candidate)
    return {"success": ok}

@router.post("/{call_id}/status")
def update_call_status(call_id: str, req: UpdateCallStatusRequest):
    """
    Update call status (e.g., 'ended', 'rejected', 'busy', 'declined').
    """
    ok = D1Service.update_call_status(call_id, req.status)
    return {"success": ok}
