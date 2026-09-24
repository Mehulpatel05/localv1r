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

def test_list_friends(auth_headers):
    with patch.object(D1Service, 'get_friends', return_value=[
        {"id": "alice_bob", "users": ["alice", "bob"], "otherUser": "bob", "avatarUrl": "https://r2/bob.png", "reputation": 10, "createdAt": "2026-09-24T12:00:00Z"}
    ]):
        res = client.get("/api/v1/friends", headers=auth_headers)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "success"
        assert len(data["friends"]) == 1
        assert data["friends"][0]["otherUser"] == "bob"

def test_send_friend_request(auth_headers):
    with patch.object(D1Service, 'send_friend_request', return_value=(True, "Friend request sent")):
        res = client.post("/api/v1/friends/request", json={"receiverHandle": "bob"}, headers=auth_headers)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "success"
        assert data["message"] == "Friend request sent"

def test_accept_friend_request(auth_headers):
    with patch.object(D1Service, 'accept_friend_request', return_value=True):
        res = client.post("/api/v1/friends/accept", json={"senderHandle": "bob"}, headers=auth_headers)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "success"

def test_unfriend(auth_headers):
    with patch.object(D1Service, 'unfriend', return_value=True):
        res = client.post("/api/v1/friends/unfriend", json={"otherHandle": "bob"}, headers=auth_headers)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "success"

def test_relationship_status(auth_headers):
    with patch.object(D1Service, 'get_relationship_status', return_value="friends"):
        res = client.get("/api/v1/friends/status/bob", headers=auth_headers)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "success"
        assert data["relationship"] == "friends"
