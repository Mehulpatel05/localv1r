import os
import uuid
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))

from config import Config
from services.r2_service import R2Service
from services.d1_service import D1Service

def test_full_d1_flow():
    print("--- Testing Complete Cloudflare D1 Flow ---")
    
    # 1. Initialize Schema
    print("[1] Ensuring D1 Schema tables...")
    assert D1Service.init_schema() == True, "Failed to initialize schema"
    
    # 2. User Creation
    test_handle = f"Anon#{uuid.uuid4().hex[:6].upper()}"
    test_phone = f"+9198765{int(time.time()) % 100000:05d}"
    print(f"[2] Creating test user: {test_handle}, Phone: {test_phone}")
    user = D1Service.get_or_create_user(test_phone, test_handle)
    print(f"    User created/retrieved: {user}")
    
    # 3. Create Post
    print("[3] Creating test post in D1...")
    post_id = D1Service.create_post(
        author_handle=test_handle,
        content="Testing Nearhood Cloudflare D1 integration with Vadodara local updates!",
        category="general",
        cityId="GJ-VADODARA",
        areaId="GJ-VADODARA-ALKAPURI",
        image_url="https://localv1r.onrender.com/api/v1/media/sample_media_123"
    )
    print(f"    Post created with ID: {post_id}")
    assert post_id is not None, "Post creation failed"
    
    # 4. Fetch Post
    print("[4] Fetching posts from D1...")
    posts = D1Service.get_posts(city_id="GJ-VADODARA", category="general")
    print(f"    Fetched {len(posts)} posts. Top post ID: {posts[0]['id'] if posts else 'None'}")
    assert len(posts) > 0, "No posts returned"
    
    # 5. Vote on Post
    print("[5] Testing vote up (+1)...")
    vote_res = D1Service.vote_post(post_id, test_handle, 1)
    print(f"    Vote (+1) result: {vote_res}")
    assert vote_res["newVote"] == 1
    
    # Toggle vote off
    print("    Testing toggle vote off...")
    toggle_res = D1Service.vote_post(post_id, test_handle, 1)
    print(f"    Toggle result: {toggle_res}")
    assert toggle_res["newVote"] == 0
    
    # 6. Add Comment
    print("[6] Adding comment to post...")
    comment_id = D1Service.add_comment(post_id, test_handle, "Great to see D1 in action!")
    print(f"    Comment added with ID: {comment_id}")
    comments = D1Service.get_comments(post_id)
    print(f"    Fetched {len(comments)} comments.")
    assert len(comments) > 0
    
    # 7. Refresh Token storage
    print("[7] Testing refresh token storage in D1...")
    jti = uuid.uuid4().hex
    D1Service.save_refresh_token(jti, user["id"], test_phone, int(time.time()) + 86400)
    token_doc = D1Service.get_refresh_token(jti)
    print(f"    Retrieved token doc: {token_doc}")
    assert token_doc is not None
    
    # 8. Clean up test post
    print("[8] Deleting test post...")
    del_ok = D1Service.delete_post(post_id)
    print(f"    Deleted post status: {del_ok}")
    
    print("\n[SUCCESS] All Cloudflare D1 Flow Tests PASSED!\n")

if __name__ == "__main__":
    test_full_d1_flow()
