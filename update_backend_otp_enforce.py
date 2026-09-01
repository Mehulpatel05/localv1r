import re

with open('backend/main.py', 'r', encoding='utf-8') as f:
    content = f.read()

replacement = '''
    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("post", device_id, max_requests=5)

    if db is not None:
        device_doc = db.collection("devices").document(device_id).get()
        if device_doc.exists:
            device_data = device_doc.to_dict()
            if not device_data.get("otpVerified"):
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="OTP_REQUIRED: Phone authentication is required to create a post.")
            
            # FUTURE: GPS/IP location check can be enforced here independently of OTP
            # if not is_in_vadodara(ip_addr, gps_coords): raise location_error

    error_msg = validate_text_content(request.content)
'''

content = re.sub(
    r'device_id, user_handle = verify_session_token\(authorization\)\s*enforce_route_rate_limit\("post", device_id, max_requests=5\)\s*error_msg = validate_text_content\(request.content\)',
    replacement.strip() + '\n\n    error_msg = validate_text_content(request.content)',
    content
)

with open('backend/main.py', 'w', encoding='utf-8') as f:
    f.write(content)
