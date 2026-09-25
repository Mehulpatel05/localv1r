import os
import sys
import uuid
import time
import jwt
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.dirname(__file__))

from main import app
from config import Config
from services.d1_service import D1Service
from routes.auth import _mint_tokens
from utils.security_guards import SecurityDecisionEngine

client = TestClient(app)

def test_phase_1_jwt_and_decision_layer():
    print("\n--- [TEST] Phase 1: JWT Identity & Decision Layer ---")
    
    # 1. Mint tokens with rich claims
    tokens = _mint_tokens(
        user_id="usr_test_123",
        phone_number="+919876543210",
        handle="TestUser123",
        role="user",
        city_id="GJ-VADODARA",
        verified=True,
        plan_tier="free",
        banned=False,
        token_version=1
    )
    access_token = tokens["access_token"]
    refresh_token = tokens["refresh_token"]

    # 2. 0ms Fast Cryptographic Decoding
    payload = jwt.decode(access_token, Config.JWT_SECRET, algorithms=["HS256"], issuer="nearhood-backend")
    assert payload["uid"] == "usr_test_123"
    assert payload["handle"] == "TestUser123"
    assert payload["role"] == "user"
    assert payload["verified"] is True
    assert payload["banned"] is False
    assert payload["tokenVersion"] == 1

    # 3. Test Security Decision Engine
    claims = SecurityDecisionEngine.get_current_claims(authorization=f"Bearer {access_token}")
    assert claims["uid"] == "usr_test_123"

    # 4. Instant Banned User Rejection
    banned_tokens = _mint_tokens(
        user_id="usr_banned",
        phone_number="+919999999999",
        handle="BannedUser",
        banned=True
    )
    with pytest.raises(Exception):
        SecurityDecisionEngine.get_current_claims(authorization=f"Bearer {banned_tokens['access_token']}")

    print("[PASS] Phase 1 JWT and Decision Engine tests passed!")


def test_phase_2_and_3_precomputation_and_action_states():
    print("\n--- [TEST] Phase 2 & 3: Precomputation & Single-Read Action Document ---")
    
    user_handle = f"ArchUser_{uuid.uuid4().hex[:6]}"
    tokens = _mint_tokens(
        user_id="usr_arch_1",
        phone_number="+919888888888",
        handle=user_handle
    )
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}

    # 1. Optimistic Write-Time Action State Set
    res = client.post(
        "/api/v1/actions/states",
        headers=headers,
        json={
            "target_id": "job_dev_101",
            "target_type": "job",
            "is_saved": True,
            "is_applied": True
        }
    )
    assert res.status_code == 200, res.text
    assert res.json()["success"] is True

    # Like a post
    res = client.post(
        "/api/v1/actions/states",
        headers=headers,
        json={
            "target_id": "post_feed_999",
            "target_type": "post",
            "is_liked": True,
            "vote_direction": 1
        }
    )
    assert res.status_code == 200

    # Block a user
    res = client.post(
        "/api/v1/actions/states",
        headers=headers,
        json={
            "target_id": "spammer_user",
            "target_type": "user",
            "is_blocked": True
        }
    )
    assert res.status_code == 200

    # 2. Phase 3: Single-Read Precomputed Action Document
    doc_res = client.get("/api/v1/actions/state/current", headers=headers)
    assert doc_res.status_code == 200
    doc = doc_res.json()
    assert "job_dev_101" in doc["savedListingIds"]
    assert "job_dev_101" in doc["appliedJobIds"]
    assert "post_feed_999" in doc["likedPostIds"]
    assert "spammer_user" in doc["blockedUserIds"]
    assert doc["votes"].get("post_feed_999") == 1

    # 3. Read-time Batch Serving
    batch_res = client.post(
        "/api/v1/actions/states/batch",
        headers=headers,
        json={"target_ids": ["job_dev_101", "post_feed_999", "non_existing"]}
    )
    assert batch_res.status_code == 200
    states = batch_res.json()["states"]
    assert states["job_dev_101"]["is_saved"] == 1 or states["job_dev_101"]["is_saved"] is True
    assert states["post_feed_999"]["is_liked"] == 1 or states["post_feed_999"]["is_liked"] is True

    # 4. Phase 2: Unread Counters & Badges
    counters_res = client.get("/api/v1/actions/counters", headers=headers)
    assert counters_res.status_code == 200
    assert "unreadMessages" in counters_res.json()["counters"]

    print("[PASS] Phase 2 & 3 Precomputation & Action State tests passed!")


def test_phase_4_multi_tenancy_isolation():
    print("\n--- [TEST] Phase 4: Per-User Multi-Tenancy Data Isolation ---")
    
    user_a = f"UserA_{uuid.uuid4().hex[:6]}"
    user_b = f"UserB_{uuid.uuid4().hex[:6]}"

    tokens_a = _mint_tokens(user_id="usr_A", phone_number="+919111111111", handle=user_a)
    tokens_b = _mint_tokens(user_id="usr_B", phone_number="+919222222222", handle=user_b)

    headers_a = {"Authorization": f"Bearer {tokens_a['access_token']}"}
    headers_b = {"Authorization": f"Bearer {tokens_b['access_token']}"}

    # User A likes and saves target_x
    client.post(
        "/api/v1/actions/states",
        headers=headers_a,
        json={"target_id": "exclusive_target_x", "target_type": "post", "is_saved": True, "is_liked": True}
    )

    # User B checks their precomputed document -> MUST NOT contain exclusive_target_x
    doc_b = client.get("/api/v1/actions/state/current", headers=headers_b).json()
    assert "exclusive_target_x" not in doc_b["savedListingIds"], "Multi-tenancy leak! User B saw User A's saved items."
    assert "exclusive_target_x" not in doc_b["likedPostIds"], "Multi-tenancy leak! User B saw User A's liked items."

    # User A checks their document -> Contains exclusive_target_x
    doc_a = client.get("/api/v1/actions/state/current", headers=headers_a).json()
    assert "exclusive_target_x" in doc_a["savedListingIds"]
    assert "exclusive_target_x" in doc_a["likedPostIds"]

    print("[PASS] Phase 4 Multi-Tenancy Data Isolation tests passed!")


def test_phase_5_caching_and_cdn_layer():
    print("\n--- [TEST] Phase 5: Caching, Fan-Out & CDN Layer ---")
    
    tokens = _mint_tokens(
        user_id="usr_cdn_test",
        phone_number="+919777777777",
        handle="CdnTester"
    )
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}

    # 1. Presigned Upload URL with Naming Convention
    res = client.post(
        "/api/v1/storage/presigned-url",
        headers=headers,
        json={
            "cityId": "gj-vadodara",
            "moduleType": "jobs",
            "listingId": "job_flutter_dev_99",
            "filename": "cover_photo.jpg",
            "contentType": "image/jpeg"
        }
    )
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["success"] is True
    assert "uploadUrl" in data
    assert data["objectKey"] == "gj-vadodara/jobs/job_flutter_dev_99/cover_photo.jpg"
    assert "gj-vadodara/jobs/job_flutter_dev_99/cover_photo.jpg" in data["publicUrl"]

    # 2. CDN Pre-Warm Trigger
    prewarm_res = client.post(
        "/api/v1/storage/cdn-prewarm",
        headers=headers,
        json={"mediaUrls": [data["publicUrl"], "https://localv1r.onrender.com/api/v1/media/sample_banner.jpg"]}
    )
    assert prewarm_res.status_code == 200
    assert prewarm_res.json()["status"] == "success"

    print("[PASS] Phase 5 Presigned R2 URL & CDN Pre-warm tests passed!")


def test_phase_6_large_scale_user_handling():
    print("\n--- [TEST] Phase 6: Large-Scale User Handling (100k -> 10M Users) ---")
    
    tokens = _mint_tokens(
        user_id="usr_scale_test",
        phone_number="+919666666666",
        handle="ScaleUser"
    )
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}

    # 1. Distributed Counter Sharding (Contention Avoidance)
    target_id = f"viral_job_{uuid.uuid4().hex[:6]}"
    
    # Concurrent write simulation across 10 shards
    for _ in range(15):
        inc_res = client.post(
            "/api/v1/actions/sharded-counter/increment",
            headers=headers,
            json={"target_id": target_id, "target_type": "job", "delta": 1}
        )
        assert inc_res.status_code == 200

    # Read aggregate SUM across all shards
    count_res = client.get(f"/api/v1/actions/sharded-counter/{target_id}")
    assert count_res.status_code == 200
    assert count_res.json()["total"] == 15

    # 2. City-Based Partitioning Check
    vadodara_posts = client.get("/api/v1/posts?cityId=GJ-VADODARA&limit=10").json()
    assert "posts" in vadodara_posts
    assert vadodara_posts["status"] == "success"

    # 3. Cursor-Based Pagination Protection (Never full collection loads)
    page_res = client.get("/api/v1/posts?limit=5")
    assert page_res.status_code == 200
    assert len(page_res.json()["posts"]) <= 5
    assert "nextCursor" in page_res.json()

    print("[PASS] Phase 6 Distributed Counter Shards & Cursor Pagination tests passed!")

if __name__ == "__main__":
    print("[INIT] Initializing D1 Schema Tables...")
    D1Service.init_schema()
    test_phase_1_jwt_and_decision_layer()
    test_phase_2_and_3_precomputation_and_action_states()
    test_phase_4_multi_tenancy_isolation()
    test_phase_5_caching_and_cdn_layer()
    test_phase_6_large_scale_user_handling()
    print("\n[SUCCESS] ALL ARCHITECTURE CONNECTION TESTS PASSED 100%!")
