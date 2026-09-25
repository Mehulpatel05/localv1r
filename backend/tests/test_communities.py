import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
import jwt
import time

from main import app
from config import Config
from services.d1_service import D1Service

client = TestClient(app)

def create_mock_jwt(uid: str, handle: str) -> str:
    payload = {
        "sub": uid,
        "handle": handle,
        "type": "access",
        "iss": "nearhood-backend",
        "exp": int(time.time()) + 3600
    }
    return jwt.encode(payload, Config.JWT_SECRET, algorithm="HS256")

@pytest.fixture
def auth_headers():
    token = create_mock_jwt("user-123", "alice")
    return {"Authorization": f"Bearer {token}"}

@pytest.fixture
def bob_auth_headers():
    token = create_mock_jwt("user-456", "bob")
    return {"Authorization": f"Bearer {token}"}

def test_list_communities():
    with patch.object(D1Service, 'get_communities', return_value=[
        {"id": "comm-1", "name": "Vadodara General Chat", "description": "City chat", "isChannel": False, "adminHandle": "alice", "memberCount": 10, "imageUrl": None, "createdAt": "2026-09-24T12:00:00Z"}
    ]):
        res = client.get("/api/v1/communities")
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "success"
        assert len(data["communities"]) == 1
        assert data["communities"][0]["name"] == "Vadodara General Chat"

def test_check_username():
    with patch.object(D1Service, 'check_community_username_available', return_value=True):
        res = client.get("/api/v1/communities/check-username?username=vadodara_hub")
        assert res.status_code == 200
        assert res.json()["available"] == True

def test_create_community(auth_headers):
    with patch.object(D1Service, 'create_community', return_value="new-comm-id"):
        res = client.post("/api/v1/communities", json={
            "name": "Tech Enthusiasts",
            "description": "Tech discussions",
            "isChannel": False,
            "visibility": "public",
            "username": "tech_vadodara"
        }, headers=auth_headers)
        assert res.status_code == 201
        data = res.json()
        assert data["status"] == "success"
        assert data["communityId"] == "new-comm-id"

def test_send_and_get_messages(auth_headers):
    with patch.object(D1Service, 'send_community_message', return_value="msg-123"), \
         patch.object(D1Service, 'get_community_messages', return_value=[
             {"id": "msg-123", "communityId": "comm-1", "authorHandle": "alice", "content": "Hello everyone!", "mediaUrls": [], "type": "text", "reactions": {}, "createdAt": "2026-09-24T12:00:00Z"}
         ]):
        # Send
        send_res = client.post("/api/v1/communities/comm-1/messages", json={
            "content": "Hello everyone!"
        }, headers=auth_headers)
        assert send_res.status_code == 201
        assert send_res.json()["messageId"] == "msg-123"

        # Get
        get_res = client.get("/api/v1/communities/comm-1/messages", headers=auth_headers)
        assert get_res.status_code == 200
        assert len(get_res.json()["messages"]) == 1
        assert get_res.json()["messages"][0]["content"] == "Hello everyone!"

def test_mute_and_archive(auth_headers):
    with patch.object(D1Service, 'mute_community', return_value=True), \
         patch.object(D1Service, 'archive_community', return_value=True):
        res_mute = client.post("/api/v1/communities/comm-1/mute", json={"mutedUntil": 3600}, headers=auth_headers)
        assert res_mute.status_code == 200
        res_archive = client.post("/api/v1/communities/comm-1/archive", json={"isArchived": True}, headers=auth_headers)
        assert res_archive.status_code == 200

def test_edit_message(auth_headers):
    with patch.object(D1Service, 'edit_community_message', return_value=True):
        res = client.put("/api/v1/communities/comm-1/messages/msg-123", json={
            "content": "Updated content"
        }, headers=auth_headers)
        assert res.status_code == 200
        assert res.json()["status"] == "success"

def test_delete_message_for_me_and_everyone(auth_headers):
    with patch.object(D1Service, 'delete_community_message', return_value=True):
        # Delete for me
        res_me = client.delete("/api/v1/communities/comm-1/messages/msg-123?mode=for_me", headers=auth_headers)
        assert res_me.status_code == 200

        # Delete for everyone
        res_all = client.delete("/api/v1/communities/comm-1/messages/msg-123?mode=everyone", headers=auth_headers)
        assert res_all.status_code == 200

def test_delete_entire_community(auth_headers, bob_auth_headers):
    with patch.object(D1Service, 'delete_community', side_effect=lambda cid, handle: handle == "alice"):
        # Owner delete succeeds
        res_owner = client.delete("/api/v1/communities/comm-1", headers=auth_headers)
        assert res_owner.status_code == 200
        assert res_owner.json()["status"] == "success"

        # Non-owner delete fails with 403
        res_non_owner = client.delete("/api/v1/communities/comm-1", headers=bob_auth_headers)
        assert res_non_owner.status_code == 403

def test_regenerate_invite_link(auth_headers, bob_auth_headers):
    with patch.object(D1Service, 'regenerate_community_invite_link', side_effect=lambda cid, handle: "join_new_abc123" if handle == "alice" else None):
        res_admin = client.post("/api/v1/communities/comm-1/regenerate-invite-link", headers=auth_headers)
        assert res_admin.status_code == 200
        assert res_admin.json()["inviteLink"] == "join_new_abc123"

        res_non_admin = client.post("/api/v1/communities/comm-1/regenerate-invite-link", headers=bob_auth_headers)
        assert res_non_admin.status_code == 403

def test_remove_member(auth_headers):
    with patch.object(D1Service, 'remove_community_member', return_value=True):
        res = client.delete("/api/v1/communities/comm-1/members/bob", headers=auth_headers)
        assert res.status_code == 200
        assert res.json()["message"] == "Member removed successfully."

def test_update_member_role_and_transfer_ownership(auth_headers):
    with patch.object(D1Service, 'update_member_role_and_permissions', return_value=True), \
         patch.object(D1Service, 'transfer_community_ownership', return_value=True):
        res_role = client.put("/api/v1/communities/comm-1/members/bob/role", json={
            "role": "admin",
            "permissions": {"can_delete_messages": True}
        }, headers=auth_headers)
        assert res_role.status_code == 200

        res_transfer = client.post("/api/v1/communities/comm-1/transfer-ownership", json={
            "newOwnerHandle": "bob"
        }, headers=auth_headers)
        assert res_transfer.status_code == 200

def test_reject_promoting_to_owner_via_role_endpoint(auth_headers):
    # API schema rejects role="owner" (only admin | member allowed)
    res = client.put("/api/v1/communities/comm-1/members/bob/role", json={
        "role": "owner"
    }, headers=auth_headers)
    assert res.status_code in (400, 422)  # Validation error (schema regex rejects 'owner')

    # D1Service logic also rejects owner directly
    assert D1Service.update_member_role_and_permissions("comm-1", "alice", "bob", "owner") == False

def test_admin_cannot_kick_another_admin_without_can_manage_admins():
    # Mock community where Charlie is an admin with ONLY can_remove_members (can_manage_admins is False)
    mock_comm = {
        "id": "comm-1",
        "name": "Test Group",
        "ownerHandle": "alice",
        "myRole": "admin",
        "myPermissions": {"can_remove_members": True, "can_manage_admins": False}
    }
    
    with patch.object(D1Service, 'get_community_by_id', return_value=mock_comm), \
         patch.object(D1Service, 'query', return_value=[{"role": "admin"}]):
        # Charlie tries to kick Bob (who is also an admin) -> Must FAIL
        can_kick_admin = D1Service.remove_community_member("comm-1", "charlie", "bob")
        assert can_kick_admin == False

    with patch.object(D1Service, 'get_community_by_id', return_value=mock_comm), \
         patch.object(D1Service, 'query', return_value=[{"role": "member"}]), \
         patch.object(D1Service, 'execute', return_value=True), \
         patch.object(D1Service, 'send_community_message', return_value="sys-1"):
        # Charlie tries to kick Dave (who is a regular member) -> Must SUCCEED
        can_kick_member = D1Service.remove_community_member("comm-1", "charlie", "dave")
        assert can_kick_member == True

def test_owner_cannot_self_demote_via_role_endpoint(auth_headers):
    # Alice is Owner of comm-1. Alice tries to PUT .../members/alice/role to demote herself to 'member' or 'admin'
    res = client.put("/api/v1/communities/comm-1/members/alice/role", json={
        "role": "member"
    }, headers=auth_headers)
    assert res.status_code == 403

    # D1Service directly rejects owner self-demotion
    mock_comm = {
        "id": "comm-1",
        "name": "Test Group",
        "ownerHandle": "alice",
        "myRole": "owner",
        "myPermissions": {}
    }
    with patch.object(D1Service, 'get_community_by_id', return_value=mock_comm):
        # 1. Self-modification blocked
        assert D1Service.update_member_role_and_permissions("comm-1", "alice", "alice", "member") == False
        # 2. Modifying owner handle by another admin blocked
        assert D1Service.update_member_role_and_permissions("comm-1", "bob", "alice", "member") == False
