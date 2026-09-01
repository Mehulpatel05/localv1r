import re

with open('backend/main.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Add GET /api/v1/posts endpoint
get_posts = '''
# 3.1 Get Posts (Read Path over REST)
@app.get("/api/v1/posts")
async def get_posts(
    limit: int = 20,
    cursor: Optional[str] = None,
    authorization: Optional[str] = Header(None, description="Bearer token")
):
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
    
    # We can enforce rate limit for reading
    if authorization and authorization.startswith("Bearer "):
        try:
            device_id, _ = verify_session_token(authorization)
            enforce_route_rate_limit("get_posts", device_id, max_requests=100)
        except:
            pass # allow anonymous reading for now, or block based on architecture

    try:
        query = db.collection("posts").order_by("createdAt", direction=firestore.Query.DESCENDING).limit(min(limit, 50))
        
        # If cursor provided, it's the post ID to start after
        if cursor:
            cursor_doc = db.collection("posts").document(cursor).get()
            if cursor_doc.exists:
                query = query.start_after(cursor_doc)
                
        docs = query.get()
        posts = []
        for doc in docs:
            data = doc.to_dict()
            if data.get("deletedAt") is not None or data.get("hiddenByMod") == True:
                continue
            
            # Format output
            data['id'] = doc.id
            if data.get('createdAt'):
                data['createdAt'] = data['createdAt'].isoformat()
            posts.append(data)
            
        last_id = docs[-1].id if docs else None
        return {"status": "success", "posts": posts, "nextCursor": last_id}
    except Exception as e:
        print(f"Error fetching posts: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch posts")

# 4.1 Get Comments
@app.get("/api/v1/posts/{post_id}/comments")
async def get_comments(post_id: str):
    if db is None:
        raise HTTPException(status_code=500, detail="Database offline.")
        
    try:
        docs = db.collection("posts").document(post_id).collection("comments").order_by("createdAt").limit(100).get()
        comments = []
        for doc in docs:
            data = doc.to_dict()
            data['id'] = doc.id
            if data.get('createdAt'):
                data['createdAt'] = data['createdAt'].isoformat()
            comments.append(data)
        return {"status": "success", "comments": comments}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to fetch comments")
'''

content = content.replace(
    '# 4. Secure Comment Addition',
    get_posts.strip() + '\n\n# 4. Secure Comment Addition'
)

with open('backend/main.py', 'w', encoding='utf-8') as f:
    f.write(content)
