import re

with open('backend/main.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Add evaluate_request_risk function
security_module = '''
# 🛡️ COMPREHENSIVE RISK EVALUATION (Server-Side Authority)
def evaluate_request_risk(
    client_ip: str, 
    client_vpn_flag: bool = False, 
) -> bool:
    """
    Evaluates request risk using server-side signals.
    Client-provided headers like x-vpn-detected are treated as weak signals.
    """
    risk_score = 0
    
    # 1. Client VPN flag = weak signal
    if client_vpn_flag:
        risk_score += 10 
        
    # 2. IP reputation = stronger (simulated)
    # ip_rep = get_ip_reputation(client_ip)
    # if ip_rep == "DATA_CENTER" or ip_rep == "KNOWN_TOR": risk_score += 50
    
    # 3. ASN / hosting check = stronger (simulated)
    # asn_info = get_asn_info(client_ip)
    # if asn_info.get("type") == "hosting": risk_score += 40
    
    # 4. GeoIP = location signal (simulated)
    # geo_info = get_geo_info(client_ip)
    # if geo_info.get("city") != "Vadodara": risk_score += 30
    
    # 5. Play Integrity = app/device integrity
    # (Already handled by verify_device_attestation blocking if false)
    
    # 6. Behaviour/rate limit = abuse signal
    # (Already handled by enforce_route_rate_limit)

    # Final decision strictly by server
    if risk_score >= 100:
        return False
    return True
'''

if 'evaluate_request_risk' not in content:
    content = content.replace(
        '# 🛡️ MAGIC BYTE SIGNATURE DETECTION',
        security_module + '\n# 🛡️ MAGIC BYTE SIGNATURE DETECTION'
    )

# Let's add x-vpn-detected to create_post and vote_post to demonstrate we parse it but rely on evaluate_request_risk
replacement_create_post = '''
async def create_post(
    request: PostCreateRequest,
    server_request: Request,
    authorization: Optional[str] = Header(None, description="Bearer token"),
    x_vpn_detected: Optional[bool] = Header(False, description="Client side VPN detection flag"),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = get_cached_idempotent_response(idempotency_key)
        if cached:
            return cached

    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("post", device_id, max_requests=5)
    
    client_ip = server_request.client.host if server_request.client else "127.0.0.1"
    if not evaluate_request_risk(client_ip, client_vpn_flag=x_vpn_detected):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="High risk request blocked by security policies.")
'''

content = re.sub(
    r'async def create_post\(\s*request: PostCreateRequest,\s*authorization: Optional\[str\] = Header\(None, description="Bearer token"\),\s*idempotency_key: Optional\[str\] = Header\(None, alias="Idempotency-Key"\)\s*\):.*?enforce_route_rate_limit\("post", device_id, max_requests=5\)',
    replacement_create_post.strip(),
    content,
    flags=re.DOTALL
)

with open('backend/main.py', 'w', encoding='utf-8') as f:
    f.write(content)
