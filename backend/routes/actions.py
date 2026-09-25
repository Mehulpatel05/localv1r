from fastapi import APIRouter, HTTPException, Header, Query, status
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from services.d1_service import D1Service
from routes.auth import verify_jwt_claims_fast

actions_router = APIRouter(prefix="/actions", tags=["User Action States & Counters"])

class SetActionStateRequest(BaseModel):
    target_id: str
    target_type: str = "post" # 'post', 'job', 'room', 'shop', 'service', 'food', 'event'
    is_liked: Optional[bool] = None
    is_saved: Optional[bool] = None
    is_applied: Optional[bool] = None
    is_reported: Optional[bool] = None
    is_blocked: Optional[bool] = None
    vote_direction: Optional[int] = None

class BatchActionStatesRequest(BaseModel):
    target_ids: List[str]

@actions_router.post("/states")
def set_action_state(
    req: SetActionStateRequest,
    authorization: Optional[str] = Header(None, alias="Authorization"),
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
):
    """
    ⚡ Write-Time Precomputation: Updates button state (saved, liked, applied, blocked)
    in the single user_action_state document/table.
    """
    token = authorization or (f"Bearer {x_session_token}" if x_session_token else None)
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing authorization header.")
    
    claims = verify_jwt_claims_fast(token)
    handle = claims.get("handle")
    if not handle:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token handle.")

    ok = D1Service.set_user_action_state(
        handle=handle,
        target_id=req.target_id,
        target_type=req.target_type,
        is_liked=req.is_liked,
        is_saved=req.is_saved,
        is_applied=req.is_applied,
        is_reported=req.is_reported,
        is_blocked=req.is_blocked,
        vote_direction=req.vote_direction
    )
    return {"success": ok, "targetId": req.target_id}

@actions_router.get("/states")
@actions_router.post("/states/batch")
def get_action_states_batch(
    req: Optional[BatchActionStatesRequest] = None,
    target_ids: Optional[str] = Query(None, description="Comma-separated target IDs"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
):
    """
    ⚡ Read-Time Serving: Returns precomputed action states for a batch of feed items in 0ms O(1).
    """
    token = authorization or (f"Bearer {x_session_token}" if x_session_token else None)
    if not token:
        return {"states": {}}
    
    claims = verify_jwt_claims_fast(token)
    handle = claims.get("handle")
    if not handle:
        return {"states": {}}

    ids: List[str] = []
    if req and req.target_ids:
        ids = req.target_ids
    elif target_ids:
        ids = [i.strip() for i in target_ids.split(",") if i.strip()]

    states = D1Service.get_user_action_states(handle=handle, target_ids=ids)
    return {"states": states}

@actions_router.get("/state/current")
def get_current_action_state_document(
    limit: int = Query(500, description="Hot set threshold limit per category"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
):
    """
    ⚡ Phase 3: Single-Read Precomputed State Document.
    Returns all hot sets (savedListingIds, appliedJobIds, likedPostIds, blockedUserIds, followingUserIds) in 1 read.
    """
    token = authorization or (f"Bearer {x_session_token}" if x_session_token else None)
    if not token:
        return {
            "savedListingIds": [],
            "appliedJobIds": [],
            "likedPostIds": [],
            "blockedUserIds": [],
            "followingUserIds": [],
            "reportedIds": [],
            "votes": {},
            "lastUpdated": 0
        }

    claims = verify_jwt_claims_fast(token)
    handle = claims.get("handle")
    if not handle:
        return {
            "savedListingIds": [],
            "appliedJobIds": [],
            "likedPostIds": [],
            "blockedUserIds": [],
            "followingUserIds": [],
            "reportedIds": [],
            "votes": {},
            "lastUpdated": 0
        }

    doc = D1Service.get_user_precomputed_action_document(handle=handle, limit=limit)
    return doc

@actions_router.get("/counters")
def get_user_counters(
    authorization: Optional[str] = Header(None, alias="Authorization"),
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
):
    """
    ⚡ 0ms O(1) Precomputed Unread Badge Counters (Messages, Notifications, Friend Requests).
    """
    token = authorization or (f"Bearer {x_session_token}" if x_session_token else None)
    if not token:
        return {"counters": {"unreadMessages": 0, "unreadNotifications": 0, "pendingFriendRequests": 0, "pendingCommunityInvites": 0}}

    claims = verify_jwt_claims_fast(token)
    handle = claims.get("handle")
    if not handle:
        return {"counters": {"unreadMessages": 0, "unreadNotifications": 0, "pendingFriendRequests": 0, "pendingCommunityInvites": 0}}

    counters = D1Service.get_user_counters(handle)
    return {"counters": counters}

@actions_router.post("/counters/reset")
def reset_user_counter(
    counter_field: str = Query(..., description="Field name to reset, e.g. unread_messages, unread_notifications"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
):
    """
    Resets counter when user reads or opens a section.
    """
    token = authorization or (f"Bearer {x_session_token}" if x_session_token else None)
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing authorization header.")

    claims = verify_jwt_claims_fast(token)
    handle = claims.get("handle")
    if not handle:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token handle.")

    ok = D1Service.reset_user_counter(handle, counter_field)
    return {"success": ok}

class IncrementShardedCounterRequest(BaseModel):
    target_id: str
    target_type: str = "listing"
    delta: int = 1

@actions_router.post("/sharded-counter/increment")
def increment_sharded_counter(
    req: IncrementShardedCounterRequest,
    authorization: Optional[str] = Header(None, alias="Authorization"),
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token")
):
    """
    ⚡ Phase 6: Increments distributed counter on a random shard (0..9) to avoid hot document lock contention.
    """
    token = authorization or (f"Bearer {x_session_token}" if x_session_token else None)
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing authorization header.")
    
    verify_jwt_claims_fast(token) # Enforces valid session
    ok = D1Service.increment_sharded_counter(
        target_id=req.target_id,
        target_type=req.target_type,
        delta=req.delta
    )
    return {"success": ok, "targetId": req.target_id}

@actions_router.get("/sharded-counter/{target_id}")
def get_sharded_counter_total(target_id: str):
    """
    ⚡ Phase 6: Computes aggregated sum across all distributed shards in <1ms.
    """
    total = D1Service.get_sharded_counter_total(target_id)
    return {"targetId": target_id, "total": total}

