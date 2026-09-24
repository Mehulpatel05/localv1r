import requests
from typing import Optional, List, Dict, Any
from config import Config

class D1Service:
    """
    Cloudflare D1 Distributed SQL Database Service.
    Interacts with Cloudflare D1 via the Cloudflare REST API.
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
    def batch(cls, statements: List[Dict[str, Any]]) -> bool:
        """
        Executes multiple SQL statements in a single batch transaction.
        Each statement is a dict: {"sql": str, "params": list}
        """
        try:
            # D1 allows batch execution by sending an array or semicolon separated SQL
            res = requests.post(
                cls._get_api_url(),
                headers=cls._get_headers(),
                json=statements,
                timeout=30
            )
            data = res.json()
            return bool(res.status_code == 200 and data.get("success"))
        except Exception as e:
            print(f"[D1Service] Batch error: {e}")
            return False

    @classmethod
    def init_schema(cls) -> bool:
        """
        Initializes the schema tables in Cloudflare D1 for Nearhood / Vadodara Local.
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
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER DEFAULT (strftime('%s', 'now'))
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

        success = True
        for q in schema_queries:
            st_success = cls.execute(q.strip())
            if not st_success:
                success = False
        return success
