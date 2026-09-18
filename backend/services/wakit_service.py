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
        payload = {
            "phone_number": phone_number,
            "expiry_seconds": 300,
        }

        try:
            response = requests.post(url, json=payload, headers=headers, timeout=10)
            if response.status_code in (200, 201):
                data = response.json()
                request_id = data.get("request_id") or data.get("id") or str(uuid.uuid4())
                expires_in = data.get("expires_in") or data.get("expiry_seconds") or 300
                return {
                    "request_id": request_id,
                    "expires_in": int(expires_in),
                    "status": "success",
                }
            else:
                # Do NOT log sensitive payloads
                print(f"[WakitService] Error sending OTP: HTTP {response.status_code}")
                raise Exception(f"Wakit OTP provider returned status {response.status_code}")
        except requests.RequestException as e:
            print("[WakitService] Network error during OTP send request.")
            raise Exception("Unable to contact OTP delivery provider. Please try again.")

    @classmethod
    def verify_otp(cls, request_id: str, otp: str) -> bool:
        """
        Verifies the user-submitted OTP for a given request_id.
        Returns True if valid, False otherwise.
        """
        api_key = Config.WAKIT_API_KEY
        base_url = Config.WAKIT_BASE_URL.rstrip('/')

        # Dev / Simulation mode if WAKIT_API_KEY is not set
        if not api_key:
            # Allow "123456" as universal dev test OTP
            if otp == "123456":
                return True
            return False

        url = f"{base_url}/otp/verify"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        payload = {
            "request_id": request_id,
            "code": otp,
        }

        try:
            response = requests.post(url, json=payload, headers=headers, timeout=10)
            if response.status_code == 200:
                data = response.json()
                # Wakit verification returns valid: true or status: "verified" / "success"
                is_valid = data.get("valid", False) or data.get("status") in ("verified", "success")
                return bool(is_valid)
            elif response.status_code in (400, 401, 404, 422):
                return False
            else:
                print(f"[WakitService] Error verifying OTP: HTTP {response.status_code}")
                return False
        except requests.RequestException:
            print("[WakitService] Network error during OTP verification.")
            return False
