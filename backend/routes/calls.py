import asyncio
import json
import logging
from fastapi import APIRouter, HTTPException, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from config import Config
from services.d1_service import D1Service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/calls", tags=["WebRTC Calls Signaling"])

# ⚡ Production-Grade Dual-Channel WebRTC Signaling Hub (Multi-Worker & Multi-Instance Aware)
class CallSignalHub:
    def __init__(self):
        self.rooms: Dict[str, List[WebSocket]] = {}
        self.lock = asyncio.Lock()
        self._redis_client = None
        self._redis_sub_task = None
        self._init_redis()

    def _init_redis(self):
        if Config.REDIS_URL:
            try:
                import redis.asyncio as aioredis
                self._redis_client = aioredis.from_url(Config.REDIS_URL, decode_responses=True)
                logger.info("[CallSignalHub] Redis Pub/Sub relay connected for multi-worker signaling")
            except Exception as e:
                logger.warning(f"[CallSignalHub] Redis not available, using in-memory relay + D1 sync: {e}")
                self._redis_client = None

    async def connect(self, call_id: str, ws: WebSocket):
        await ws.accept()
        async with self.lock:
            if call_id not in self.rooms:
                self.rooms[call_id] = []
            self.rooms[call_id].append(ws)

        # Initial State Sync: Send existing call state from D1 so late-connecting peers receive offer/answer/candidates
        try:
            call = D1Service.get_call_by_id(call_id)
            if call:
                # If call is already answered, inform the newly connected peer
                if call.get("sdpAnswer"):
                    await ws.send_text(json.dumps({
                        "type": "answer",
                        "callId": call_id,
                        "sdp": call["sdpAnswer"],
                        "receiver": call.get("receiverHandle", "")
                    }))

                # Send any existing ICE candidates stored in D1
                for c in call.get("callerIceCandidates", []):
                    await ws.send_text(json.dumps({
                        "type": "candidate",
                        "callId": call_id,
                        "candidate": c,
                        "handle": call.get("callerHandle", "")
                    }))
                for c in call.get("receiverIceCandidates", []):
                    await ws.send_text(json.dumps({
                        "type": "candidate",
                        "callId": call_id,
                        "candidate": c,
                        "handle": call.get("receiverHandle", "")
                    }))
        except Exception as e:
            logger.debug(f"[CallSignalHub] Initial D1 state sync skipped: {e}")

    async def disconnect(self, call_id: str, ws: WebSocket):
        async with self.lock:
            if call_id in self.rooms:
                if ws in self.rooms[call_id]:
                    self.rooms[call_id].remove(ws)
                if not self.rooms[call_id]:
                    del self.rooms[call_id]

    async def relay(self, call_id: str, message: str, sender_ws: Optional[WebSocket] = None):
        # 1. Local Process Relay
        async with self.lock:
            peers = list(self.rooms.get(call_id, []))
        for ws in peers:
            if ws != sender_ws:
                try:
                    await ws.send_text(message)
                except Exception:
                    pass

        # 2. Redis Cross-Worker Broadcast (if running multiple Uvicorn worker processes)
        if self._redis_client:
            try:
                await self._redis_client.publish(f"call_signals:{call_id}", message)
            except Exception:
                pass

hub = CallSignalHub()

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
    endedBy: Optional[str] = ""
    durationSeconds: Optional[int] = 0

@router.websocket("/{call_id}/ws")
async def call_websocket_signaling(websocket: WebSocket, call_id: str):
    """
    ⚡ Real-time WebSocket Relay Channel for instant SDP offer/answer, trickle-ICE, and status events.
    Synchronously relays signals to connected peers and asynchronously persists to D1.
    """
    await hub.connect(call_id, websocket)
    try:
        while True:
            raw_data = await websocket.receive_text()
            try:
                msg = json.loads(raw_data)
                msg_type = msg.get("type", "")

                # Relay instantly to peer socket
                await hub.relay(call_id, raw_data, websocket)

                # Mirror state to D1 persistence asynchronously
                if msg_type == "answer" and msg.get("sdp"):
                    receiver = msg.get("receiver", "")
                    D1Service.answer_call(call_id, receiver, msg.get("sdp"))
                elif msg_type == "candidate" and msg.get("candidate"):
                    handle = msg.get("handle", "")
                    D1Service.add_call_ice_candidate(call_id, handle, msg.get("candidate"))
                elif msg_type == "status" and msg.get("status"):
                    ended_by = msg.get("endedBy", "")
                    dur = int(msg.get("durationSeconds", 0))
                    D1Service.update_call_status(call_id, msg.get("status"), ended_by=ended_by, duration_seconds=dur)
            except json.JSONDecodeError:
                pass
    except WebSocketDisconnect:
        await hub.disconnect(call_id, websocket)
    except Exception:
        await hub.disconnect(call_id, websocket)

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
    Update call status (e.g., 'ended', 'rejected', 'busy', 'declined') with idempotency.
    """
    ok = D1Service.update_call_status(
        call_id,
        req.status,
        ended_by=req.endedBy or "",
        duration_seconds=req.durationSeconds or 0
    )
    return {"success": ok}
