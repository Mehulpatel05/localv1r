import pytest
import time
from fastapi.testclient import TestClient
from main import app
from routes.auth import _otp_requests, _phone_send_rl, _ip_send_rl

client = TestClient(app)

@pytest.fixture(autouse=True)
def clean_state():
    from config import Config
    original_key = Config.WAKIT_API_KEY
    Config.WAKIT_API_KEY = ""
    _otp_requests.clear()
    _phone_send_rl.clear()
    _ip_send_rl.clear()
    yield
    Config.WAKIT_API_KEY = original_key

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

def test_send_otp_success_and_rate_limit():
    phone = "+919876543210"
    
    # 1st request
    res1 = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res1.status_code == 200
    data1 = res1.json()
    assert "request_id" in data1
    assert data1["status"] == "success"

    # 2nd request
    res2 = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res2.status_code == 200

    # 3rd request
    res3 = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res3.status_code == 200

    # 4th request
    res4 = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res4.status_code == 200

    # 5th request
    res5 = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res5.status_code == 200

    # 6th request -> Rate limited (max 5 per window)
    res6 = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res6.status_code == 429
    assert "Too many OTP requests" in _get_err_message(res6)

def test_verify_otp_flow_and_lockout():
    phone = "+919123456780"
    res_send = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res_send.status_code == 200
    request_id = res_send.json()["request_id"]

    # Wrong code attempt 1
    res_v1 = client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "000000"})
    assert res_v1.status_code == 400
    assert "4 attempt(s) remaining" in _get_err_message(res_v1)

    # Wrong code attempt 2, 3, 4, 5
    for _ in range(4):
        client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "000000"})

    # 6th attempt -> lockout
    res_lockout = client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "000000"})
    assert res_lockout.status_code == 429
    assert "locked" in _get_err_message(res_lockout).lower()

def test_verify_otp_success_and_replay_prevention():
    phone = "+919988776655"
    res_send = client.post("/auth/otp/send", json={"phone_number": phone})
    assert res_send.status_code == 200
    request_id = res_send.json()["request_id"]

    # In test mode without WAKIT_API_KEY, "123456" is accepted
    res_verify = client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "123456"})
    assert res_verify.status_code == 200
    data = res_verify.json()
    assert data["status"] == "success"
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["user"]["phoneNumber"] == phone

    # Replay attack prevention: Same request_id cannot be reused
    res_replay = client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "123456"})
    assert res_replay.status_code == 400
    assert "already been verified" in _get_err_message(res_replay)

def test_refresh_token_endpoint():
    phone = "+919988112233"
    res_send = client.post("/auth/otp/send", json={"phone_number": phone})
    request_id = res_send.json()["request_id"]

    res_verify = client.post("/auth/otp/verify", json={"request_id": request_id, "otp": "123456"})
    refresh_token = res_verify.json()["refresh_token"]

    res_refresh = client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert res_refresh.status_code == 200
    refresh_data = res_refresh.json()
    assert "access_token" in refresh_data
    assert "refresh_token" in refresh_data
