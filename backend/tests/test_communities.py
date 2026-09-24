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

def test_create_community(auth_headers):
    with patch.object(D1Service, 'create_community', return_value="new-comm-id"):
        res = client.post("/api/v1/communities", json={
            "name": "Tech Enthusiasts",
            "description": "Tech discussions",
            "isChannel": False
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
        get_res = client.get("/api/v1/communities/comm-1/messages")
        assert get_res.status_code == 200
        assert len(get_res.json()["messages"]) == 1
        assert get_res.json()["messages"][0]["content"] == "Hello everyone!"
