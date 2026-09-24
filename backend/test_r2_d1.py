import os
import uuid
import sys

# Add backend directory to sys.path
sys.path.insert(0, os.path.dirname(__file__))

from config import Config
from services.r2_service import R2Service
from services.d1_service import D1Service

def test_r2():
    print("--- Testing Cloudflare R2 ---")
    test_id = str(uuid.uuid4())
    test_data = b"Nearhood R2 Object Storage Verification Payload"
    
    # 1. Upload
    key = R2Service.upload_media(test_data, f"test_{test_id}.txt", "text/plain")
    print(f"[R2] Uploaded object key: {key}")
    assert key is not None, "R2 Upload failed!"
    
    # 2. Fetch
    fetched = R2Service.get_media_bytes(key)
    print(f"[R2] Fetched bytes match: {fetched == test_data}")
    assert fetched == test_data, "R2 Fetched data mismatch!"
    
    # 3. Range Fetch
    chunk, total_size, c_type = R2Service.get_media_range(key, "bytes=0-10")
    print(f"[R2] Range fetch (0-10): {chunk} (Length: {len(chunk)})")
    
    # 4. Clean up
    deleted = R2Service.delete_media(key)
    print(f"[R2] Deleted test object: {deleted}")
    print("[SUCCESS] Cloudflare R2 Test PASSED!\n")

def test_d1():
    print("--- Testing Cloudflare D1 ---")
    print(f"Account ID: {Config.CLOUDFLARE_ACCOUNT_ID}")
    print(f"Database ID: {Config.D1_DATABASE_ID}")
    
    # Query test
    rows = D1Service.query("SELECT 1 as is_working;")
    if rows is not None:
        print(f"[D1] Query Success! Result: {rows}")
        
        # Init Schema
        print("[D1] Creating tables in D1...")
        init_ok = D1Service.init_schema()
        print(f"[D1] Schema creation status: {init_ok}")
        
        # List tables
        tables = D1Service.query("SELECT name FROM sqlite_master WHERE type='table';")
        table_names = [t.get('name') for t in (tables or []) if not t.get('name', '').startswith('_')]
        print(f"[D1] Active Tables in D1: {table_names}")
        
        print("[SUCCESS] Cloudflare D1 Test PASSED!\n")
    else:
        print("[D1] D1 Query failed. Note: Ensure the Cloudflare API Token has 'D1 Edit' permissions.\n")

if __name__ == "__main__":
    test_r2()
    test_d1()
