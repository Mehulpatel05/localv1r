import re

with open('backend/main.py', 'r', encoding='utf-8') as f:
    content = f.read()

new_attestation = '''
# 🛡️ DEVICE INTEGRITY ATTESTATION VALIDATION (Play Integrity)
def verify_device_attestation(request_hash: str, attestation_token: str) -> bool:
    if not attestation_token:
        return False
        
    if attestation_token.startswith("simulated_attestation_"):
        parts = attestation_token.split("_")
        # simulated_attestation_com.example.localv1_<requestHash>
        if len(parts) >= 3:
            package_name = parts[2]
            return package_name == "com.example.localv1"
        return False
        
    # In production, verify with Google Play Integrity API
    # POST https://playintegrity.googleapis.com/v1/com.example.localv1:decodeIntegrityToken
    # { "integrity_token": attestation_token }
    # Using Google Auth credentials
    
    try:
        import google.auth
        from google.auth.transport.requests import Request as GoogleAuthRequest
        
        credentials, project_id = google.auth.default(scopes=['https://www.googleapis.com/auth/playintegrity'])
        auth_req = GoogleAuthRequest()
        credentials.refresh(auth_req)
        
        url = f"https://playintegrity.googleapis.com/v1/com.example.localv1:decodeIntegrityToken"
        headers = {
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json"
        }
        data = {
            "integrity_token": attestation_token
        }
        
        import requests
        response = requests.post(url, headers=headers, json=data, timeout=10)
        
        if response.status_code == 200:
            result = response.json()
            token_payload_external = result.get("tokenPayloadExternal", {})
            request_details = token_payload_external.get("requestDetails", {})
            
            # Verify request hash
            if request_details.get("requestHash") != request_hash:
                print("Integrity Error: Request hash mismatch")
                return False
                
            # Verify app recognition
            app_verdict = token_payload_external.get("appIntegrity", {}).get("appRecognitionVerdict")
            if app_verdict != "PLAY_RECOGNIZED":
                print(f"Integrity Error: App not recognized ({app_verdict})")
                return False
                
            # Verify device recognition
            device_verdict = token_payload_external.get("deviceIntegrity", {}).get("deviceRecognitionVerdict")
            if not device_verdict or "MEETS_DEVICE_INTEGRITY" not in device_verdict:
                print(f"Integrity Error: Device integrity failed ({device_verdict})")
                return False
                
            return True
        else:
            print(f"Integrity API Error: {response.status_code} {response.text}")
            return False
    except Exception as e:
        print(f"Play Integrity Verification failed: {e}")
        # Fallback for development if needed, but return False in prod
        return False
'''

content = re.sub(
    r'# 🛡️ DEVICE INTEGRITY ATTESTATION VALIDATION.*?(?=# 🛡️ MODERATOR ROLE PRIVILEGES HIERARCHY)',
    new_attestation.strip() + '\n\n',
    content,
    flags=re.DOTALL
)

# Update register_device call
content = content.replace(
    'if not verify_device_attestation(request.installationId, request.attestationToken):',
    '''
    import hashlib
    # Reconstruct request hash
    raw_hash_str = f"POST/api/v1/devices/register{request.installationId}"
    expected_hash = hashlib.sha256(raw_hash_str.encode()).hexdigest()
    if not verify_device_attestation(expected_hash, request.attestationToken):
    '''
)

with open('backend/main.py', 'w', encoding='utf-8') as f:
    f.write(content)
