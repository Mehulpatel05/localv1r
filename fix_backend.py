import re

with open('backend/main.py', 'r', encoding='utf-8') as f:
    content = f.read()

new_auth_code = '''
import secrets

def generate_session_token(installation_id: str, handle: str) -> str:
    auth_token = secrets.token_hex(32)
    token_hash = hashlib.sha256(auth_token.encode()).hexdigest()
    
    if db is not None:
        db.collection("devices").document(installation_id).set({
            "installationId": installation_id,
            "tokenHash": token_hash,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "lastSeenAt": firestore.SERVER_TIMESTAMP,
            "revokedAt": None
        })
    return auth_token

def generate_refresh_token(installation_id: str, handle: str) -> str:
    return "deprecated"

def verify_session_token(authorization: Optional[str]) -> Tuple[str, str]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing or invalid Authorization header.")
    
    auth_token = authorization.split("Bearer ")[1].strip()
    token_hash = hashlib.sha256(auth_token.encode()).hexdigest()
    
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        docs = db.collection("devices").where("tokenHash", "==", token_hash).limit(1).get()
        if not docs:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session token.")
            
        device_doc = docs[0].to_dict()
        if device_doc.get("revokedAt") is not None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session revoked.")
            
        installation_id = device_doc.get("installationId")
        handle = generate_server_handle(installation_id)
        
        banned_ref = db.collection("banned_users").document(handle).get()
        if banned_ref.exists:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This account has been suspended for safety policy violations.")
            
        return installation_id, handle
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session token.")
'''

# Find the def generate_session_token block and replace it up to # 🛡️ DEVICE INTEGRITY ATTESTATION VALIDATION
content = re.sub(
    r'def generate_session_token\(installation_id: str, handle: str\) -> str:.*?# 🛡️ DEVICE INTEGRITY ATTESTATION VALIDATION',
    new_auth_code.strip() + '\n\n# 🛡️ DEVICE INTEGRITY ATTESTATION VALIDATION',
    content,
    flags=re.DOTALL
)

# x_session_token -> authorization
content = re.sub(
    r'x_session_token:\s*Optional\[str\]\s*=\s*Header\([^)]*\)',
    r'authorization: Optional[str] = Header(None, description="Bearer token")',
    content
)

# verify_session_token(x_session_token) -> verify_session_token(authorization)
content = content.replace('verify_session_token(x_session_token)', 'verify_session_token(authorization)')

# We need to make sure `firestore` is imported, wait, it is already imported:
# from google.cloud import firestore

with open('backend/main.py', 'w', encoding='utf-8') as f:
    f.write(content)
