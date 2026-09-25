import os
import uuid
import time
import requests
from typing import Dict, Any, Optional
from config import Config

class WakitService:
    """
    Production adapter service for Wakit WhatsApp/SMS OTP Gateway.
    Directly interfaces with https://wakit.in/api/v1.
    Protects secrets: NEVER logs API keys or OTP codes in plain text.
    """

    @classmethod
    def _get_client_session(cls) -> requests.Session:
        session = requests.Session()
        session.headers.update({
            "User-Agent": "NearhoodBackend/2.0 (Android/iOS OTP Service)",
            "Accept": "application/json",
            "Content-Type": "application/json",
        })
        return session

    @classmethod
    def send_otp(cls, phone_number: str) -> Dict[str, Any]:
        """
        Sends a 6-digit OTP code to the given E.164 phone number via Wakit.
        Returns a dict containing request_id, expires_in (seconds), and status.
        Raises an exception if the API key is missing or provider delivery fails.
        """
        api_key = Config.WAKIT_API_KEY.strip()
        base_url = Config.WAKIT_BASE_URL.rstrip('/')

        if not api_key:
            raise RuntimeError(
                "WAKIT_API_KEY is not configured in backend environment (.env). "
                "Please set a valid Wakit API key for real OTP delivery."
            )

        url = f"{base_url}/otp/send"
        headers = {
            "Authorization": f"Bearer {api_key}",
        }
        payload = {
            "to": phone_number,
            "phone_number": phone_number,
            "code_length": 6,
            "expiry_seconds": 300,
        }

        # (connect_timeout, read_timeout)
        timeout_config = (5, Config.WAKIT_TIMEOUT_SECONDS)
        max_retries = max(1, Config.WAKIT_MAX_RETRIES)
        last_error = None

        session = cls._get_client_session()
        try:
            for attempt in range(1, max_retries + 1):
                try:
                    response = session.post(url, json=payload, headers=headers, timeout=timeout_config)
                    
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
                        resp_text = response.text[:300] if response.text else ""
                        print(f"[WakitService] Send error: HTTP {response.status_code} - {resp_text}")
                        last_error = f"Gateway returned HTTP {response.status_code}: {resp_text}"
                        
                        # Don't retry on client errors (400, 401, 403, 422)
                        if 400 <= response.status_code < 500:
                            break

                except requests.exceptions.Timeout as e:
                    last_error = f"Gateway connection timed out after {timeout_config[1]}s: {e}"
                    print(f"[WakitService] Timeout on attempt {attempt}/{max_retries} contacting OTP gateway: {e}")
                    if attempt < max_retries:
                        time.sleep(1.0 * attempt)
                except requests.RequestException as e:
                    last_error = f"Network exception contacting gateway: {e}"
                    print(f"[WakitService] Network error on attempt {attempt}/{max_retries}: {e}")
                    if attempt < max_retries:
                        time.sleep(1.0 * attempt)

        finally:
            session.close()

        raise RuntimeError(f"Unable to send OTP via Wakit gateway: {last_error}")

    @classmethod
    def verify_otp(cls, request_id: str, otp: str, phone_number: Optional[str] = None) -> bool:
        """
        Verifies the user-submitted OTP for a given request_id and phone number with Wakit.
        Returns True if valid, False otherwise.
        Raises an exception if the API key is missing.
        """
        api_key = Config.WAKIT_API_KEY.strip()
        base_url = Config.WAKIT_BASE_URL.rstrip('/')

        if not api_key:
            raise RuntimeError(
                "WAKIT_API_KEY is not configured in backend environment (.env). "
                "Please set a valid Wakit API key for real OTP verification."
            )

        url = f"{base_url}/otp/verify"
        headers = {
            "Authorization": f"Bearer {api_key}",
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

        session = cls._get_client_session()
        try:
            for attempt in range(1, max_retries + 1):
                try:
                    response = session.post(url, json=payload, headers=headers, timeout=timeout_config)
                    
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
                        # Invalid code or session
                        return False
                    else:
                        print(f"[WakitService] HTTP {response.status_code} during OTP verification: {response.text[:300]}")
                        return False
                        
                except requests.exceptions.Timeout as e:
                    print(f"[WakitService] Timeout on attempt {attempt}/{max_retries} during OTP verify: {e}")
                    if attempt < max_retries:
                        time.sleep(1.0 * attempt)
                except requests.RequestException as e:
                    print(f"[WakitService] Network error on attempt {attempt}/{max_retries} during OTP verify: {e}")
                    if attempt < max_retries:
                        time.sleep(1.0 * attempt)

        finally:
            session.close()

        return False
