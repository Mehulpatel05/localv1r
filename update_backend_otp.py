import re

with open('backend/main.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Add OtpVerifyRequest
if 'class OtpVerifyRequest(BaseModel):' not in content:
    content = content.replace(
        'class DeviceRegisterRequest(BaseModel):',
        'class OtpVerifyRequest(BaseModel):\n    firebaseIdToken: str = Field(..., min_length=10)\n\nclass DeviceRegisterRequest(BaseModel):'
    )

new_endpoint = '''
# 2.5 Phone Auth OTP Verification (Backend verifies Firebase ID token directly)
@app.post("/api/v1/devices/verify-phone")
async def verify_phone_auth(
    request: OtpVerifyRequest,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("verify_phone", device_id, max_requests=5)

    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")

    try:
        from firebase_admin import auth as firebase_auth
        
        # Verify Firebase ID token via firebase-admin, ensuring server-backed authority
        decoded_token = firebase_auth.verify_id_token(request.firebaseIdToken)
        phone_number = decoded_token.get('phone_number')
        
        if not phone_number:
            raise HTTPException(status_code=400, detail="Token does not contain a phone number.")
            
        import hashlib
        phone_hash = hashlib.sha256(phone_number.encode()).hexdigest()
        
        # Update device doc indicating OTP is verified on server side
        db.collection("devices").document(device_id).update({
            "otpVerified": True,
            "phoneNumberHash": phone_hash,
            "phoneVerifiedAt": firestore.SERVER_TIMESTAMP
        })
        
        res = {"status": "success", "message": "Phone authentication verified by backend."}
        if idempotency_key:
            save_idempotent_response(idempotency_key, res)
        return res
    except Exception as e:
        print(f"Firebase ID token verification failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase ID token. OTP verification failed.")
'''

if 'verify_phone_auth' not in content:
    content = content.replace(
        '# 3. Secure Post Creation',
        new_endpoint.strip() + '\n\n# 3. Secure Post Creation'
    )

with open('backend/main.py', 'w', encoding='utf-8') as f:
    f.write(content)
