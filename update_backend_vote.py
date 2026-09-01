import re

with open('backend/main.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Update VoteRequest
content = content.replace(
    'class VoteRequest(BaseModel):\n    direction: Literal[1, -1] = Field(..., description="1 for upvote, -1 for downvote")',
    'class VoteRequest(BaseModel):\n    direction: Literal[1, -1] = Field(..., description="1 for upvote, -1 for downvote")\n    attestationToken: Optional[str] = None\n    requestId: Optional[str] = None'
)

# Update vote_post endpoint
replacement_vote = '''
    device_id, user_handle = verify_session_token(authorization)
    enforce_route_rate_limit("vote", device_id, max_requests=60)

    # Verify Play Integrity Hash
    if request.attestationToken and request.requestId:
        import hashlib
        raw_hash_str = f"POST/api/v1/posts/{post_id}/vote{request.direction}{request.requestId}"
        expected_hash = hashlib.sha256(raw_hash_str.encode()).hexdigest()
        if not verify_device_attestation(expected_hash, request.attestationToken):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Device attestation validation failed.")
'''

content = re.sub(
    r'device_id, user_handle = verify_session_token\(authorization\)\s*enforce_route_rate_limit\("vote", device_id, max_requests=60\)',
    replacement_vote.strip(),
    content
)

with open('backend/main.py', 'w', encoding='utf-8') as f:
    f.write(content)
