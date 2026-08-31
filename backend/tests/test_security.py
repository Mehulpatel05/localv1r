import pytest
import time
import hmac
import hashlib
from fastapi.testclient import TestClient
import sys
import os

# Include parent directory in python path to import main
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from main import app, generate_session_token, generate_mod_session_token
from config import Config

client = TestClient(app)

# Helper to generate tampered token
def generate_tampered_token(installation_id, handle):
    expires_at = int(time.time()) + 604800
    message = f"access:{installation_id}:{handle}:{expires_at}".encode()
    signature = hmac.new(b"tampered_signature_secret_key", message, hashlib.sha256).hexdigest()
    return f"{installation_id}.{handle}.{expires_at}.{signature}"

def test_missing_token():
    response = client.post("/api/v1/posts/create", json={
        "content": "Hello Vadodara",
        "area": "alkapuri",
        "category": "general"
    })
    assert response.status_code == 401

def test_invalid_token():
    response = client.post("/api/v1/posts/create", headers={"x-session-token": "invalid.format.token.here"}, json={
        "content": "Hello Vadodara",
        "area": "alkapuri",
        "category": "general"
    })
    assert response.status_code == 401

def test_tampered_token():
    tampered = generate_tampered_token("dev-id-123", "Anon#123456")
    response = client.post("/api/v1/posts/create", headers={"x-session-token": tampered}, json={
        "content": "Hello Vadodara",
        "area": "alkapuri",
        "category": "general"
    })
    assert response.status_code == 401

def test_expired_token():
    expires_at = int(time.time()) - 100
    message = f"access:dev-id-123:Anon#123456:{expires_at}".encode()
    signature = hmac.new(Config.JWT_SECRET.encode(), message, hashlib.sha256).hexdigest()
    expired = f"dev-id-123.Anon#123456.{expires_at}.{signature}"
    
    response = client.post("/api/v1/posts/create", headers={"x-session-token": expired}, json={
        "content": "Hello Vadodara",
        "area": "alkapuri",
        "category": "general"
    })
    assert response.status_code == 401

def test_oversized_post_payload():
    valid_token = generate_session_token("dev-id-123", "Anon#123456")
    oversized_content = "A" * 5001
    response = client.post("/api/v1/posts/create", headers={"x-session-token": valid_token}, json={
        "content": oversized_content,
        "area": "alkapuri",
        "category": "general"
    })
    # Invalid size fails validation, returns 400 Bad Request
    assert response.status_code == 400

def test_invalid_area_category_enums():
    valid_token = generate_session_token("dev-id-123", "Anon#123456")
    response = client.post("/api/v1/posts/create", headers={"x-session-token": valid_token}, json={
        "content": "Hello Vadodara",
        "area": "invalid_neighborhood",
        "category": "general"
    })
    assert response.status_code == 400

def test_idempotency_key_replay():
    valid_token = generate_session_token("dev-id-123", "Anon#123456")
    headers = {
        "x-session-token": valid_token,
        "Idempotency-Key": "test-unique-idempotency-key-uuid-999"
    }
    payload = {
        "content": "Testing request replay protection features",
        "area": "alkapuri",
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
    response = client.post("/api/v1/moderation/ban", headers={"x-moderator-token": mod_token}, json={
        "targetHandle": "Anon#HACKER",
        "reason": "Privilege escalation test"
    })
    assert response.status_code == 403
