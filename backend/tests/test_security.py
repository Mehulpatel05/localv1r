import pytest
import time
import jwt
from fastapi.testclient import TestClient
import sys
import os

# Include parent directory in python path to import main
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from main import app, generate_mod_session_token
from config import Config

client = TestClient(app)

def generate_valid_auth_token(user_id: str = "dev-id-123", handle: str = "Anon#123456", phone: str = "+919876543210") -> str:
    now = int(time.time())
    payload = {
        "sub": user_id,
        "phone": phone,
        "handle": handle,
        "type": "access",
        "iss": "nearhood-backend",
        "iat": now,
        "exp": now + 3600
    }
    return jwt.encode(payload, Config.JWT_SECRET, algorithm="HS256")

def generate_tampered_token(user_id: str = "dev-id-123", handle: str = "Anon#123456") -> str:
    now = int(time.time())
    payload = {
        "sub": user_id,
        "handle": handle,
        "type": "access",
        "iss": "nearhood-backend",
        "iat": now,
        "exp": now + 3600
    }
    return jwt.encode(payload, "tampered_signature_secret_key_1234567890", algorithm="HS256")

def generate_expired_token(user_id: str = "dev-id-123", handle: str = "Anon#123456") -> str:
    now = int(time.time()) - 500
    payload = {
        "sub": user_id,
        "handle": handle,
        "type": "access",
        "iss": "nearhood-backend",
        "iat": now - 3600,
        "exp": now
    }
    return jwt.encode(payload, Config.JWT_SECRET, algorithm="HS256")

def test_missing_token():
    response = client.post("/api/v1/posts/create", json={
        "content": "Hello Vadodara",
        "cityId": "GJ-BDQ",
        "areaId": "GJ-BDQ-ALKAPURI",
        "category": "general"
    })
    assert response.status_code == 401

def test_invalid_token():
    response = client.post(
        "/api/v1/posts/create",
        headers={"Authorization": "Bearer invalid.format.token.here"},
        json={
            "content": "Hello Vadodara",
            "cityId": "GJ-BDQ",
            "areaId": "GJ-BDQ-ALKAPURI",
            "category": "general"
        }
    )
    assert response.status_code == 401

def test_tampered_token():
    tampered = generate_tampered_token("dev-id-123", "Anon#123456")
    response = client.post(
        "/api/v1/posts/create",
        headers={"Authorization": f"Bearer {tampered}"},
        json={
            "content": "Hello Vadodara",
            "cityId": "GJ-BDQ",
            "areaId": "GJ-BDQ-ALKAPURI",
            "category": "general"
        }
    )
    assert response.status_code == 401

def test_expired_token():
    expired = generate_expired_token("dev-id-123", "Anon#123456")
    response = client.post(
        "/api/v1/posts/create",
        headers={"Authorization": f"Bearer {expired}"},
        json={
            "content": "Hello Vadodara",
            "cityId": "GJ-BDQ",
            "areaId": "GJ-BDQ-ALKAPURI",
            "category": "general"
        }
    )
    assert response.status_code == 401

def test_oversized_post_payload():
    valid_token = generate_valid_auth_token("dev-id-123", "Anon#123456")
    oversized_content = "A" * 5001
    response = client.post(
        "/api/v1/posts/create",
        headers={"Authorization": f"Bearer {valid_token}"},
        json={
            "content": oversized_content,
            "cityId": "GJ-BDQ",
            "areaId": "GJ-BDQ-ALKAPURI",
            "category": "general"
        }
    )
    # Invalid size fails validation, returns 400 Bad Request
    assert response.status_code == 400

def test_invalid_area_category_enums():
    valid_token = generate_valid_auth_token("dev-id-123", "Anon#123456")
    response = client.post(
        "/api/v1/posts/create",
        headers={"Authorization": f"Bearer {valid_token}"},
        json={
            "content": "Hello Vadodara",
            "cityId": "GJ-BDQ",
            "category": "invalid_nonexistent_category"
        }
    )
    assert response.status_code == 422 or response.status_code == 400

def test_idempotency_key_replay():
    valid_token = generate_valid_auth_token("dev-id-123", "Anon#123456")
    headers = {
        "Authorization": f"Bearer {valid_token}",
        "Idempotency-Key": "test-unique-idempotency-key-uuid-999"
    }
    payload = {
        "content": "Testing request replay protection features",
        "cityId": "GJ-BDQ",
        "areaId": "GJ-BDQ-ALKAPURI",
        "category": "general"
    }
    response1 = client.post("/api/v1/posts/create", headers=headers, json=payload)
    response2 = client.post("/api/v1/posts/create", headers=headers, json=payload)
    
    # Second request must match the response of the first request (bypass execution)
    assert response1.status_code == response2.status_code

def test_moderator_privilege_escalation():
    # Simple moderator token
    mod_token = generate_mod_session_token("mod@vadodara.local", "moderator")
    
    # Try to ban a user (requires 'admin' role)
    response = client.post(
        "/api/v1/moderation/ban",
        headers={"x-moderator-token": mod_token},
        json={
            "targetHandle": "Anon#HACKER",
            "reason": "Privilege escalation test"
        }
    )
    assert response.status_code == 403
