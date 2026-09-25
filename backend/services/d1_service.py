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
            """,
            """
            CREATE TABLE IF NOT EXISTS join_requests (
                id TEXT PRIMARY KEY,
                community_id TEXT NOT NULL,
                user_handle TEXT NOT NULL,
                status TEXT DEFAULT 'pending',
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                FOREIGN KEY (community_id) REFERENCES communities(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_jr_comm ON join_requests(community_id, status);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_jr_user ON join_requests(user_handle, status);
            """,
            """
            CREATE TABLE IF NOT EXISTS community_message_deletions (
                message_id TEXT NOT NULL,
                user_handle TEXT NOT NULL,
                deleted_at INTEGER DEFAULT (strftime('%s', 'now')),
                PRIMARY KEY (message_id, user_handle)
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_cmd_user ON community_message_deletions(user_handle);
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
            "ALTER TABLE communities ADD COLUMN visibility TEXT DEFAULT 'public';",
            "ALTER TABLE communities ADD COLUMN username TEXT;",
            "ALTER TABLE communities ADD COLUMN invite_link TEXT;",
            "ALTER TABLE communities ADD COLUMN settings_json TEXT DEFAULT '{}';",
            "ALTER TABLE communities ADD COLUMN owner_handle TEXT;",
            "ALTER TABLE community_members ADD COLUMN admin_permissions_json TEXT DEFAULT '{}';",
            "ALTER TABLE community_members ADD COLUMN muted_until INTEGER DEFAULT 0;",
            "ALTER TABLE community_members ADD COLUMN is_archived INTEGER DEFAULT 0;",
            "ALTER TABLE community_messages ADD COLUMN pinned INTEGER DEFAULT 0;",
            "ALTER TABLE community_messages ADD COLUMN is_system INTEGER DEFAULT 0;",
            "ALTER TABLE community_messages ADD COLUMN edited_at INTEGER;",
            "ALTER TABLE community_messages ADD COLUMN deleted_for_everyone INTEGER DEFAULT 0;",
            "ALTER TABLE community_messages ADD COLUMN deleted_by TEXT;",
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
    def check_community_username_available(cls, username: str) -> bool:
        clean = username.strip().lower().lstrip('@')
        if not clean or len(clean) < 3 or len(clean) > 30:
            return False
        import re
        if not re.match(r'^[a-zA-Z0-9_]+$', clean):
            return False
        rows = cls.query("SELECT id FROM communities WHERE LOWER(username) = ? LIMIT 1;", [clean])
        return not (rows and len(rows) > 0)

    @classmethod
    def create_community(
        cls,
        name: str,
        description: str,
        admin_handle: str,
        is_channel: bool = False,
        visibility: str = "public",
        username: Optional[str] = None,
        invite_link: Optional[str] = None,
        settings: Optional[Dict[str, Any]] = None,
        image_url: Optional[str] = None,
        initial_members: Optional[List[str]] = None
    ) -> Optional[str]:
        comm_id = str(uuid.uuid4())
        now_ts = int(time.time())
        clean_admin = admin_handle.replace("@", "").strip()
        clean_visibility = "private" if visibility.lower() == "private" else "public"
        clean_username = username.strip().lower().lstrip('@') if (username and clean_visibility == "public") else None

        if clean_username and not cls.check_community_username_available(clean_username):
            return None

        clean_invite = invite_link.strip() if invite_link else (uuid.uuid4().hex[:8] if clean_visibility == "private" else None)

        default_settings = {
            "who_can_send": "admins_only" if is_channel else "all",
            "media_permissions": {
                "text": True,
                "photo": True,
                "video": True,
                "file": True,
                "call": True
            },
            "approve_new_members": False,
            "delete_mode": "everyone"
        }
        if settings:
            default_settings.update(settings)
        if is_channel:
            default_settings["who_can_send"] = "admins_only"

        settings_json = json.dumps(default_settings)
        member_count = 1 + (len(initial_members) if initial_members else 0)

        sql = """
        INSERT INTO communities (
            id, name, description, is_channel, admin_handle, owner_handle, visibility, username, invite_link, settings_json, member_count, image_url, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        if cls.execute(sql, [
            comm_id, name.strip(), description.strip(), 1 if is_channel else 0,
            clean_admin, clean_admin, clean_visibility, clean_username, clean_invite,
            settings_json, member_count, image_url, now_ts, now_ts
        ]):
            admin_perms = json.dumps({
                "can_add_members": True,
                "can_remove_members": True,
                "can_edit_info": True,
                "can_pin_messages": True,
                "can_delete_messages": True,
                "can_manage_admins": True
            })
            member_id = f"{comm_id}_{clean_admin.lower()}"
            cls.execute(
                "INSERT OR REPLACE INTO community_members (id, community_id, user_handle, role, admin_permissions_json, muted_until, is_archived, last_read_at, joined_at) VALUES (?, ?, ?, 'owner', ?, 0, 0, ?, ?);",
                [member_id, comm_id, clean_admin, admin_perms, now_ts, now_ts]
            )

            if initial_members:
                for m_handle in initial_members:
                    clean_m = m_handle.replace("@", "").strip()
                    if clean_m and clean_m.lower() != clean_admin.lower():
                        m_id = f"{comm_id}_{clean_m.lower()}"
                        cls.execute(
                            "INSERT OR IGNORE INTO community_members (id, community_id, user_handle, role, admin_permissions_json, muted_until, is_archived, last_read_at, joined_at) VALUES (?, ?, ?, 'member', '{}', 0, 0, ?, ?);",
                            [m_id, comm_id, clean_m, now_ts, now_ts]
                        )

            system_text = f"{clean_admin} created this {'channel' if is_channel else 'group'}"
            cls.send_community_message(
                community_id=comm_id,
                author_handle="System",
                content=system_text,
                message_type="system"
            )
            return comm_id
        return None

    @classmethod
    def get_communities(
        cls,
        user_handle: Optional[str] = None,
        filter_mode: str = "all",
        search_query: Optional[str] = None,
        type_filter: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        clean_user = user_handle.replace("@", "").strip().lower() if user_handle else None
        now_ts = int(time.time())

        if filter_mode == "joined":
            if not clean_user:
                return []
            sql = """
            SELECT c.*, m.role as my_role, m.muted_until as my_muted_until, m.is_archived as my_is_archived, m.last_read_at as my_last_read_at,
                   (SELECT COUNT(*) FROM community_messages msg WHERE msg.community_id = c.id AND msg.created_at > COALESCE(m.last_read_at, 0) AND msg.deleted_at IS NULL AND LOWER(msg.author_handle) != ?) as unread_count,
                   (SELECT content FROM community_messages msg WHERE msg.community_id = c.id AND msg.deleted_at IS NULL ORDER BY msg.created_at DESC LIMIT 1) as last_message,
                   (SELECT created_at FROM community_messages msg WHERE msg.community_id = c.id AND msg.deleted_at IS NULL ORDER BY msg.created_at DESC LIMIT 1) as last_message_at,
                   (SELECT author_handle FROM community_messages msg WHERE msg.community_id = c.id AND msg.deleted_at IS NULL ORDER BY msg.created_at DESC LIMIT 1) as last_sender_handle
            FROM communities c
            INNER JOIN community_members m ON c.id = m.community_id
            WHERE LOWER(m.user_handle) = ?
            """
            params: List[Any] = [clean_user, clean_user]
            if type_filter == "group":
                sql += " AND c.is_channel = 0"
            elif type_filter == "channel":
                sql += " AND c.is_channel = 1"

            if search_query and len(search_query.strip()) >= 2:
                q = f"%{search_query.strip().lower()}%"
                sql += " AND (LOWER(c.name) LIKE ? OR LOWER(COALESCE(c.username, '')) LIKE ? OR LOWER(COALESCE(c.description, '')) LIKE ?)"
                params.extend([q, q, q])

            sql += " ORDER BY COALESCE(last_message_at, c.created_at) DESC;"
            rows = cls.query(sql, params) or []

        elif filter_mode == "discover" or filter_mode == "directory":
            sql = """
            SELECT c.*, NULL as my_role, 0 as my_muted_until, 0 as my_is_archived, 0 as unread_count,
                   NULL as last_message, NULL as last_message_at, NULL as last_sender_handle
            FROM communities c
            WHERE c.visibility = 'public'
            """
            params = []
            if clean_user:
                sql += " AND c.id NOT IN (SELECT community_id FROM community_members WHERE LOWER(user_handle) = ?)"
                params.append(clean_user)

            if type_filter == "group":
                sql += " AND c.is_channel = 0"
            elif type_filter == "channel":
                sql += " AND c.is_channel = 1"

            if search_query and len(search_query.strip()) >= 2:
                q = f"%{search_query.strip().lower()}%"
                sql += " AND (LOWER(c.name) LIKE ? OR LOWER(COALESCE(c.username, '')) LIKE ? OR LOWER(COALESCE(c.description, '')) LIKE ?)"
                params.extend([q, q, q])

            sql += " ORDER BY c.member_count DESC, c.created_at DESC LIMIT 50;"
            rows = cls.query(sql, params) or []

        else: # filter_mode == "all"
            if clean_user:
                return cls.get_communities(user_handle=clean_user, filter_mode="joined", search_query=search_query, type_filter=type_filter)
            else:
                return cls.get_communities(user_handle=None, filter_mode="discover", search_query=search_query, type_filter=type_filter)

        res = []
        for r in rows:
            settings_obj = {}
            if r.get("settings_json"):
                try:
                    settings_obj = json.loads(r["settings_json"])
                except:
                    pass

            muted_until = r.get("my_muted_until") or 0
            is_muted = (muted_until == -1) or (muted_until > now_ts)
            is_archived = bool(r.get("my_is_archived", 0))

            res.append({
                "id": r["id"],
                "name": r["name"],
                "description": r.get("description", ""),
                "isChannel": bool(r.get("is_channel", 0)),
                "adminHandle": r.get("owner_handle") or r["admin_handle"],
                "ownerHandle": r.get("owner_handle") or r["admin_handle"],
                "visibility": r.get("visibility", "public"),
                "username": r.get("username"),
                "inviteLink": r.get("invite_link"),
                "settings": settings_obj,
                "memberCount": r.get("member_count", 1),
                "imageUrl": r.get("image_url"),
                "myRole": r.get("my_role") or "member",
                "isMuted": is_muted,
                "mutedUntil": muted_until,
                "isArchived": is_archived,
                "unreadCount": r.get("unread_count", 0) or 0,
                "lastMessage": r.get("last_message"),
                "lastMessageAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["last_message_at"])) if r.get("last_message_at") else None,
                "lastSenderHandle": r.get("last_sender_handle"),
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None,
                "updatedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["updated_at"])) if r.get("updated_at") else None
            })
        return res

    @classmethod
    def get_community_by_id(cls, community_id: str, user_handle: Optional[str] = None) -> Optional[Dict[str, Any]]:
        sql = "SELECT * FROM communities WHERE id = ? LIMIT 1;"
        rows = cls.query(sql, [community_id])
        if not rows or len(rows) == 0:
            return None
        r = rows[0]
        now_ts = int(time.time())

        my_role = None
        my_muted_until = 0
        my_is_archived = False
        my_permissions = {}

        if user_handle:
            clean_u = user_handle.replace("@", "").strip().lower()
            m_rows = cls.query("SELECT role, admin_permissions_json, muted_until, is_archived FROM community_members WHERE community_id = ? AND LOWER(user_handle) = ? LIMIT 1;", [community_id, clean_u])
            if m_rows and len(m_rows) > 0:
                mr = m_rows[0]
                my_role = mr.get("role")
                my_muted_until = mr.get("muted_until") or 0
                my_is_archived = bool(mr.get("is_archived", 0))
                if mr.get("admin_permissions_json"):
                    try:
                        my_permissions = json.loads(mr["admin_permissions_json"])
                    except:
                        pass

        settings_obj = {}
        if r.get("settings_json"):
            try:
                settings_obj = json.loads(r["settings_json"])
            except:
                pass

        is_muted = (my_muted_until == -1) or (my_muted_until > now_ts)

        return {
            "id": r["id"],
            "name": r["name"],
            "description": r.get("description", ""),
            "isChannel": bool(r.get("is_channel", 0)),
            "adminHandle": r.get("owner_handle") or r["admin_handle"],
            "ownerHandle": r.get("owner_handle") or r["admin_handle"],
            "visibility": r.get("visibility", "public"),
            "username": r.get("username"),
            "inviteLink": r.get("invite_link"),
            "settings": settings_obj,
            "memberCount": r.get("member_count", 1),
            "imageUrl": r.get("image_url"),
            "myRole": my_role,
            "myPermissions": my_permissions,
            "isMuted": is_muted,
            "mutedUntil": my_muted_until,
            "isArchived": my_is_archived,
            "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None,
            "updatedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["updated_at"])) if r.get("updated_at") else None
        }

    @classmethod
    def get_community_by_username_or_link(cls, identifier: str) -> Optional[Dict[str, Any]]:
        clean = identifier.strip().lstrip('@').lower()
        sql = "SELECT id FROM communities WHERE LOWER(username) = ? OR LOWER(invite_link) = ? LIMIT 1;"
        rows = cls.query(sql, [clean, clean])
        if rows and len(rows) > 0:
            return cls.get_community_by_id(rows[0]["id"])
        return None

    @classmethod
    def update_community_settings(
        cls,
        community_id: str,
        user_handle: str,
        name: Optional[str] = None,
        description: Optional[str] = None,
        image_url: Optional[str] = None,
        visibility: Optional[str] = None,
        username: Optional[str] = None,
        settings: Optional[Dict[str, Any]] = None
    ) -> bool:
        clean_user = user_handle.replace("@", "").strip().lower()
        comm = cls.get_community_by_id(community_id, user_handle=clean_user)
        if not comm:
            return False

        # Verify user is owner or admin with can_edit_info
        role = comm.get("myRole")
        perms = comm.get("myPermissions", {})
        if role != "owner" and not (role == "admin" and perms.get("can_edit_info", True)):
            return False

        updates = ["updated_at = ?"]
        params: List[Any] = [int(time.time())]

        if name:
            updates.append("name = ?")
            params.append(name.strip())
        if description is not None:
            updates.append("description = ?")
            params.append(description.strip())
        if image_url is not None:
            updates.append("image_url = ?")
            params.append(image_url.strip())
        if visibility:
            clean_vis = "private" if visibility.lower() == "private" else "public"
            updates.append("visibility = ?")
            params.append(clean_vis)
        if username is not None:
            clean_u = username.strip().lower().lstrip('@')
            if clean_u:
                if not cls.check_community_username_available(clean_u):
                    current_u = (comm.get("username") or "").lower()
                    if clean_u != current_u:
                        return False
                updates.append("username = ?")
                params.append(clean_u)
            else:
                updates.append("username = NULL")
        if settings is not None:
            current_settings = comm.get("settings", {})
            current_settings.update(settings)
            updates.append("settings_json = ?")
            params.append(json.dumps(current_settings))

        params.append(community_id)
        sql = f"UPDATE communities SET {', '.join(updates)} WHERE id = ?;"
        return cls.execute(sql, params)

    @classmethod
    def join_community(cls, community_id: str, user_handle: str, invite_code: Optional[str] = None) -> Dict[str, Any]:
        clean_user = user_handle.replace("@", "").strip()
        if not clean_user:
            return {"success": False, "error": "Invalid user handle."}

        comm = cls.get_community_by_id(community_id)
        if not comm:
            return {"success": False, "error": "Community not found"}

        member_id = f"{community_id}_{clean_user.lower()}"
        existing = cls.query(
            "SELECT id FROM community_members WHERE id = ? OR (community_id = ? AND LOWER(user_handle) = ?) LIMIT 1;",
            [member_id, community_id, clean_user.lower()]
        )
        if existing and len(existing) > 0:
            return {"success": True, "status": "joined", "message": "Already a member"}

        settings = comm.get("settings", {})
        approve_required = settings.get("approve_new_members", False)

        now_ts = int(time.time())

        # If approval is required, create pending join request
        if approve_required:
            req_id = str(uuid.uuid4())
            sql = "INSERT INTO join_requests (id, community_id, user_handle, status, created_at) VALUES (?, ?, ?, 'pending', ?);"
            if cls.execute(sql, [req_id, community_id, clean_user, now_ts]):
                return {"success": True, "status": "pending", "message": "Join request submitted for admin review."}
            return {"success": False, "error": "Failed to submit join request"}

        # Instant join
        sql = "INSERT OR REPLACE INTO community_members (id, community_id, user_handle, role, admin_permissions_json, muted_until, is_archived, last_read_at, joined_at) VALUES (?, ?, ?, 'member', '{}', 0, 0, ?, ?);"
        if cls.execute(sql, [member_id, community_id, clean_user, now_ts, now_ts]):
            cls.execute("UPDATE communities SET member_count = (SELECT COUNT(*) FROM community_members WHERE community_id = ?) WHERE id = ?;", [community_id, community_id])
            
            # System message
            comm_type = "channel" if comm.get("isChannel") else "group"
            cls.send_community_message(
                community_id=community_id,
                author_handle="System",
                content=f"{clean_user} joined the {comm_type}",
                message_type="system"
            )
            return {"success": True, "status": "joined", "message": "Joined community successfully."}

        return {"success": False, "error": "Failed to join community"}

    @classmethod
    def leave_community(cls, community_id: str, user_handle: str) -> Dict[str, Any]:
        clean_user = user_handle.replace("@", "").strip()
        comm = cls.get_community_by_id(community_id)
        if not comm:
            return {"success": False, "error": "Community not found"}

        owner_handle = (comm.get("ownerHandle") or comm.get("adminHandle") or "").lower()
        if owner_handle == clean_user.lower() and comm.get("memberCount", 1) > 1:
            return {"success": False, "error": "You must transfer ownership before leaving the community."}

        cls.execute("DELETE FROM community_members WHERE community_id = ? AND LOWER(user_handle) = ?;", [community_id, clean_user.lower()])
        cls.execute("UPDATE communities SET member_count = MAX(1, member_count - 1) WHERE id = ?;", [community_id])

        comm_type = "channel" if comm.get("isChannel") else "group"
        cls.send_community_message(
            community_id=community_id,
            author_handle="System",
            content=f"{clean_user} left the {comm_type}",
            message_type="system"
        )
        return {"success": True, "message": "Left community successfully."}

    @classmethod
    def get_join_requests(cls, community_id: str, admin_handle: str) -> List[Dict[str, Any]]:
        clean_admin = admin_handle.replace("@", "").strip().lower()
        comm = cls.get_community_by_id(community_id, user_handle=clean_admin)
        if not comm:
            return []
        role = comm.get("myRole")
        perms = comm.get("myPermissions", {})
        if role != "owner" and not (role == "admin" and perms.get("can_add_members", True)):
            return []

        sql = """
        SELECT r.id, r.community_id, r.user_handle, r.status, r.created_at, u.avatar_url, u.reputation
        FROM join_requests r
        LEFT JOIN users u ON LOWER(r.user_handle) = LOWER(u.handle)
        WHERE r.community_id = ? AND r.status = 'pending'
        ORDER BY r.created_at ASC;
        """
        rows = cls.query(sql, [community_id]) or []
        res = []
        for r in rows:
            res.append({
                "id": r["id"],
                "communityId": r["community_id"],
                "userHandle": r["user_handle"],
                "status": r["status"],
                "avatarUrl": r.get("avatar_url") or "",
                "reputation": r.get("reputation") or 0,
                "createdAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["created_at"])) if r.get("created_at") else None
            })
        return res

    @classmethod
    def respond_join_request(cls, community_id: str, request_id: str, admin_handle: str, approve: bool) -> bool:
        clean_admin = admin_handle.replace("@", "").strip().lower()
        comm = cls.get_community_by_id(community_id, user_handle=clean_admin)
        if not comm:
            return False
        role = comm.get("myRole")
        perms = comm.get("myPermissions", {})
        if role != "owner" and not (role == "admin" and perms.get("can_add_members", True)):
            return False

        req_rows = cls.query("SELECT user_handle FROM join_requests WHERE id = ? AND community_id = ? AND status = 'pending' LIMIT 1;", [request_id, community_id])
        if not req_rows or len(req_rows) == 0:
            return False
        target_handle = req_rows[0]["user_handle"]
        now_ts = int(time.time())

        if approve:
            cls.execute("UPDATE join_requests SET status = 'approved' WHERE id = ?;", [request_id])
            member_id = f"{community_id}_{target_handle.lower()}"
            cls.execute("INSERT OR REPLACE INTO community_members (id, community_id, user_handle, role, admin_permissions_json, muted_until, is_archived, last_read_at, joined_at) VALUES (?, ?, ?, 'member', '{}', 0, 0, ?, ?);", [member_id, community_id, target_handle, now_ts, now_ts])
            cls.execute("UPDATE communities SET member_count = member_count + 1 WHERE id = ?;", [community_id])
            comm_type = "channel" if comm.get("isChannel") else "group"
            cls.send_community_message(
                community_id=community_id,
                author_handle="System",
                content=f"{target_handle} was approved to join the {comm_type}",
                message_type="system"
            )
        else:
            cls.execute("UPDATE join_requests SET status = 'declined' WHERE id = ?;", [request_id])
        return True

    @classmethod
    def get_community_members(cls, community_id: str) -> List[Dict[str, Any]]:
        sql = """
        SELECT m.user_handle, m.role, m.admin_permissions_json, m.joined_at, u.avatar_url, u.reputation
        FROM community_members m
        LEFT JOIN users u ON LOWER(m.user_handle) = LOWER(u.handle)
        WHERE m.community_id = ?
        ORDER BY 
            CASE m.role 
                WHEN 'owner' THEN 1 
                WHEN 'admin' THEN 2 
                ELSE 3 
            END ASC,
            m.joined_at ASC;
        """
        rows = cls.query(sql, [community_id]) or []
        res = []
        for r in rows:
            perms = {}
            if r.get("admin_permissions_json"):
                try:
                    perms = json.loads(r["admin_permissions_json"])
                except:
                    pass
            res.append({
                "userHandle": r["user_handle"],
                "role": r["role"],
                "permissions": perms,
                "avatarUrl": r.get("avatar_url") or "",
                "reputation": r.get("reputation") or 0,
                "joinedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["joined_at"])) if r.get("joined_at") else None
            })
        return res

    @classmethod
    def update_member_role_and_permissions(
        cls,
        community_id: str,
        admin_handle: str,
        target_handle: str,
        role: str,
        permissions: Optional[Dict[str, Any]] = None
    ) -> bool:
        clean_admin = admin_handle.replace("@", "").strip().lower()
        clean_target = target_handle.replace("@", "").strip().lower()
        clean_role = role.strip().lower()

        # SECURITY: Strictly reject setting role to 'owner' or anything other than 'admin' or 'member'
        if clean_role not in ("admin", "member"):
            return False

        # Cannot modify own role/permissions via this endpoint
        if clean_admin == clean_target:
            return False

        comm = cls.get_community_by_id(community_id, user_handle=clean_admin)
        if not comm:
            return False

        my_role = comm.get("myRole")
        my_perms = comm.get("myPermissions", {})
        if my_role != "owner" and not (my_role == "admin" and my_perms.get("can_manage_admins", False)):
            return False

        owner_handle = (comm.get("ownerHandle") or comm.get("adminHandle") or "").lower()
        if clean_target == owner_handle:
            return False

        # Check target's existing role in database
        target_rows = cls.query(
            "SELECT role FROM community_members WHERE community_id = ? AND LOWER(user_handle) = ? LIMIT 1;",
            [community_id, clean_target]
        )
        if not target_rows or len(target_rows) == 0:
            return False
        if (target_rows[0].get("role") or "").lower() == "owner":
            return False

        perms_json = json.dumps(permissions) if permissions else ("{}" if clean_role == "member" else json.dumps({
            "can_add_members": True,
            "can_remove_members": True,
            "can_edit_info": True,
            "can_pin_messages": True,
            "can_delete_messages": True,
            "can_manage_admins": False
        }))

        sql = "UPDATE community_members SET role = ?, admin_permissions_json = ? WHERE community_id = ? AND LOWER(user_handle) = ?;"
        return cls.execute(sql, [clean_role, perms_json, community_id, clean_target])

    @classmethod
    def transfer_community_ownership(cls, community_id: str, current_owner_handle: str, new_owner_handle: str) -> bool:
        clean_owner = current_owner_handle.replace("@", "").strip().lower()
        clean_new = new_owner_handle.replace("@", "").strip()
        comm = cls.get_community_by_id(community_id, user_handle=clean_owner)
        if not comm or comm.get("myRole") != "owner":
            return False

        # Update community owner_handle
        cls.execute("UPDATE communities SET owner_handle = ?, admin_handle = ? WHERE id = ?;", [clean_new, clean_new, community_id])
        # Promote new owner
        cls.execute("UPDATE community_members SET role = 'owner' WHERE community_id = ? AND LOWER(user_handle) = ?;", [community_id, clean_new.lower()])
        # Demote old owner to admin
        cls.execute("UPDATE community_members SET role = 'admin' WHERE community_id = ? AND LOWER(user_handle) = ?;", [community_id, clean_owner])
        
        cls.send_community_message(
            community_id=community_id,
            author_handle="System",
            content=f"{clean_owner} transferred community ownership to {clean_new}",
            message_type="system"
        )
        return True

    @classmethod
    def remove_community_member(cls, community_id: str, admin_handle: str, target_handle: str) -> bool:
        clean_admin = admin_handle.replace("@", "").strip().lower()
        clean_target = target_handle.replace("@", "").strip()
        comm = cls.get_community_by_id(community_id, user_handle=clean_admin)
        if not comm:
            return False

        my_role = comm.get("myRole")
        my_perms = comm.get("myPermissions", {})

        # Find target member's role
        target_rows = cls.query(
            "SELECT role FROM community_members WHERE community_id = ? AND LOWER(user_handle) = ? LIMIT 1;",
            [community_id, clean_target.lower()]
        )
        if not target_rows or len(target_rows) == 0:
            return False
        target_role = (target_rows[0].get("role") or "member").lower()

        # Cannot remove the owner under any circumstances
        owner_handle = (comm.get("ownerHandle") or comm.get("adminHandle") or "").lower()
        if target_role == "owner" or clean_target.lower() == owner_handle:
            return False

        # Admin-vs-Admin removal: ONLY Owner OR Admin with can_manage_admins can remove another Admin
        if target_role == "admin":
            if my_role != "owner" and not (my_role == "admin" and my_perms.get("can_manage_admins", False)):
                return False

        # Regular member removal: Owner OR Admin with can_remove_members
        if target_role == "member":
            if my_role != "owner" and not (my_role == "admin" and my_perms.get("can_remove_members", True)):
                return False

        cls.execute("DELETE FROM community_members WHERE community_id = ? AND LOWER(user_handle) = ?;", [community_id, clean_target.lower()])
        cls.execute("UPDATE communities SET member_count = MAX(1, member_count - 1) WHERE id = ?;", [community_id])

        cls.send_community_message(
            community_id=community_id,
            author_handle="System",
            content=f"{clean_target} was removed from the community",
            message_type="system"
        )
        return True

    @classmethod
    def mute_community(cls, community_id: str, user_handle: str, muted_until: int) -> bool:
        clean_user = user_handle.replace("@", "").strip().lower()
        member_id = f"{community_id}_{clean_user}"
        return cls.execute("UPDATE community_members SET muted_until = ? WHERE id = ?;", [muted_until, member_id])

    @classmethod
    def archive_community(cls, community_id: str, user_handle: str, is_archived: bool) -> bool:
        clean_user = user_handle.replace("@", "").strip().lower()
        member_id = f"{community_id}_{clean_user}"
        return cls.execute("UPDATE community_members SET is_archived = ? WHERE id = ?;", [1 if is_archived else 0, member_id])

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
        clean_author = author_handle.replace("@", "").strip()
        now_ts = int(time.time())

        # If not a system message, validate sender permissions
        if message_type != "system":
            comm = cls.get_community_by_id(community_id, user_handle=clean_author)
            if not comm:
                return None

            user_role = comm.get("myRole")
            if not user_role:
                return None # Must be a member to post

            settings = comm.get("settings", {})
            is_channel = comm.get("isChannel", False)

            # Channels: only admin and owner can post
            if is_channel and user_role not in ("owner", "admin"):
                return None

            # Groups: check who_can_send
            who_can_send = settings.get("who_can_send", "all")
            if who_can_send == "admins_only" and user_role not in ("owner", "admin"):
                return None

            # Check media permissions
            media_perms = settings.get("media_permissions", {})
            if message_type in ("image", "image_group") and not media_perms.get("photo", True) and user_role not in ("owner", "admin"):
                return None
            if message_type == "video" and not media_perms.get("video", True) and user_role not in ("owner", "admin"):
                return None
            if message_type == "file" and not media_perms.get("file", True) and user_role not in ("owner", "admin"):
                return None

        msg_id = str(uuid.uuid4())
        media_json = json.dumps(media_urls) if media_urls else None

        sql = """
        INSERT INTO community_messages (
            id, community_id, author_handle, content, image_url, media_urls_json, message_type, reactions_json, pinned, is_system, created_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, '{}', 0, ?, ?
        );
        """
        is_sys_int = 1 if message_type == "system" else 0
        if cls.execute(sql, [msg_id, community_id, clean_author, content, image_url, media_json, message_type, is_sys_int, now_ts]):
            cls.execute("UPDATE communities SET updated_at = ? WHERE id = ?;", [now_ts, community_id])
            return msg_id
        return None

    @classmethod
    def edit_community_message(cls, community_id: str, message_id: str, author_handle: str, new_content: str) -> bool:
        clean_author = author_handle.replace("@", "").strip().lower()
        now_ts = int(time.time())

        # Check message exists and is authored by user within 48h (48 * 3600 = 172800)
        rows = cls.query("SELECT author_handle, created_at, deleted_at FROM community_messages WHERE id = ? AND community_id = ? LIMIT 1;", [message_id, community_id])
        if not rows or len(rows) == 0:
            return False
        msg = rows[0]
        if msg.get("deleted_at") or (msg.get("author_handle") or "").lower() != clean_author:
            return False
        created_at = msg.get("created_at") or 0
        if (now_ts - created_at) > 172800:
            return False # Past 48 hours

        sql = "UPDATE community_messages SET content = ?, edited_at = ? WHERE id = ?;"
        return cls.execute(sql, [new_content.strip(), now_ts, message_id])

    @classmethod
    def delete_community(cls, community_id: str, user_handle: str) -> bool:
        clean_user = user_handle.replace("@", "").strip().lower()
        comm = cls.get_community_by_id(community_id, user_handle=clean_user)
        if not comm:
            return False
        if comm.get("myRole") != "owner":
            return False

        cls.execute("DELETE FROM join_requests WHERE community_id = ?;", [community_id])
        cls.execute("DELETE FROM community_messages WHERE community_id = ?;", [community_id])
        cls.execute("DELETE FROM community_members WHERE community_id = ?;", [community_id])
        return cls.execute("DELETE FROM communities WHERE id = ?;", [community_id])

    @classmethod
    def regenerate_community_invite_link(cls, community_id: str, admin_handle: str) -> Optional[str]:
        clean_admin = admin_handle.replace("@", "").strip().lower()
        comm = cls.get_community_by_id(community_id, user_handle=clean_admin)
        if not comm:
            return None
        my_role = comm.get("myRole")
        my_perms = comm.get("myPermissions", {})
        if my_role != "owner" and not (my_role == "admin" and my_perms.get("can_edit_info", True)):
            return None

        new_token = f"join_{uuid.uuid4().hex[:10]}"
        now_ts = int(time.time())
        sql = "UPDATE communities SET invite_link = ?, updated_at = ? WHERE id = ?;"
        if cls.execute(sql, [new_token, now_ts, community_id]):
            return new_token
        return None

    @classmethod
    def delete_community_message(cls, community_id: str, message_id: str, user_handle: str, mode: str = "everyone") -> bool:
        clean_user = user_handle.replace("@", "").strip().lower()
        now_ts = int(time.time())

        rows = cls.query("SELECT author_handle FROM community_messages WHERE id = ? AND community_id = ? LIMIT 1;", [message_id, community_id])
        if not rows or len(rows) == 0:
            return False
        author = rows[0].get("author_handle", "").lower()

        if mode == "for_me":
            sql = "INSERT OR REPLACE INTO community_message_deletions (message_id, user_handle, deleted_at) VALUES (?, ?, ?);"
            return cls.execute(sql, [message_id, clean_user, now_ts])

        comm = cls.get_community_by_id(community_id, user_handle=clean_user)
        if not comm:
            return False
        my_role = comm.get("myRole")
        my_perms = comm.get("myPermissions", {})

        is_author = (author == clean_user)
        is_mod = (my_role == "owner") or (my_role == "admin" and my_perms.get("can_delete_messages", True))

        if not is_author and not is_mod:
            return False

        # Admin cannot delete owner's message
        owner_handle = (comm.get("ownerHandle") or "").lower()
        if not is_author and author == owner_handle and my_role != "owner":
            return False

        settings = comm.get("settings", {})
        del_mode = settings.get("delete_mode", "tombstone")

        if comm.get("isChannel") or del_mode == "silent":
            # Hard delete
            sql = "UPDATE community_messages SET deleted_at = ? WHERE id = ?;"
            return cls.execute(sql, [now_ts, message_id])
        else:
            # Group tombstone for everyone
            sql = "UPDATE community_messages SET deleted_for_everyone = 1, deleted_by = ?, content = 'This message was deleted' WHERE id = ?;"
            return cls.execute(sql, [clean_user, message_id])

    @classmethod
    def pin_community_message(cls, community_id: str, message_id: str, admin_handle: str, pin: bool) -> bool:
        clean_admin = admin_handle.replace("@", "").strip().lower()
        comm = cls.get_community_by_id(community_id, user_handle=clean_admin)
        if not comm:
            return False
        my_role = comm.get("myRole")
        my_perms = comm.get("myPermissions", {})
        if my_role != "owner" and not (my_role == "admin" and my_perms.get("can_pin_messages", True)):
            return False

        sql = "UPDATE community_messages SET pinned = ? WHERE id = ? AND community_id = ?;"
        return cls.execute(sql, [1 if pin else 0, message_id, community_id])

    @classmethod
    def get_community_messages(
        cls,
        community_id: str,
        user_handle: Optional[str] = None,
        limit: int = 50,
        before_ts: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        clean_user = user_handle.replace("@", "").strip().lower() if user_handle else None
        conditions = ["community_id = ?", "deleted_at IS NULL"]
        params: List[Any] = [community_id]

        if clean_user:
            conditions.append("id NOT IN (SELECT message_id FROM community_message_deletions WHERE LOWER(user_handle) = ?)")
            params.append(clean_user)

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
                "pinned": bool(r.get("pinned", 0)),
                "isSystem": bool(r.get("is_system", 0)),
                "editedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(r["edited_at"])) if r.get("edited_at") else None,
                "deletedForEveryone": bool(r.get("deleted_for_everyone", 0)),
                "deletedBy": r.get("deleted_by"),
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


