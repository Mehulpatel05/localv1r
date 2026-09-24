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
            """,
            """
            CREATE TABLE IF NOT EXISTS friendships (
                id TEXT PRIMARY KEY,
                user1 TEXT NOT NULL,
                user2 TEXT NOT NULL,
                created_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_friendships_user1 ON friendships(user1);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_friendships_user2 ON friendships(user2);
            """,
            """
            CREATE TABLE IF NOT EXISTS friend_requests (
                id TEXT PRIMARY KEY,
                sender_handle TEXT NOT NULL,
                receiver_handle TEXT NOT NULL,
                status TEXT DEFAULT 'pending',
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_fr_receiver ON friend_requests(receiver_handle, status);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_fr_sender ON friend_requests(sender_handle, status);
            """,
            """
            CREATE TABLE IF NOT EXISTS blocks (
                id TEXT PRIMARY KEY,
                blocker_handle TEXT NOT NULL,
                blocked_handle TEXT NOT NULL,
                created_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON blocks(blocker_handle);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_handle);
            """,
            """
            CREATE TABLE IF NOT EXISTS communities (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT,
                is_channel INTEGER DEFAULT 0,
                admin_handle TEXT NOT NULL,
                member_count INTEGER DEFAULT 1,
                image_url TEXT,
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_comm_created ON communities(created_at DESC);
            """,
            """
            CREATE TABLE IF NOT EXISTS community_members (
                id TEXT PRIMARY KEY,
                community_id TEXT NOT NULL,
                user_handle TEXT NOT NULL,
                role TEXT DEFAULT 'member',
                last_read_at INTEGER DEFAULT (strftime('%s', 'now')),
                joined_at INTEGER DEFAULT (strftime('%s', 'now')),
                FOREIGN KEY (community_id) REFERENCES communities(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_cm_user ON community_members(user_handle);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_cm_comm ON community_members(community_id);
            """,
            """
            CREATE TABLE IF NOT EXISTS community_messages (
                id TEXT PRIMARY KEY,
                community_id TEXT NOT NULL,
                author_handle TEXT NOT NULL,
                content TEXT NOT NULL,
                image_url TEXT,
                media_urls_json TEXT,
                message_type TEXT DEFAULT 'text',
                reactions_json TEXT,
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                deleted_at INTEGER,
                FOREIGN KEY (community_id) REFERENCES communities(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_cmsg_comm_created ON community_messages(community_id, created_at ASC);
            """,
            """
            CREATE TABLE IF NOT EXISTS direct_chats (
                id TEXT PRIMARY KEY,
                user1 TEXT NOT NULL,
                user2 TEXT NOT NULL,
                last_message TEXT DEFAULT '',
                last_sender_handle TEXT DEFAULT '',
                last_message_at INTEGER DEFAULT (strftime('%s', 'now')),
                unread_user1 INTEGER DEFAULT 0,
                unread_user2 INTEGER DEFAULT 0,
                updated_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_dc_u1 ON direct_chats(user1);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_dc_u2 ON direct_chats(user2);
            """,
            """
            CREATE TABLE IF NOT EXISTS direct_messages (
                id TEXT PRIMARY KEY,
                chat_id TEXT NOT NULL,
                sender_handle TEXT NOT NULL,
                receiver_handle TEXT NOT NULL,
                content TEXT NOT NULL,
                image_url TEXT,
                media_urls_json TEXT,
                message_type TEXT DEFAULT 'text',
                reactions_json TEXT DEFAULT '{}',
                is_read INTEGER DEFAULT 0,
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                deleted_at INTEGER,
                FOREIGN KEY (chat_id) REFERENCES direct_chats(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_dm_chat_created ON direct_messages(chat_id, created_at ASC);
            """,
            """
            CREATE TABLE IF NOT EXISTS calls (
                id TEXT PRIMARY KEY,
                caller_handle TEXT NOT NULL,
                receiver_handle TEXT NOT NULL,
                call_type TEXT DEFAULT 'audio',
                status TEXT DEFAULT 'ringing',
                sdp_offer TEXT,
                sdp_answer TEXT,
                caller_ice_candidates_json TEXT DEFAULT '[]',
                receiver_ice_candidates_json TEXT DEFAULT '[]',
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_calls_receiver ON calls(receiver_handle, status);
            """,
            """
            CREATE TABLE IF NOT EXISTS presence (
                handle TEXT PRIMARY KEY,
                is_online INTEGER DEFAULT 0,
                last_seen_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS notifications (
                id TEXT PRIMARY KEY,
                target_handle TEXT NOT NULL,
                sender_handle TEXT,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                type TEXT NOT NULL,
                data_json TEXT,
                is_read INTEGER DEFAULT 0,
                created_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_notif_target ON notifications(target_handle, created_at DESC);
            """,
            """
            CREATE TABLE IF NOT EXISTS user_preferences (
                handle TEXT PRIMARY KEY,
                preferences_json TEXT,
                call_privacy TEXT DEFAULT 'everyone',
                updated_at INTEGER DEFAULT (strftime('%s', 'now'))
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
        areaId: Optional[str] = None,
        image_url: Optional[str] = None,
        media_type: str = "photo",
        **kwargs
    ) -> Optional[str]:
        post_id = kwargs.pop("post_id", None) or str(uuid.uuid4())
        state_id = cityId.split("-")[0] if "-" in cityId else "GJ"
        is_emergency = 1 if category.lower() == "emergency" else 0
        now_ts = int(time.time())
        eff_area = areaId or cityId

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
            cityId, state_id, eff_area, category,
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
            clean_author = author.replace("@", "").strip().lower()
            conditions.append("LOWER(REPLACE(author_handle, '@', '')) = ?")
            params.append(clean_author)
            
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

    # ==========================================
    # 🤝 FRIENDSHIPS, REQUESTS & BLOCKS
    # ==========================================

    @classmethod
    def canonical_pair(cls, u1: str, u2: str) -> Tuple[str, str]:
        c1 = u1.replace("@", "").strip().lower()
        c2 = u2.replace("@", "").strip().lower()
        return (c1, c2) if c1 < c2 else (c2, c1)

    @classmethod
    def canonical_friendship_id(cls, u1: str, u2: str) -> str:
        p1, p2 = cls.canonical_pair(u1, u2)
        return f"{p1}_{p2}"

    @classmethod
    def get_relationship_status(cls, user1: str, user2: str) -> str:
        u1 = user1.replace("@", "").strip().lower()
        u2 = user2.replace("@", "").strip().lower()
        if not u1 or not u2 or u1 == u2:
            return "none"

        # 1. Blocked by me
        b1 = cls.query("SELECT id FROM blocks WHERE LOWER(blocker_handle) = ? AND LOWER(blocked_handle) = ? LIMIT 1;", [u1, u2])
        if b1 and len(b1) > 0:
            return "blockedByMe"

        # 2. Blocked by them
        b2 = cls.query("SELECT id FROM blocks WHERE LOWER(blocker_handle) = ? AND LOWER(blocked_handle) = ? LIMIT 1;", [u2, u1])
        if b2 and len(b2) > 0:
            return "blockedByThem"

        # 3. Friends
        fid = cls.canonical_friendship_id(u1, u2)
        f = cls.query("SELECT id FROM friendships WHERE id = ? LIMIT 1;", [fid])
        if f and len(f) > 0:
            return "friends"

        # 4. Request sent by me
        req_sent = cls.query("SELECT id FROM friend_requests WHERE LOWER(sender_handle) = ? AND LOWER(receiver_handle) = ? AND status = 'pending' LIMIT 1;", [u1, u2])
        if req_sent and len(req_sent) > 0:
            return "requestSentByMe"

        # 5. Request received by me
        req_recv = cls.query("SELECT id FROM friend_requests WHERE LOWER(sender_handle) = ? AND LOWER(receiver_handle) = ? AND status = 'pending' LIMIT 1;", [u2, u1])
        if req_recv and len(req_recv) > 0:
            return "requestReceivedByMe"

        return "none"

    @classmethod
    def send_friend_request(cls, sender: str, receiver: str) -> Tuple[bool, str]:
        s = sender.replace("@", "").strip().lower()
        r = receiver.replace("@", "").strip().lower()
        if not s or not r:
            return False, "Invalid username"
        if s == r:
            return False, "Cannot send request to yourself"

        rel_status = cls.get_relationship_status(s, r)
        if rel_status == "friends":
            return False, "You are already friends"
        if rel_status == "requestSentByMe":
            return False, "Friend request already sent"
        if rel_status == "requestReceivedByMe":
            cls.accept_friend_request(r, s)
            return True, "Friend request accepted"
        if rel_status in ["blockedByMe", "blockedByThem"]:
            return False, "Unable to send friend request"

        req_id = f"{s}_{r}"
        now_ts = int(time.time())
        sql = "INSERT OR REPLACE INTO friend_requests (id, sender_handle, receiver_handle, status, created_at, updated_at) VALUES (?, ?, ?, 'pending', ?, ?);"
        ok = cls.execute(sql, [req_id, s, r, now_ts, now_ts])
        return ok, "Friend request sent" if ok else "Failed to send request"

    @classmethod
    def accept_friend_request(cls, sender: str, receiver: str) -> bool:
        s = sender.replace("@", "").strip().lower()
        r = receiver.replace("@", "").strip().lower()
        now_ts = int(time.time())

        # Update request status
        cls.execute("UPDATE friend_requests SET status = 'accepted', updated_at = ? WHERE (LOWER(sender_handle) = ? AND LOWER(receiver_handle) = ?) OR (LOWER(sender_handle) = ? AND LOWER(receiver_handle) = ?);", [now_ts, s, r, r, s])

        # Create friendship entry
        p1, p2 = cls.canonical_pair(s, r)
        fid = f"{p1}_{p2}"
        sql = "INSERT OR IGNORE INTO friendships (id, user1, user2, created_at) VALUES (?, ?, ?, ?);"
        return cls.execute(sql, [fid, p1, p2, now_ts])

    @classmethod
    def reject_friend_request(cls, sender: str, receiver: str) -> bool:
        s = sender.replace("@", "").strip().lower()
        r = receiver.replace("@", "").strip().lower()
        now_ts = int(time.time())
        sql = "UPDATE friend_requests SET status = 'rejected', updated_at = ? WHERE LOWER(sender_handle) = ? AND LOWER(receiver_handle) = ?;"
        return cls.execute(sql, [now_ts, s, r])

    @classmethod
    def cancel_friend_request(cls, sender: str, receiver: str) -> bool:
        s = sender.replace("@", "").strip().lower()
        r = receiver.replace("@", "").strip().lower()
        sql = "DELETE FROM friend_requests WHERE LOWER(sender_handle) = ? AND LOWER(receiver_handle) = ? AND status = 'pending';"
        return cls.execute(sql, [s, r])

    @classmethod
    def unfriend(cls, user1: str, user2: str) -> bool:
        p1, p2 = cls.canonical_pair(user1, user2)
        fid = f"{p1}_{p2}"
        cls.execute("DELETE FROM friendships WHERE id = ?;", [fid])
        cls.execute("DELETE FROM friend_requests WHERE (LOWER(sender_handle) = ? AND LOWER(receiver_handle) = ?) OR (LOWER(sender_handle) = ? AND LOWER(receiver_handle) = ?);", [p1, p2, p2, p1])
        return True

    @classmethod
    def block_user(cls, blocker: str, blocked: str) -> bool:
        b = blocker.replace("@", "").strip().lower()
        t = blocked.replace("@", "").strip().lower()
        now_ts = int(time.time())
        block_id = f"{b}_{t}"
        cls.execute("INSERT OR REPLACE INTO blocks (id, blocker_handle, blocked_handle, created_at) VALUES (?, ?, ?, ?);", [block_id, b, t, now_ts])
        cls.unfriend(b, t)
        return True

    @classmethod
    def unblock_user(cls, blocker: str, blocked: str) -> bool:
        b = blocker.replace("@", "").strip().lower()
        t = blocked.replace("@", "").strip().lower()
        return cls.execute("DELETE FROM blocks WHERE LOWER(blocker_handle) = ? AND LOWER(blocked_handle) = ?;", [b, t])

    @classmethod
    def get_friends(cls, handle: str, limit: int = 100) -> List[Dict[str, Any]]:
        h = handle.replace("@", "").strip().lower()
        sql = """
        SELECT f.id, f.user1, f.user2, f.created_at,
               u.handle, u.avatar_url, u.reputation
        FROM friendships f
        LEFT JOIN users u ON (
            CASE WHEN LOWER(f.user1) = ? THEN LOWER(f.user2) ELSE LOWER(f.user1) END = LOWER(u.handle)
        )
        WHERE LOWER(f.user1) = ? OR LOWER(f.user2) = ?
        ORDER BY f.created_at DESC
        LIMIT ?;
        """
        rows = cls.query(sql, [h, h, h, limit]) or []
        results = []
        for r in rows:
            other_handle = r["user2"] if r["user1"].lower() == h else r["user1"]
            results.append({
                "id": r["id"],
                "users": [r["user1"], r["user2"]],
                "otherUser": r.get("handle") or other_handle,
                "avatarUrl": r.get("avatar_url") or "",
                "reputation": r.get("reputation") or 0,
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None
            })
        return results

    @classmethod
    def get_pending_requests(cls, handle: str, direction: str = "received") -> List[Dict[str, Any]]:
        h = handle.replace("@", "").strip().lower()
        if direction == "received":
            sql = """
            SELECT r.id, r.sender_handle, r.receiver_handle, r.status, r.created_at, r.updated_at,
                   u.avatar_url AS sender_avatar
            FROM friend_requests r
            LEFT JOIN users u ON LOWER(r.sender_handle) = LOWER(u.handle)
            WHERE LOWER(r.receiver_handle) = ? AND r.status = 'pending'
            ORDER BY r.created_at DESC;
            """
            rows = cls.query(sql, [h]) or []
        else:
            sql = """
            SELECT r.id, r.sender_handle, r.receiver_handle, r.status, r.created_at, r.updated_at,
                   u.avatar_url AS receiver_avatar
            FROM friend_requests r
            LEFT JOIN users u ON LOWER(r.receiver_handle) = LOWER(u.handle)
            WHERE LOWER(r.sender_handle) = ? AND r.status = 'pending'
            ORDER BY r.created_at DESC;
            """
            rows = cls.query(sql, [h]) or []
        results = []
        for r in rows:
            results.append({
                "id": r["id"],
                "senderHandle": r["sender_handle"],
                "receiverHandle": r["receiver_handle"],
                "status": r["status"],
                "senderAvatarUrl": r.get("sender_avatar") or "",
                "receiverAvatarUrl": r.get("receiver_avatar") or "",
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None,
                "updatedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["updated_at"])) if r.get("updated_at") else None
            })
        return results

    @classmethod
    def get_blocked_users(cls, handle: str) -> List[Dict[str, Any]]:
        h = handle.replace("@", "").strip().lower()
        sql = "SELECT id, blocker_handle, blocked_handle, created_at FROM blocks WHERE LOWER(blocker_handle) = ? ORDER BY created_at DESC;"
        rows = cls.query(sql, [h]) or []
        results = []
        for r in rows:
            results.append({
                "id": r["id"],
                "blockerHandle": r["blocker_handle"],
                "blockedHandle": r["blocked_handle"],
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None
            })
        return results

    @classmethod
    def get_friend_count(cls, handle: str) -> int:
        h = handle.replace("@", "").strip().lower()
        sql = "SELECT COUNT(*) as cnt FROM friendships WHERE LOWER(user1) = ? OR LOWER(user2) = ?;"
        rows = cls.query(sql, [h, h])
        if rows and len(rows) > 0:
            return rows[0].get("cnt", 0)
        return 0

    @classmethod
    def get_user_upvotes(cls, handle: str) -> int:
        clean = handle.replace("@", "").strip().lower()
        sql = "SELECT COALESCE(SUM(upvotes), 0) as total FROM posts WHERE LOWER(REPLACE(author_handle, '@', '')) = ? AND deleted_at IS NULL;"
        rows = cls.query(sql, [clean])
        if rows and len(rows) > 0:
            return int(rows[0].get("total", 0) or 0)
        return 0

    # ==========================================
    # 👥 COMMUNITIES & GENERAL CHAT OPERATIONS
    # ==========================================

    @classmethod
    def create_community(
        cls,
        name: str,
        description: str,
        admin_handle: str,
        is_channel: bool = False,
        image_url: Optional[str] = None
    ) -> Optional[str]:
        comm_id = str(uuid.uuid4())
        now_ts = int(time.time())
        clean_admin = admin_handle.replace("@", "").strip()

        sql = """
        INSERT INTO communities (id, name, description, is_channel, admin_handle, member_count, image_url, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?);
        """
        if cls.execute(sql, [comm_id, name.strip(), description.strip(), 1 if is_channel else 0, clean_admin, image_url, now_ts, now_ts]):
            # Add admin as first member
            member_id = f"{comm_id}_{clean_admin.lower()}"
            cls.execute("INSERT OR REPLACE INTO community_members (id, community_id, user_handle, role, last_read_at, joined_at) VALUES (?, ?, ?, 'admin', ?, ?);", [member_id, comm_id, clean_admin, now_ts, now_ts])
            return comm_id
        return None

    @classmethod
    def get_communities(
        cls,
        user_handle: Optional[str] = None,
        filter_mode: str = "all"
    ) -> List[Dict[str, Any]]:
        clean_user = user_handle.replace("@", "").strip().lower() if user_handle else None

        if filter_mode == "joined":
            if not clean_user:
                return []
            sql = """
            SELECT c.* FROM communities c
            INNER JOIN community_members m ON c.id = m.community_id
            WHERE LOWER(m.user_handle) = ?
            ORDER BY c.name ASC;
            """
            rows = cls.query(sql, [clean_user]) or []
        elif filter_mode == "discover":
            if clean_user:
                sql = """
                SELECT c.* FROM communities c
                WHERE c.id NOT IN (
                    SELECT community_id FROM community_members WHERE LOWER(user_handle) = ?
                )
                ORDER BY c.created_at DESC;
                """
                rows = cls.query(sql, [clean_user]) or []
            else:
                sql = "SELECT * FROM communities ORDER BY created_at DESC;"
                rows = cls.query(sql) or []
        else:
            sql = "SELECT * FROM communities ORDER BY created_at DESC;"
            rows = cls.query(sql) or []

        res = []
        for r in rows:
            res.append({
                "id": r["id"],
                "name": r["name"],
                "description": r.get("description", ""),
                "isChannel": bool(r.get("is_channel", 0)),
                "adminHandle": r["admin_handle"],
                "memberCount": r.get("member_count", 1),
                "imageUrl": r.get("image_url"),
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None,
                "updatedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["updated_at"])) if r.get("updated_at") else None
            })
        return res

    @classmethod
    def get_community_by_id(cls, community_id: str) -> Optional[Dict[str, Any]]:
        sql = "SELECT * FROM communities WHERE id = ? LIMIT 1;"
        rows = cls.query(sql, [community_id])
        if rows and len(rows) > 0:
            r = rows[0]
            return {
                "id": r["id"],
                "name": r["name"],
                "description": r.get("description", ""),
                "isChannel": bool(r.get("is_channel", 0)),
                "adminHandle": r["admin_handle"],
                "memberCount": r.get("member_count", 1),
                "imageUrl": r.get("image_url"),
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None
            }
        return None

    @classmethod
    def update_community(
        cls,
        community_id: str,
        admin_handle: str,
        name: Optional[str] = None,
        description: Optional[str] = None,
        image_url: Optional[str] = None
    ) -> bool:
        comm = cls.get_community_by_id(community_id)
        if not comm:
            return False
        clean_admin = admin_handle.replace("@", "").strip().lower()
        if comm["adminHandle"].lower() != clean_admin:
            return False

        updates = ["updated_at = ?"]
        params = [int(time.time())]

        if name:
            updates.append("name = ?")
            params.append(name.strip())
        if description is not None:
            updates.append("description = ?")
            params.append(description.strip())
        if image_url is not None:
            updates.append("image_url = ?")
            params.append(image_url.strip())

        params.append(community_id)
        sql = f"UPDATE communities SET {', '.join(updates)} WHERE id = ?;"
        return cls.execute(sql, params)

    @classmethod
    def join_community(cls, community_id: str, user_handle: str) -> bool:
        clean_user = user_handle.replace("@", "").strip()
        member_id = f"{community_id}_{clean_user.lower()}"
        now_ts = int(time.time())

        # Check existing membership
        existing = cls.query("SELECT id FROM community_members WHERE id = ? LIMIT 1;", [member_id])
        if existing and len(existing) > 0:
            return True

        sql = "INSERT INTO community_members (id, community_id, user_handle, role, last_read_at, joined_at) VALUES (?, ?, ?, 'member', ?, ?);"
        if cls.execute(sql, [member_id, community_id, clean_user, now_ts, now_ts]):
            cls.execute("UPDATE communities SET member_count = member_count + 1 WHERE id = ?;", [community_id])
            return True
        return False

    @classmethod
    def leave_community(cls, community_id: str, user_handle: str) -> bool:
        clean_user = user_handle.replace("@", "").strip().lower()
        cls.execute("DELETE FROM community_members WHERE community_id = ? AND LOWER(user_handle) = ?;", [community_id, clean_user])
        cls.execute("UPDATE communities SET member_count = MAX(1, member_count - 1) WHERE id = ?;", [community_id])
        return True

    @classmethod
    def get_community_members(cls, community_id: str) -> List[Dict[str, Any]]:
        sql = """
        SELECT m.user_handle, m.role, m.joined_at, u.avatar_url, u.reputation
        FROM community_members m
        LEFT JOIN users u ON LOWER(m.user_handle) = LOWER(u.handle)
        WHERE m.community_id = ?
        ORDER BY m.joined_at ASC;
        """
        rows = cls.query(sql, [community_id]) or []
        res = []
        for r in rows:
            res.append({
                "userHandle": r["user_handle"],
                "role": r["role"],
                "avatarUrl": r.get("avatar_url") or "",
                "reputation": r.get("reputation") or 0,
                "joinedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["joined_at"])) if r.get("joined_at") else None
            })
        return res

    @classmethod
    def send_community_message(
        cls,
        community_id: str,
        author_handle: str,
        content: str,
        image_url: Optional[str] = None,
        media_urls: Optional[List[str]] = None,
        message_type: str = "text"
    ) -> Optional[str]:
        msg_id = str(uuid.uuid4())
        now_ts = int(time.time())
        clean_author = author_handle.replace("@", "").strip()
        media_json = json.dumps(media_urls) if media_urls else None

        sql = """
        INSERT INTO community_messages (
            id, community_id, author_handle, content, image_url, media_urls_json, message_type, reactions_json, created_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, '{}', ?
        );
        """
        if cls.execute(sql, [msg_id, community_id, clean_author, content, image_url, media_json, message_type, now_ts]):
            # Update community timestamp
            cls.execute("UPDATE communities SET updated_at = ? WHERE id = ?;", [now_ts, community_id])
            return msg_id
        return None

    @classmethod
    def get_community_messages(
        cls,
        community_id: str,
        limit: int = 50,
        before_ts: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        conditions = ["community_id = ?", "deleted_at IS NULL"]
        params = [community_id]

        if before_ts:
            conditions.append("created_at < ?")
            params.append(before_ts)

        where_clause = " WHERE " + " AND ".join(conditions)
        sql = f"""
        SELECT * FROM community_messages
        {where_clause}
        ORDER BY created_at ASC
        LIMIT ?;
        """
        params.append(min(limit, 100))

        rows = cls.query(sql, params) or []
        res = []
        for r in rows:
            media_urls = []
            if r.get("media_urls_json"):
                try:
                    media_urls = json.loads(r["media_urls_json"])
                except:
                    pass

            reactions = {}
            if r.get("reactions_json"):
                try:
                    reactions = json.loads(r["reactions_json"])
                except:
                    pass

            res.append({
                "id": r["id"],
                "communityId": r["community_id"],
                "authorHandle": r["author_handle"],
                "content": r["content"],
                "imageUrl": r.get("image_url"),
                "mediaUrls": media_urls,
                "type": r.get("message_type", "text"),
                "reactions": reactions,
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None,
                "timestamp": r.get("created_at")
            })
        return res

    @classmethod
    def react_community_message(
        cls,
        message_id: str,
        user_handle: str,
        emoji: str
    ) -> Dict[str, Any]:
        clean_user = user_handle.replace("@", "").strip()
        clean_emoji = emoji.strip()

        rows = cls.query("SELECT reactions_json FROM community_messages WHERE id = ? LIMIT 1;", [message_id])
        if not rows or len(rows) == 0:
            return {"success": False, "reactions": {}}

        reactions = {}
        if rows[0].get("reactions_json"):
            try:
                reactions = json.loads(rows[0]["reactions_json"])
            except:
                pass

        user_list = reactions.get(clean_emoji, [])
        if clean_user in user_list:
            user_list.remove(clean_user)
            if not user_list:
                reactions.pop(clean_emoji, None)
            else:
                reactions[clean_emoji] = user_list
        else:
            if clean_emoji not in reactions:
                reactions[clean_emoji] = []
            reactions[clean_emoji].append(clean_user)

        reactions_json = json.dumps(reactions)
        cls.execute("UPDATE community_messages SET reactions_json = ? WHERE id = ?;", [reactions_json, message_id])
        return {"success": True, "reactions": reactions}

    @classmethod
    def delete_community_message(cls, message_id: str, user_handle: str) -> bool:
        clean_user = user_handle.replace("@", "").strip().lower()
        now_ts = int(time.time())
        sql = "UPDATE community_messages SET deleted_at = ? WHERE id = ? AND LOWER(author_handle) = ?;"
        return cls.execute(sql, [now_ts, message_id, clean_user])

    @classmethod
    def mark_community_read(cls, community_id: str, user_handle: str) -> bool:
        clean_user = user_handle.replace("@", "").strip().lower()
        member_id = f"{community_id}_{clean_user}"
        now_ts = int(time.time())
        return cls.execute("UPDATE community_members SET last_read_at = ? WHERE id = ?;", [now_ts, member_id])

    # ==========================================
    # 💬 1-ON-1 DIRECT CHAT & MESSAGING
    # ==========================================

    @classmethod
    def get_or_create_direct_chat(cls, u1: str, u2: str) -> Dict[str, Any]:
        p1, p2 = cls.canonical_pair(u1, u2)
        chat_id = f"{p1}_{p2}"
        rows = cls.query("SELECT * FROM direct_chats WHERE id = ? LIMIT 1;", [chat_id])
        if rows and len(rows) > 0:
            return rows[0]

        now_ts = int(time.time())
        sql = """
        INSERT INTO direct_chats (id, user1, user2, last_message, last_sender_handle, last_message_at, unread_user1, unread_user2, updated_at)
        VALUES (?, ?, ?, '', '', ?, 0, 0, ?);
        """
        cls.execute(sql, [chat_id, p1, p2, now_ts, now_ts])
        return {
            "id": chat_id,
            "user1": p1,
            "user2": p2,
            "last_message": "",
            "last_sender_handle": "",
            "last_message_at": now_ts,
            "unread_user1": 0,
            "unread_user2": 0,
            "updated_at": now_ts
        }

    @classmethod
    def get_user_direct_chats(cls, handle: str) -> List[Dict[str, Any]]:
        clean = handle.replace("@", "").strip().lower()
        sql = """
        SELECT c.*,
               u1.avatar_url AS u1_avatar, u1.handle AS u1_handle,
               u2.avatar_url AS u2_avatar, u2.handle AS u2_handle
        FROM direct_chats c
        LEFT JOIN users u1 ON LOWER(c.user1) = LOWER(u1.handle)
        LEFT JOIN users u2 ON LOWER(c.user2) = LOWER(u2.handle)
        WHERE LOWER(c.user1) = ? OR LOWER(c.user2) = ?
        ORDER BY c.updated_at DESC;
        """
        rows = cls.query(sql, [clean, clean]) or []
        res = []
        for r in rows:
            is_u1 = r["user1"].lower() == clean
            partner = r["user2"] if is_u1 else r["user1"]
            partner_avatar = r["u2_avatar"] if is_u1 else r["u1_avatar"]
            partner_handle = r["u2_handle"] if is_u1 else r["u1_handle"]
            unread = r["unread_user1"] if is_u1 else r["unread_user2"]

            res.append({
                "id": r["id"],
                "partnerHandle": partner_handle or partner,
                "partnerAvatarUrl": partner_avatar or "",
                "lastMessage": r.get("last_message", ""),
                "lastSenderHandle": r.get("last_sender_handle", ""),
                "lastMessageAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["last_message_at"])) if r.get("last_message_at") else None,
                "unreadCount": unread or 0,
                "updatedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["updated_at"])) if r.get("updated_at") else None
            })
        return res

    @classmethod
    def send_direct_message(
        cls,
        sender: str,
        receiver: str,
        content: str,
        image_url: Optional[str] = None,
        media_urls: Optional[List[str]] = None,
        message_type: str = "text"
    ) -> Optional[str]:
        p1, p2 = cls.canonical_pair(sender, receiver)
        chat_id = f"{p1}_{p2}"
        cls.get_or_create_direct_chat(p1, p2)

        msg_id = str(uuid.uuid4())
        now_ts = int(time.time())
        clean_sender = sender.replace("@", "").strip()
        clean_receiver = receiver.replace("@", "").strip()
        media_json = json.dumps(media_urls) if media_urls else None

        sql = """
        INSERT INTO direct_messages (
            id, chat_id, sender_handle, receiver_handle, content, image_url, media_urls_json, message_type, reactions_json, is_read, created_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, '{}', 0, ?
        );
        """
        if cls.execute(sql, [msg_id, chat_id, clean_sender, clean_receiver, content, image_url, media_json, message_type, now_ts]):
            # Update chat metadata
            is_u1 = p1.lower() == clean_sender.lower()
            unread_col = "unread_user2 = unread_user2 + 1" if is_u1 else "unread_user1 = unread_user1 + 1"
            update_chat_sql = f"""
            UPDATE direct_chats SET
                last_message = ?,
                last_sender_handle = ?,
                last_message_at = ?,
                updated_at = ?,
                {unread_col}
            WHERE id = ?;
            """
            cls.execute(update_chat_sql, [content, clean_sender, now_ts, now_ts, chat_id])
            return msg_id
        return None

    @classmethod
    def get_direct_messages(
        cls,
        chat_id: str,
        limit: int = 50,
        before_ts: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        conditions = ["chat_id = ?", "deleted_at IS NULL"]
        params = [chat_id]

        if before_ts:
            conditions.append("created_at < ?")
            params.append(before_ts)

        where_clause = " WHERE " + " AND ".join(conditions)
        sql = f"""
        SELECT * FROM direct_messages
        {where_clause}
        ORDER BY created_at ASC
        LIMIT ?;
        """
        params.append(min(limit, 100))

        rows = cls.query(sql, params) or []
        res = []
        for r in rows:
            media_urls = []
            if r.get("media_urls_json"):
                try:
                    media_urls = json.loads(r["media_urls_json"])
                except:
                    pass

            reactions = {}
            if r.get("reactions_json"):
                try:
                    reactions = json.loads(r["reactions_json"])
                except:
                    pass

            res.append({
                "id": r["id"],
                "chatId": r["chat_id"],
                "senderHandle": r["sender_handle"],
                "receiverHandle": r["receiver_handle"],
                "content": r["content"],
                "imageUrl": r.get("image_url"),
                "mediaUrls": media_urls,
                "type": r.get("message_type", "text"),
                "reactions": reactions,
                "isRead": bool(r.get("is_read", 0)),
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None,
                "timestamp": r.get("created_at")
            })
        return res

    @classmethod
    def mark_direct_chat_read(cls, chat_id: str, user_handle: str) -> bool:
        clean = user_handle.replace("@", "").strip().lower()
        parts = chat_id.split("_")
        if len(parts) >= 2:
            is_u1 = parts[0].lower() == clean
            col = "unread_user1 = 0" if is_u1 else "unread_user2 = 0"
            cls.execute(f"UPDATE direct_chats SET {col} WHERE id = ?;", [chat_id])
        cls.execute("UPDATE direct_messages SET is_read = 1 WHERE chat_id = ? AND LOWER(receiver_handle) = ?;", [chat_id, clean])
        return True

    @classmethod
    def delete_direct_message(cls, message_id: str, user_handle: str) -> bool:
        clean = user_handle.replace("@", "").strip().lower()
        now_ts = int(time.time())
        return cls.execute("UPDATE direct_messages SET deleted_at = ? WHERE id = ? AND LOWER(sender_handle) = ?;", [now_ts, message_id, clean])

    # ==========================================
    # 📞 WEBRTC AUDIO & VIDEO CALLING
    # ==========================================

    @classmethod
    def initiate_call(cls, caller: str, receiver: str, call_type: str, sdp_offer: str) -> Optional[str]:
        call_id = str(uuid.uuid4())
        now_ts = int(time.time())
        clean_caller = caller.replace("@", "").strip()
        clean_receiver = receiver.replace("@", "").strip()

        sql = """
        INSERT INTO calls (id, caller_handle, receiver_handle, call_type, status, sdp_offer, sdp_answer, caller_ice_candidates_json, receiver_ice_candidates_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, 'ringing', ?, NULL, '[]', '[]', ?, ?);
        """
        if cls.execute(sql, [call_id, clean_caller, clean_receiver, call_type, sdp_offer, now_ts, now_ts]):
            return call_id
        return None

    @classmethod
    def get_active_call_for_user(cls, handle: str) -> Optional[Dict[str, Any]]:
        clean = handle.replace("@", "").strip().lower()
        # Look for ringing or accepted calls in the last 60 seconds
        now_ts = int(time.time())
        sql = """
        SELECT * FROM calls
        WHERE (LOWER(receiver_handle) = ? OR LOWER(caller_handle) = ?)
          AND status IN ('ringing', 'accepted')
          AND created_at > ?
        ORDER BY created_at DESC
        LIMIT 1;
        """
        rows = cls.query(sql, [clean, clean, now_ts - 120])
        if rows and len(rows) > 0:
            return rows[0]
        return None

    @classmethod
    def get_call_by_id(cls, call_id: str) -> Optional[Dict[str, Any]]:
        rows = cls.query("SELECT * FROM calls WHERE id = ? LIMIT 1;", [call_id])
        if rows and len(rows) > 0:
            r = rows[0]
            caller_ice = []
            receiver_ice = []
            try:
                caller_ice = json.loads(r.get("caller_ice_candidates_json") or "[]")
                receiver_ice = json.loads(r.get("receiver_ice_candidates_json") or "[]")
            except:
                pass
            return {
                "id": r["id"],
                "callerHandle": r["caller_handle"],
                "receiverHandle": r["receiver_handle"],
                "callType": r["call_type"],
                "status": r["status"],
                "sdpOffer": r.get("sdp_offer"),
                "sdpAnswer": r.get("sdp_answer"),
                "callerIceCandidates": caller_ice,
                "receiverIceCandidates": receiver_ice,
                "createdAt": r["created_at"],
                "updatedAt": r["updated_at"]
            }
        return None

    @classmethod
    def answer_call(cls, call_id: str, receiver: str, sdp_answer: str) -> bool:
        clean = receiver.replace("@", "").strip().lower()
        now_ts = int(time.time())
        sql = "UPDATE calls SET status = 'accepted', sdp_answer = ?, updated_at = ? WHERE id = ? AND LOWER(receiver_handle) = ?;"
        return cls.execute(sql, [sdp_answer, now_ts, call_id, clean])

    @classmethod
    def add_call_ice_candidate(cls, call_id: str, handle: str, candidate_dict: Dict[str, Any]) -> bool:
        clean = handle.replace("@", "").strip().lower()
        rows = cls.query("SELECT caller_handle, receiver_handle, caller_ice_candidates_json, receiver_ice_candidates_json FROM calls WHERE id = ? LIMIT 1;", [call_id])
        if not rows or len(rows) == 0:
            return False

        r = rows[0]
        is_caller = r["caller_handle"].lower() == clean
        ice_list = []
        field = "caller_ice_candidates_json" if is_caller else "receiver_ice_candidates_json"
        try:
            ice_list = json.loads(r.get(field) or "[]")
        except:
            pass

        ice_list.append(candidate_dict)
        now_ts = int(time.time())
        sql = f"UPDATE calls SET {field} = ?, updated_at = ? WHERE id = ?;"
        return cls.execute(sql, [json.dumps(ice_list), now_ts, call_id])

    @classmethod
    def update_call_status(cls, call_id: str, status: str) -> bool:
        now_ts = int(time.time())
        return cls.execute("UPDATE calls SET status = ?, updated_at = ? WHERE id = ?;", [status, now_ts, call_id])

    # ==========================================
    # 🟢 ONLINE PRESENCE & LAST SEEN
    # ==========================================

    @classmethod
    def update_presence(cls, handle: str, is_online: bool) -> bool:
        clean = handle.replace("@", "").strip().lower()
        now_ts = int(time.time())
        sql = "INSERT OR REPLACE INTO presence (handle, is_online, last_seen_at) VALUES (?, ?, ?);"
        return cls.execute(sql, [clean, 1 if is_online else 0, now_ts])

    @classmethod
    def get_presence(cls, handle: str) -> Dict[str, Any]:
        clean = handle.replace("@", "").strip().lower()
        rows = cls.query("SELECT * FROM presence WHERE LOWER(handle) = ? LIMIT 1;", [clean])
        now_ts = int(time.time())
        if rows and len(rows) > 0:
            r = rows[0]
            last_seen = r.get("last_seen_at", 0)
            # Auto-expire online status if heartbeat is older than 60s
            is_active = bool(r.get("is_online", 0)) and (now_ts - last_seen < 60)
            return {
                "handle": r["handle"],
                "isOnline": is_active,
                "lastSeenAt": last_seen
            }
        return {"handle": clean, "isOnline": False, "lastSeenAt": 0}

    @classmethod
    def get_bulk_presence(cls, handles: List[str]) -> Dict[str, Dict[str, Any]]:
        clean_handles = [h.replace("@", "").strip().lower() for h in handles if h]
        if not clean_handles:
            return {}

        now_ts = int(time.time())
        placeholders = ", ".join(["?"] * len(clean_handles))
        sql = f"SELECT * FROM presence WHERE LOWER(handle) IN ({placeholders});"
        rows = cls.query(sql, clean_handles) or []
        res = {}
        for r in rows:
            last_seen = r.get("last_seen_at", 0)
            is_active = bool(r.get("is_online", 0)) and (now_ts - last_seen < 60)
            res[r["handle"].lower()] = {
                "isOnline": is_active,
                "lastSeenAt": last_seen
            }
        return res

    # ==========================================
    # 🔔 IN-APP NOTIFICATIONS
    # ==========================================

    @classmethod
    def create_notification(
        cls,
        target_handle: str,
        title: str,
        body: str,
        type: str,
        sender_handle: Optional[str] = None,
        data: Optional[Dict[str, Any]] = None
    ) -> Optional[str]:
        notif_id = str(uuid.uuid4())
        now_ts = int(time.time())
        clean_target = target_handle.replace("@", "").strip()
        clean_sender = sender_handle.replace("@", "").strip() if sender_handle else None
        data_json = json.dumps(data) if data else None

        sql = """
        INSERT INTO notifications (id, target_handle, sender_handle, title, body, type, data_json, is_read, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?);
        """
        if cls.execute(sql, [notif_id, clean_target, clean_sender, title, body, type, data_json, now_ts]):
            return notif_id
        return None

    @classmethod
    def get_notifications(cls, target_handle: str, limit: int = 50) -> List[Dict[str, Any]]:
        clean = target_handle.replace("@", "").strip().lower()
        sql = """
        SELECT * FROM notifications
        WHERE LOWER(target_handle) = ?
        ORDER BY created_at DESC
        LIMIT ?;
        """
        rows = cls.query(sql, [clean, min(limit, 100)]) or []
        res = []
        for r in rows:
            data = {}
            if r.get("data_json"):
                try:
                    data = json.loads(r["data_json"])
                except:
                    pass
            res.append({
                "id": r["id"],
                "targetHandle": r["target_handle"],
                "senderHandle": r.get("sender_handle"),
                "title": r["title"],
                "body": r["body"],
                "type": r["type"],
                "data": data,
                "isRead": bool(r.get("is_read", 0)),
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None,
                "timestamp": r.get("created_at")
            })
        return res

    @classmethod
    def mark_notification_read(cls, notif_id: str, target_handle: str) -> bool:
        clean = target_handle.replace("@", "").strip().lower()
        return cls.execute("UPDATE notifications SET is_read = 1 WHERE id = ? AND LOWER(target_handle) = ?;", [notif_id, clean])

    @classmethod
    def mark_all_notifications_read(cls, target_handle: str) -> bool:
        clean = target_handle.replace("@", "").strip().lower()
        return cls.execute("UPDATE notifications SET is_read = 1 WHERE LOWER(target_handle) = ?;", [clean])

    # ==========================================
    # ⚙️ USER PREFERENCES & CALL PRIVACY
    # ==========================================

    @classmethod
    def save_user_preferences(
        cls,
        handle: str,
        preferences_dict: Dict[str, Any],
        call_privacy: Optional[str] = None
    ) -> bool:
        clean = handle.replace("@", "").strip().lower()
        now_ts = int(time.time())
        pref_json = json.dumps(preferences_dict)
        call_priv = call_privacy or "everyone"

        sql = """
        INSERT OR REPLACE INTO user_preferences (handle, preferences_json, call_privacy, updated_at)
        VALUES (?, ?, ?, ?);
        """
        return cls.execute(sql, [clean, pref_json, call_priv, now_ts])

    @classmethod
    def get_user_preferences(cls, handle: str) -> Dict[str, Any]:
        clean = handle.replace("@", "").strip().lower()
        rows = cls.query("SELECT * FROM user_preferences WHERE LOWER(handle) = ? LIMIT 1;", [clean])
        if rows and len(rows) > 0:
            r = rows[0]
            prefs = {}
            if r.get("preferences_json"):
                try:
                    prefs = json.loads(r["preferences_json"])
                except:
                    pass
            prefs["callPrivacy"] = r.get("call_privacy", "everyone")
            return prefs
        return {"callPrivacy": "everyone"}


