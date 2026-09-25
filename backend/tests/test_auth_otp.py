import pytest
import time
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from main import app
from routes.auth import _otp_requests, _phone_send_rl, _ip_send_rl
from services.wakit_service import WakitService
from config import Config

client = TestClient(app)

@pytest.fixture(autouse=True)
def clean_state():
    _otp_requests.clear()
    _phone_send_rl.clear()
    _ip_send_rl.clear()
    Config.WAKIT_API_KEY = "test_live_api_key_valid"
    yield
    _otp_requests.clear()
    _phone_send_rl.clear()
    _ip_send_rl.clear()

def _get_err_message(res) -> str:
    body = res.json()
    if "detail" in body:
        return str(body["detail"])
    if "error" in body and "message" in body["error"]:
        return str(body["error"]["message"])
    return str(body)

def test_send_otp_invalid_phone():
    res = client.post("/auth/otp/send", json={"phone_number": "12345"})
    assert res.status_code == 400
    assert "Invalid phone number format" in _get_err_message(res)

@patch.object(WakitService, "send_otp")
def test_send_otp_success_and_rate_limit(mock_send):
    mock_send.return_value = {
        "request_id": "wakit_live_req_1001",
        "expires_in": 300,
        "status": "success",
    }
    phone = "+919876543210"
    
    # 1st request
    res1 = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res1.status_code == 200
    data1 = res1.json()
    assert data1["request_id"] == "wakit_live_req_1001"
    assert data1["status"] == "success"

    # 2nd, 3rd, 4th, 5th request
    for _ in range(4):
        res = client.post("/auth/otp/send", json={"phone_number": phone})
        assert res.status_code == 200

    # 6th request -> Rate limited (max 5 per window)
    res6 = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res6.status_code == 429
    assert "Too many OTP requests" in _get_err_message(res6)

@patch.object(WakitService, "verify_otp")
@patch.object(WakitService, "send_otp")
def test_verify_otp_flow_and_lockout(mock_send, mock_verify):
    mock_send.return_value = {
        "request_id": "wakit_req_lockout_test",
        "expires_in": 300,
        "status": "success",
    }
    mock_verify.return_value = False

    phone = "+919123456780"
    res_send = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res_send.status_code == 200
    request_id = res_send.json()["request_id"]

    # Wrong code attempt 1
    res_v1 = client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "999999"})
    assert res_v1.status_code == 400
    assert "4 attempt(s) remaining" in _get_err_message(res_v1)

    # Wrong code attempts 2, 3, 4, 5
    for _ in range(4):
        client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "999999"})

    # 6th attempt -> lockout
    res_lockout = client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "999999"})
    assert res_lockout.status_code == 429
    assert "locked" in _get_err_message(res_lockout).lower()

@patch.object(WakitService, "verify_otp")
@patch.object(WakitService, "send_otp")
def test_verify_otp_success_and_replay_prevention(mock_send, mock_verify):
    mock_send.return_value = {
        "request_id": "wakit_req_success_1002",
        "expires_in": 300,
        "status": "success",
    }
    mock_verify.side_effect = lambda req_id, otp, phone_number=None: otp == "847291"

    phone = "+919988776655"
    res_send = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res_send.status_code == 200
    request_id = res_send.json()["request_id"]

    # Valid real OTP
    res_verify = client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "847291"})
    assert res_verify.status_code == 200
    data = res_verify.json()
    assert data["status"] == "success"
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["user"]["phoneNumber"] == phone

    # Idempotent retry support: Same request_id returns the active cached session response
    res_replay = client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "847291"})
    assert res_replay.status_code == 200
    assert res_replay.json()["access_token"] == data["access_token"]

@patch.object(WakitService, "verify_otp")
@patch.object(WakitService, "send_otp")
def test_refresh_token_endpoint(mock_send, mock_verify):
    mock_send.return_value = {
        "request_id": "wakit_req_refresh_1003",
        "expires_in": 300,
        "status": "success",
    }
    mock_verify.return_value = True

    phone = "+919988112233"
    res_send = client.post("/auth/otp/send", json={"phone_number": phone})
    request_id = res_send.json()["request_id"]

    res_verify = client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "654321"})
    refresh_token = res_verify.json()["refresh_token"]

    res_refresh = client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert res_refresh.status_code == 200
    refresh_data = res_refresh.json()
    assert "access_token" in refresh_data
    assert "refresh_token" in refresh_data
