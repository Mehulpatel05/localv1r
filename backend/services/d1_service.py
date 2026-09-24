import requests
import json
import time
import uuid
import hashlib
import hmac
from typing import Optional, List, Dict, Any, Tuple
from config import Config

class D1Service:
    """
    Cloudflare D1 Distributed SQL Database Service.
    Acts as the single source of truth for Users, Posts, Comments, Votes, Reports, Media, and Auth Sessions.
    """

    @classmethod
    def _get_api_url(cls) -> str:
        return f"https://api.cloudflare.com/client/v4/accounts/{Config.CLOUDFLARE_ACCOUNT_ID}/d1/database/{Config.D1_DATABASE_ID}/query"

    @classmethod
    def _get_headers(cls) -> Dict[str, str]:
        return {
            "Authorization": f"Bearer {Config.CLOUDFLARE_API_TOKEN}",
            "Content-Type": "application/json"
        }

    @classmethod
    def query(cls, sql: str, params: Optional[List[Any]] = None) -> Optional[List[Dict[str, Any]]]:
        """
        Executes a SQL SELECT query against Cloudflare D1.
        Returns the list of rows (as dictionaries) or None on failure.
        """
        payload: Dict[str, Any] = {"sql": sql}
        if params is not None:
            payload["params"] = params

        try:
            res = requests.post(
                cls._get_api_url(),
                headers=cls._get_headers(),
                json=payload,
                timeout=15
            )
            data = res.json()
            if res.status_code == 200 and data.get("success"):
                result = data.get("result", [])
                if result and len(result) > 0:
                    return result[0].get("results", [])
                return []
            else:
                print(f"[D1Service] Query failed ({res.status_code}): {data.get('errors')}")
                return None
        except Exception as e:
            print(f"[D1Service] Connection error: {e}")
            return None

    @classmethod
    def execute(cls, sql: str, params: Optional[List[Any]] = None) -> bool:
        """
        Executes a SQL INSERT / UPDATE / DELETE / DDL query.
        Returns True if successful, False otherwise.
        """
        payload: Dict[str, Any] = {"sql": sql}
        if params is not None:
            payload["params"] = params

        try:
            res = requests.post(
                cls._get_api_url(),
                headers=cls._get_headers(),
                json=payload,
                timeout=15
            )
            data = res.json()
            if res.status_code == 200 and data.get("success"):
                return True
            else:
                print(f"[D1Service] Execute failed ({res.status_code}): {data.get('errors')}")
                return False
        except Exception as e:
            print(f"[D1Service] Execution error: {e}")
            return False

    @classmethod
    def init_schema(cls) -> bool:
        """
        Initializes and ensures all schema tables exist in Cloudflare D1.
        """
        schema_queries = [
            """
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                handle TEXT UNIQUE NOT NULL,
                installation_id TEXT,
                phone TEXT,
                device_id TEXT,
                avatar_url TEXT,
                reputation INTEGER DEFAULT 0,
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS refresh_tokens (
                jti TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                phone TEXT,
                status TEXT DEFAULT 'active',
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                expires_at INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS posts (
                id TEXT PRIMARY KEY,
                author_handle TEXT NOT NULL,
                content TEXT NOT NULL,
                image_url TEXT,
                media_type TEXT DEFAULT 'photo',
                city_id TEXT NOT NULL DEFAULT 'GJ-VADODARA',
                state_id TEXT NOT NULL DEFAULT 'GJ',
                area_id TEXT NOT NULL,
                category TEXT NOT NULL,
                upvotes INTEGER DEFAULT 0,
                downvotes INTEGER DEFAULT 0,
                score INTEGER DEFAULT 0,
                comment_count INTEGER DEFAULT 0,
                is_emergency INTEGER DEFAULT 0,
                hidden_by_mod INTEGER DEFAULT 0,
                report_count INTEGER DEFAULT 0,
                meta_json TEXT,
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER DEFAULT (strftime('%s', 'now')),
                deleted_at INTEGER
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS comments (
                id TEXT PRIMARY KEY,
                post_id TEXT NOT NULL,
                author_handle TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS votes (
                post_id TEXT NOT NULL,
                user_handle TEXT NOT NULL,
                direction INTEGER NOT NULL,
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                PRIMARY KEY (post_id, user_handle)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS reports (
                id TEXT PRIMARY KEY,
                post_id TEXT NOT NULL,
                reporter_handle TEXT NOT NULL,
                reason TEXT NOT NULL,
                status TEXT DEFAULT 'pending',
                created_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media (
                media_id TEXT PRIMARY KEY,
                object_key TEXT NOT NULL,
                bucket TEXT NOT NULL DEFAULT 'nearhood',
                storage_provider TEXT DEFAULT 'r2',
                size INTEGER NOT NULL,
                mime_type TEXT NOT NULL,
                media_type TEXT DEFAULT 'photo',
                content_hash TEXT,
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                deleted_at INTEGER
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS moderation_logs (
                id TEXT PRIMARY KEY,
                moderator_id TEXT NOT NULL,
                role TEXT NOT NULL,
                action TEXT NOT NULL,
                target TEXT NOT NULL,
                reason TEXT,
                request_id TEXT,
                ip_address TEXT,
                created_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS banned_users (
                handle TEXT PRIMARY KEY,
                banned_by TEXT NOT NULL,
                reason TEXT,
                created_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """
        ]

        all_ok = True
        for q in schema_queries:
            if not cls.execute(q.strip()):
                all_ok = False

        # Apply column migrations safely if tables already exist
        migrations = [
            "ALTER TABLE posts ADD COLUMN meta_json TEXT;",
            "ALTER TABLE posts ADD COLUMN deleted_at INTEGER;",
        ]
        for m in migrations:
            cls.execute(m.strip())

        return all_ok

    # ==========================================
    # 📝 POSTS & FEED OPERATIONS
    # ==========================================

    @classmethod
    def create_post(
        cls,
        author_handle: str,
        content: str,
        category: str,
        cityId: str,
        areaId: str,
        image_url: Optional[str] = None,
        media_type: str = "photo",
        **kwargs
    ) -> Optional[str]:
        post_id = kwargs.pop("post_id", None) or str(uuid.uuid4())
        state_id = cityId.split("-")[0] if "-" in cityId else "GJ"
        is_emergency = 1 if category.lower() == "emergency" else 0
        now_ts = int(time.time())

        # Collect optional category fields into meta_json
        meta_dict = {k: v for k, v in kwargs.items() if v is not None}
        meta_json = json.dumps(meta_dict) if meta_dict else None

        sql = """
        INSERT INTO posts (
            id, author_handle, content, image_url, media_type,
            city_id, state_id, area_id, category,
            upvotes, downvotes, score, comment_count,
            is_emergency, hidden_by_mod, report_count,
            meta_json, created_at, updated_at
        ) VALUES (
            ?, ?, ?, ?, ?,
            ?, ?, ?, ?,
            0, 0, 0, 0,
            ?, 0, 0,
            ?, ?, ?
        );
        """
        params = [
            post_id, author_handle, content, image_url, media_type,
            cityId, state_id, areaId, category,
            is_emergency,
            meta_json, now_ts, now_ts
        ]

        if cls.execute(sql, params):
            return post_id
        return None

    @classmethod
    def get_posts(
        cls,
        city_id: Optional[str] = None,
        area_id: Optional[str] = None,
        category: Optional[str] = None,
        author: Optional[str] = None,
        cursor: Optional[str] = None,
        limit: int = 20
    ) -> List[Dict[str, Any]]:
        conditions = ["deleted_at IS NULL", "hidden_by_mod = 0"]
        params = []

        if city_id:
            conditions.append("city_id = ?")
            params.append(city_id)
        if area_id:
            conditions.append("area_id = ?")
            params.append(area_id)
        if category:
            conditions.append("category = ?")
            params.append(category)
        if author:
            conditions.append("author_handle = ?")
            params.append(author)
            
        if cursor:
            # Cursor pagination using created_at timestamp
            cursor_post = cls.get_post_by_id(cursor)
            if cursor_post and "created_at" in cursor_post:
                conditions.append("created_at < ?")
                params.append(cursor_post["created_at"])

        where_clause = " WHERE " + " AND ".join(conditions)
        sql = f"""
        SELECT * FROM posts
        {where_clause}
        ORDER BY created_at DESC
        LIMIT ?;
        """
        params.append(min(limit, 50))

        rows = cls.query(sql, params) or []
        formatted_posts = []
        for r in rows:
            post = {
                "id": r["id"],
                "authorHandle": r["author_handle"],
                "content": r["content"],
                "imageUrl": r["image_url"],
                "mediaType": r.get("media_type", "photo"),
                "cityId": r["city_id"],
                "stateId": r["state_id"],
                "areaId": r["area_id"],
                "category": r["category"],
                "upvotes": r.get("upvotes", 0),
                "downvotes": r.get("downvotes", 0),
                "score": r.get("score", 0),
                "totalScore": r.get("score", 0),
                "commentCount": r.get("comment_count", 0),
                "isEmergency": bool(r.get("is_emergency", 0)),
                "hiddenByMod": bool(r.get("hidden_by_mod", 0)),
                "reportCount": r.get("report_count", 0),
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None
            }
            # Unpack meta_json if present
            if r.get("meta_json"):
                try:
                    meta = json.loads(r["meta_json"])
                    for mk, mv in meta.items():
                        if mk not in post:
                            post[mk] = mv
                except:
                    pass
            formatted_posts.append(post)
        return formatted_posts

    @classmethod
    def get_post_by_id(cls, post_id: str) -> Optional[Dict[str, Any]]:
        sql = "SELECT * FROM posts WHERE id = ? LIMIT 1;"
        rows = cls.query(sql, [post_id])
        if rows and len(rows) > 0:
            r = rows[0]
            post = {
                "id": r["id"],
                "authorHandle": r["author_handle"],
                "content": r["content"],
                "imageUrl": r["image_url"],
                "mediaType": r.get("media_type", "photo"),
                "cityId": r["city_id"],
                "stateId": r["state_id"],
                "areaId": r["area_id"],
                "category": r["category"],
                "upvotes": r.get("upvotes", 0),
                "downvotes": r.get("downvotes", 0),
                "score": r.get("score", 0),
                "totalScore": r.get("score", 0),
                "commentCount": r.get("comment_count", 0),
                "isEmergency": bool(r.get("is_emergency", 0)),
                "hiddenByMod": bool(r.get("hidden_by_mod", 0)),
                "reportCount": r.get("report_count", 0),
                "created_at": r.get("created_at"),
                "deletedAt": r.get("deleted_at")
            }
            if r.get("meta_json"):
                try:
                    meta = json.loads(r["meta_json"])
                    for mk, mv in meta.items():
                        if mk not in post:
                            post[mk] = mv
                except:
                    pass
            return post
        return None

    @classmethod
    def delete_post(cls, post_id: str) -> bool:
        now_ts = int(time.time())
        sql = "UPDATE posts SET deleted_at = ? WHERE id = ?;"
        return cls.execute(sql, [now_ts, post_id])

    @classmethod
    def restore_post(cls, post_id: str) -> bool:
        # Unhide, reset report count, and remove reports
        cls.execute("DELETE FROM reports WHERE post_id = ?;", [post_id])
        sql = "UPDATE posts SET hidden_by_mod = 0, report_count = 0, deleted_at = NULL WHERE id = ?;"
        return cls.execute(sql, [post_id])

    # ==========================================
    # 💬 COMMENTS OPERATIONS
    # ==========================================

    @classmethod
    def add_comment(cls, post_id: str, author_handle: str, content: str) -> Optional[str]:
        comment_id = str(uuid.uuid4())
        now_ts = int(time.time())
        
        insert_sql = "INSERT INTO comments (id, post_id, author_handle, content, created_at) VALUES (?, ?, ?, ?, ?);"
        if cls.execute(insert_sql, [comment_id, post_id, author_handle, content, now_ts]):
            # Increment comment_count on post
            cls.execute("UPDATE posts SET comment_count = comment_count + 1 WHERE id = ?;", [post_id])
            return comment_id
        return None

    @classmethod
    def get_comments(cls, post_id: str, limit: int = 100) -> List[Dict[str, Any]]:
        sql = "SELECT * FROM comments WHERE post_id = ? ORDER BY created_at ASC LIMIT ?;"
        rows = cls.query(sql, [post_id, limit]) or []
        res = []
        for r in rows:
            res.append({
                "id": r["id"],
                "postId": r["post_id"],
                "authorHandle": r["author_handle"],
                "content": r["content"],
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None
            })
        return res

    # ==========================================
    # 🗳️ VOTING & SCORING OPERATIONS
    # ==========================================

    @classmethod
    def vote_post(cls, post_id: str, user_handle: str, direction: int) -> Dict[str, Any]:
        """
        Reddit/StackOverflow style toggle voting.
        direction: 1 (upvote) or -1 (downvote).
        """
        # Check existing vote
        existing = cls.query("SELECT direction FROM votes WHERE post_id = ? AND user_handle = ? LIMIT 1;", [post_id, user_handle])
        previous_vote = existing[0]["direction"] if existing and len(existing) > 0 else 0

        now_ts = int(time.time())

        if previous_vote == direction:
            # Toggle OFF vote
            new_vote = 0
            cls.execute("DELETE FROM votes WHERE post_id = ? AND user_handle = ?;", [post_id, user_handle])
            if direction == 1:
                score_delta, up_delta, down_delta = -1, -1, 0
            else:
                score_delta, up_delta, down_delta = 1, 0, -1
        elif previous_vote == 0:
            # Cast new vote
            new_vote = direction
            cls.execute("INSERT OR REPLACE INTO votes (post_id, user_handle, direction, created_at) VALUES (?, ?, ?, ?);", [post_id, user_handle, direction, now_ts])
            if direction == 1:
                score_delta, up_delta, down_delta = 1, 1, 0
            else:
                score_delta, up_delta, down_delta = -1, 0, 1
        else:
            # Switch vote (+1 to -1 or vice versa)
            new_vote = direction
            cls.execute("UPDATE votes SET direction = ?, created_at = ? WHERE post_id = ? AND user_handle = ?;", [direction, now_ts, post_id, user_handle])
            if direction == 1:
                score_delta, up_delta, down_delta = 2, 1, -1
            else:
                score_delta, up_delta, down_delta = -2, -1, 1

        # Atomically update posts counters
        update_post_sql = """
        UPDATE posts SET
            score = score + ?,
            upvotes = MAX(0, upvotes + ?),
            downvotes = MAX(0, downvotes + ?),
            updated_at = ?
        WHERE id = ?;
        """
        cls.execute(update_post_sql, [score_delta, up_delta, down_delta, now_ts, post_id])

        return {
            "success": True,
            "newVote": new_vote,
            "scoreDelta": score_delta,
            "upvoteDelta": up_delta,
            "downvoteDelta": down_delta
        }

    # ==========================================
    # 🚨 REPORTS & MODERATION
    # ==========================================

    @classmethod
    def report_post(cls, post_id: str, reporter_handle: str, reason: str) -> bool:
        # Check if already reported by this user
        existing = cls.query("SELECT id FROM reports WHERE post_id = ? AND reporter_handle = ? LIMIT 1;", [post_id, reporter_handle])
        if existing and len(existing) > 0:
            return True # already reported

        report_id = str(uuid.uuid4())
        now_ts = int(time.time())
        insert_sql = "INSERT INTO reports (id, post_id, reporter_handle, reason, status, created_at) VALUES (?, ?, ?, ?, 'pending', ?);"
        if cls.execute(insert_sql, [report_id, post_id, reporter_handle, reason, now_ts]):
            cls.execute("UPDATE posts SET report_count = report_count + 1 WHERE id = ?;", [post_id])
            return True
        return False

    @classmethod
    def log_moderator_action(cls, moderator_id: str, role: str, action: str, target: str, reason: str, request_id: str, ip_address: str) -> bool:
        log_id = hashlib.sha256(f"{moderator_id}:{action}:{time.time()}".encode()).hexdigest()[:16]
        now_ts = int(time.time())
        sql = """
        INSERT INTO moderation_logs (id, moderator_id, role, action, target, reason, request_id, ip_address, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        return cls.execute(sql, [log_id, moderator_id, role, action, target, reason, request_id, ip_address, now_ts])

    # ==========================================
    # 🖼️ MEDIA REGISTRY (R2 METADATA)
    # ==========================================

    @classmethod
    def register_media(
        cls,
        media_id: str,
        object_key: str,
        size: int,
        mime_type: str,
        content_hash: str,
        storage_provider: str = "r2",
        media_type: str = "photo",
        **kwargs
    ) -> bool:
        now_ts = int(time.time())
        sql = """
        INSERT OR REPLACE INTO media (
            media_id, object_key, bucket, storage_provider, size, mime_type, media_type, content_hash, created_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?
        );
        """
        return cls.execute(sql, [media_id, object_key, Config.R2_BUCKET_NAME, storage_provider, size, mime_type, media_type, content_hash, now_ts])

    @classmethod
    def get_media_by_id(cls, media_id: str) -> Optional[Dict[str, Any]]:
        sql = "SELECT * FROM media WHERE media_id = ? LIMIT 1;"
        rows = cls.query(sql, [media_id])
        if rows and len(rows) > 0:
            r = rows[0]
            return {
                "mediaId": r["media_id"],
                "objectKey": r["object_key"],
                "bucket": r["bucket"],
                "storageProvider": r["storage_provider"],
                "size": r["size"],
                "mimeType": r["mime_type"],
                "mediaType": r.get("media_type", "photo"),
                "contentHash": r["content_hash"],
                "deletedAt": r.get("deleted_at")
            }
        return None

    @classmethod
    def get_media_by_hash(cls, content_hash: str) -> Optional[Dict[str, Any]]:
        sql = "SELECT * FROM media WHERE content_hash = ? AND deleted_at IS NULL LIMIT 1;"
        rows = cls.query(sql, [content_hash])
        if rows and len(rows) > 0:
            r = rows[0]
            return {
                "mediaId": r["media_id"],
                "objectKey": r["object_key"],
                "bucket": r["bucket"],
                "storageProvider": r["storage_provider"],
                "size": r["size"],
                "mimeType": r["mime_type"],
                "mediaType": r.get("media_type", "photo")
            }
        return None

    @classmethod
    def delete_media(cls, media_id: str) -> bool:
        now_ts = int(time.time())
        sql = "UPDATE media SET deleted_at = ? WHERE media_id = ?;"
        return cls.execute(sql, [now_ts, media_id])

    # ==========================================
    # 🔑 USER & AUTH SESSIONS
    # ==========================================

    @classmethod
    def save_refresh_token(cls, jti: str, user_id: str, phone: str, expires_at: int) -> bool:
        now_ts = int(time.time())
        sql = "INSERT OR REPLACE INTO refresh_tokens (jti, user_id, phone, status, created_at, expires_at) VALUES (?, ?, ?, 'active', ?, ?);"
        return cls.execute(sql, [jti, user_id, phone, now_ts, expires_at])

    @classmethod
    def get_refresh_token(cls, jti: str) -> Optional[Dict[str, Any]]:
        sql = "SELECT * FROM refresh_tokens WHERE jti = ? LIMIT 1;"
        rows = cls.query(sql, [jti])
        if rows and len(rows) > 0:
            return rows[0]
        return None

    @classmethod
    def revoke_refresh_token(cls, jti: str) -> bool:
        sql = "UPDATE refresh_tokens SET status = 'revoked' WHERE jti = ?;"
        return cls.execute(sql, [jti])

    @classmethod
    def get_user_by_id(cls, user_id: str) -> Optional[Dict[str, Any]]:
        sql = "SELECT * FROM users WHERE id = ? LIMIT 1;"
        rows = cls.query(sql, [user_id])
        if rows and len(rows) > 0:
            return rows[0]
        return None

    @classmethod
    def get_user_by_handle(cls, handle: str) -> Optional[Dict[str, Any]]:
        sql = "SELECT * FROM users WHERE LOWER(handle) = LOWER(?) LIMIT 1;"
        rows = cls.query(sql, [handle])
        if rows and len(rows) > 0:
            return rows[0]
        return None

    @classmethod
    def get_user_by_phone(cls, phone: str) -> Optional[Dict[str, Any]]:
        sql = "SELECT * FROM users WHERE phone = ? LIMIT 1;"
        rows = cls.query(sql, [phone])
        if rows and len(rows) > 0:
            return rows[0]
        return None

    @classmethod
    def is_handle_available(cls, handle: str, exclude_user_id: Optional[str] = None) -> bool:
        clean = handle.replace("@", "").strip().lower()
        if exclude_user_id:
            sql = "SELECT id FROM users WHERE LOWER(REPLACE(handle, '@', '')) = ? AND id != ? LIMIT 1;"
            rows = cls.query(sql, [clean, exclude_user_id])
        else:
            sql = "SELECT id FROM users WHERE LOWER(REPLACE(handle, '@', '')) = ? LIMIT 1;"
            rows = cls.query(sql, [clean])
        return not bool(rows and len(rows) > 0)

    @classmethod
    def update_user_handle(cls, user_id: str, new_handle: str) -> bool:
        now_ts = int(time.time())
        sql = "UPDATE users SET handle = ?, updated_at = ? WHERE id = ?;"
        return cls.execute(sql, [new_handle, now_ts, user_id])

    @classmethod
    def update_user_avatar(cls, user_id: str, avatar_url: str) -> bool:
        now_ts = int(time.time())
        sql = "UPDATE users SET avatar_url = ?, updated_at = ? WHERE id = ?;"
        return cls.execute(sql, [avatar_url, now_ts, user_id])

    @classmethod
    def get_or_create_user(cls, phone: str, handle: str, installation_id: Optional[str] = None) -> Dict[str, Any]:
        existing = cls.query("SELECT * FROM users WHERE phone = ? OR handle = ? LIMIT 1;", [phone, handle])
        now_ts = int(time.time())
        if existing and len(existing) > 0:
            return existing[0]

        user_id = str(uuid.uuid4())
        sql = "INSERT INTO users (id, handle, phone, installation_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);"
        cls.execute(sql, [user_id, handle, phone, installation_id, now_ts, now_ts])
        return {"id": user_id, "handle": handle, "phone": phone, "installation_id": installation_id}

