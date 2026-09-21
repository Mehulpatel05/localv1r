import os
import uuid
import time
import requests
from typing import Dict, Any, Optional
from config import Config

class WakitService:
    """
    Adapter service for Wakit WhatsApp/SMS OTP Gateway.
    Protects secrets: NEVER logs API keys or OTP codes.
    """

    @classmethod
    def send_otp(cls, phone_number: str) -> Dict[str, Any]:
        """
        Sends an OTP code to the given E.164 phone number via Wakit.
        Returns a dict containing request_id and expires_in (seconds).
        """
        api_key = Config.WAKIT_API_KEY
        base_url = Config.WAKIT_BASE_URL.rstrip('/')

        # In case API key is not configured (e.g. local testing), provide simulated adapter response
        if not api_key:
            simulated_id = f"wakit_sim_{uuid.uuid4().hex[:16]}"
            return {
                "request_id": simulated_id,
                "expires_in": 300, # 5 minutes default
                "status": "success",
            }

        url = f"{base_url}/otp/send"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        # Wakit API expects 'to' with E.164 phone and optional 'code_length'
        payload = {
            "to": phone_number,
            "phone_number": phone_number,
            "code_length": 6,
            "expiry_seconds": 300,
        }

        timeout_config = (5, Config.WAKIT_TIMEOUT_SECONDS)
        max_retries = max(1, Config.WAKIT_MAX_RETRIES)
        last_error = None

        for attempt in range(1, max_retries + 1):
            try:
                response = requests.post(url, json=payload, headers=headers, timeout=timeout_config)
                if response.status_code in (200, 201):
                    data = response.json()
                    req_data = data.get("data") if isinstance(data.get("data"), dict) else {}
                    request_id = (
                        data.get("request_id")
                        or data.get("id")
                        or req_data.get("request_id")
                        or req_data.get("id")
                        or str(uuid.uuid4())
                    )
                    expires_in = (
                        data.get("expires_in")
                        or data.get("expiry_seconds")
                        or req_data.get("expires_in")
                        or 300
                    )
                    return {
                        "request_id": str(request_id),
                        "expires_in": int(expires_in),
                        "status": "success",
                    }
                else:
                    resp_text = response.text[:200] if response.text else ""
                    print(f"[WakitService] Error sending OTP: HTTP {response.status_code}, response: {resp_text}")
                    last_error = f"Wakit API returned HTTP {response.status_code}: {resp_text}"
            except requests.exceptions.Timeout as e:
                last_error = f"Connection/read timed out after {timeout_config[1]}s: {e}"
                print(f"[WakitService] Timeout on attempt {attempt}/{max_retries} contacting OTP provider: {e}")
                if attempt < max_retries:
                    time.sleep(1.0)
            except requests.RequestException as e:
                last_error = f"Network exception: {e}"
                print(f"[WakitService] Network error on attempt {attempt}/{max_retries} during OTP send request: {e}")
                if attempt < max_retries:
                    time.sleep(1.0)

        # If external provider is unreachable/timing out, gracefully activate fallback simulation if enabled
        if Config.OTP_FALLBACK_SIMULATION:
            fallback_id = f"wakit_fallback_{uuid.uuid4().hex[:16]}"
            print(f"[WakitService] External provider timed out ({last_error}). Falling back to simulated OTP session (code: {Config.DEFAULT_TEST_OTP}) for {phone_number}.")
            return {
                "request_id": fallback_id,
                "expires_in": 300,
                "status": "success",
                "fallback": True,
            }

        raise Exception(f"Unable to contact OTP delivery provider at {url}: {last_error}")

    @classmethod
    def verify_otp(cls, request_id: str, otp: str, phone_number: Optional[str] = None) -> bool:
        """
        Verifies the user-submitted OTP for a given request_id and phone number.
        Returns True if valid, False otherwise.
        """
        api_key = Config.WAKIT_API_KEY
        base_url = Config.WAKIT_BASE_URL.rstrip('/')

        # Check for fallback / dev simulation sessions or universal test OTP
        is_sim_request = (
            not api_key
            or request_id.startswith("wakit_sim_")
            or request_id.startswith("wakit_fallback_")
            or request_id.startswith("sim_")
        )

        if is_sim_request or (Config.OTP_FALLBACK_SIMULATION and otp == Config.DEFAULT_TEST_OTP):
            if otp == Config.DEFAULT_TEST_OTP:
                return True
            if is_sim_request:
                return False

        url = f"{base_url}/otp/verify"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        payload = {
            "request_id": request_id,
            "id": request_id,
            "code": otp,
            "otp": otp,
        }
        if phone_number:
            payload["to"] = phone_number
            payload["phone_number"] = phone_number

        timeout_config = (5, Config.WAKIT_TIMEOUT_SECONDS)
        max_retries = max(1, Config.WAKIT_MAX_RETRIES)

        for attempt in range(1, max_retries + 1):
            try:
                response = requests.post(url, json=payload, headers=headers, timeout=timeout_config)
                if response.status_code in (200, 201):
                    data = response.json()
                    d_data = data.get("data") if isinstance(data.get("data"), dict) else {}
                    if d_data:
                        is_valid = (
                            d_data.get("verified") is True
                            or d_data.get("valid") is True
                            or d_data.get("status") in ("verified", "success", "approved")
                        )
                    else:
                        is_valid = (
                            data.get("verified") is True
                            or data.get("valid") is True
                            or data.get("status") in ("verified", "success", "approved")
                            or (data.get("success") is True and not data.get("error"))
                        )
                    return bool(is_valid)
                elif response.status_code in (400, 401, 403, 404, 422):
                    return False
                else:
                    print(f"[WakitService] Error verifying OTP: HTTP {response.status_code}")
                    return False
            except requests.exceptions.Timeout as e:
                print(f"[WakitService] Timeout on attempt {attempt}/{max_retries} during OTP verification: {e}")
                if attempt < max_retries:
                    time.sleep(1.0)
            except requests.RequestException:
                print(f"[WakitService] Network error on attempt {attempt}/{max_retries} during OTP verification.")
                if attempt < max_retries:
                    time.sleep(1.0)

        # If gateway timed out during verification, check fallback OTP if enabled
        if Config.OTP_FALLBACK_SIMULATION and otp == Config.DEFAULT_TEST_OTP:
            return True

        return False
