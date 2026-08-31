import os
import hashlib
import time
from typing import Optional
import firebase_admin
from firebase_admin import credentials, firestore

from config import Config

# Initialize Firebase Admin Client
db = None

try:
    if os.path.exists(Config.FIREBASE_CREDENTIALS_PATH):
        # 1. Load explicit credentials from service account JSON
        cred = credentials.Certificate(Config.FIREBASE_CREDENTIALS_PATH)
        firebase_admin.initialize_app(cred)
        print("[INFO] Firebase Admin initialized via service-account credentials.")
    else:
        # 2. Fallback: Authenticate using Application Default Credentials (ADC)
        firebase_admin.initialize_app()
        print("[WARN] service-account.json not found. Falling back to Application Default Credentials (ADC).")
    
    db = firestore.client()
except Exception as err:
    print(f"[ERROR] CRITICAL: Failed to initialize Firebase Admin SDK: {err}")
    db = None


class FirebaseService:
    """
    Acts as the secure Firebase interface.
    Executes database writes using Server Admin SDK credentials, enabling a complete
    write block on standard client devices.
    """

    @staticmethod
    def _is_db_active() -> bool:
        if db is None:
            print("[WARN] DB Connection is inactive. Call ignored.")
            return False
        return True

    @staticmethod
    def create_post(author_handle: str, content: str, area: str, category: str, image_url: Optional[str] = None) -> bool:
        if not FirebaseService._is_db_active():
            return False
        try:
            posts_ref = db.collection("posts")
            posts_ref.add({
                "authorHandle": author_handle,
                "content": content,
                "imageUrl": image_url,
                "area": area,
                "category": category,
                "createdAt": firestore.SERVER_TIMESTAMP,
                "upvotes": 0,
                "downvotes": 0,
                "commentCount": 0,
                "isEmergency": category == "emergency",
                "userVotes": {},
                "hiddenByMod": False,
                "reporters": [],
                "reportCount": 0
            })
            return True
        except Exception as e:
            print(f"Error creating post in Firestore: {e}")
            return False

    @staticmethod
    def add_comment(post_id: str, author_handle: str, content: str) -> bool:
        if not FirebaseService._is_db_active():
            return False
        try:
            post_ref = db.collection("posts").document(post_id)
            comment_ref = post_ref.collection("comments").document()
            
            batch = db.batch()
            batch.set(comment_ref, {
                "authorHandle": author_handle,
                "content": content,
                "createdAt": firestore.SERVER_TIMESTAMP
            })
            batch.update(post_ref, {
                "commentCount": firestore.Increment(1)
            })
            batch.commit()
            return True
        except Exception as e:
            print(f"Error adding comment in Firestore: {e}")
            return False

    @staticmethod
    def vote_post(post_id: str, user_handle: str, direction: int) -> bool:
        if not FirebaseService._is_db_active():
            return False
        
        post_ref = db.collection("posts").document(post_id)
        vote_ref = post_ref.collection("votes").document(user_handle)
        
        @firestore.transactional
        def run_vote_transaction(transaction, p_ref, v_ref):
            post_snapshot = p_ref.get(transaction=transaction)
            if not post_snapshot.exists:
                return False
                
            vote_snapshot = v_ref.get(transaction=transaction)
            post_data = post_snapshot.to_dict()
            upvotes = post_data.get("upvotes", 0)
            downvotes = post_data.get("downvotes", 0)
            
            previous_vote = 0
            if vote_snapshot.exists:
                previous_vote = vote_snapshot.to_dict().get("direction", 0)
                
            if previous_vote == direction:
                # Cancel previous vote
                if direction == 1:
                    upvotes = max(0, upvotes - 1)
                else:
                    downvotes = max(0, downvotes - 1)
                transaction.delete(v_ref)
            else:
                # Change vote or cast new
                if previous_vote == 1:
                    upvotes = max(0, upvotes - 1)
                elif previous_vote == -1:
                    downvotes = max(0, downvotes - 1)
                    
                if direction == 1:
                    upvotes += 1
                elif direction == -1:
                    downvotes += 1
                
                transaction.set(v_ref, {"direction": direction})
                
            transaction.update(p_ref, {
                "upvotes": upvotes,
                "downvotes": downvotes
            })
            return True

        try:
            transaction = db.transaction()
            return run_vote_transaction(transaction, post_ref, vote_ref)
        except Exception as e:
            print(f"Error casting vote in Firestore: {e}")
            return False

    @staticmethod
    def report_post(post_id: str, reporter_handle: str, reason: str) -> bool:
        if not FirebaseService._is_db_active():
            return False
        
        post_ref = db.collection("posts").document(post_id)
        report_ref = post_ref.collection("reports").document(reporter_handle)
        
        @firestore.transactional
        def run_report_transaction(transaction, p_ref, r_ref):
            post_snapshot = p_ref.get(transaction=transaction)
            if not post_snapshot.exists:
                return False
                
            report_snapshot = r_ref.get(transaction=transaction)
            if report_snapshot.exists:
                # User has already reported this post (satisfies: one actor -> one report per post)
                return True
                
            post_data = post_snapshot.to_dict()
            report_count = post_data.get("reportCount", 0)
            
            # Write detailed report metadata document (§8 report model)
            transaction.set(r_ref, {
                "reporterHandle": reporter_handle,
                "reason": reason,
                "status": "pending",
                "createdAt": firestore.SERVER_TIMESTAMP
            })
            
            # Increment reportCount atomically on the post
            transaction.update(p_ref, {
                "reportCount": report_count + 1
            })
            return True

        try:
            transaction = db.transaction()
            return run_report_transaction(transaction, post_ref, report_ref)
        except Exception as e:
            print(f"Error reporting post in Firestore: {e}")
            return False

    @staticmethod
    def restore_post(post_id: str) -> bool:
        if not FirebaseService._is_db_active():
            return False
        try:
            post_ref = db.collection("posts").document(post_id)
            reports_ref = post_ref.collection("reports")
            docs = reports_ref.get()
            
            batch = db.batch()
            for doc in docs:
                batch.delete(doc.reference)
                
            batch.update(post_ref, {
                "reportCount": 0,
                "hiddenByMod": False
            })
            batch.commit()
            return True
        except Exception as e:
            print(f"Error restoring post in Firestore: {e}")
            return False

    @staticmethod
    def delete_post(post_id: str) -> bool:
        if not FirebaseService._is_db_active():
            return False
        try:
            db.collection("posts").document(post_id).update({
                "deletedAt": firestore.SERVER_TIMESTAMP,
                "hiddenByMod": True
            })
            return True
        except Exception as e:
            print(f"Error soft-deleting post in Firestore: {e}")
            return False

    @staticmethod
    def delete_media(media_id: str) -> bool:
        if not FirebaseService._is_db_active():
            return False
        try:
            db.collection("media").document(media_id).update({
                "deletedAt": firestore.SERVER_TIMESTAMP
            })
            return True
        except Exception as e:
            print(f"Error soft-deleting media in Firestore: {e}")
            return False

    @staticmethod
    def register_media(media_id: str, telegram_file_id: str, size: int, mime_type: str, content_hash: str, storage_provider: str = "telegram") -> bool:
        if not FirebaseService._is_db_active():
            return False
        try:
            db.collection("media").document(media_id).set({
                "mediaId": media_id,
                "telegramFileId": telegram_file_id,
                "telegramMessageId": None,
                "storageProvider": storage_provider,
                "backupObjectKey": None,
                "contentHash": content_hash,
                "size": size,
                "mimeType": mime_type,
                "createdAt": firestore.SERVER_TIMESTAMP,
                "deletedAt": None
            })
            return True
        except Exception as e:
            print(f"Error registering media: {e}")
            return False

    @staticmethod
    def get_media_by_hash(content_hash: str) -> Optional[dict]:
        if not FirebaseService._is_db_active():
            return None
        try:
            docs = db.collection("media").where("contentHash", "==", content_hash).limit(1).get()
            if docs:
                return docs[0].to_dict()
            return None
        except Exception as e:
            print(f"Error checking media hash: {e}")
            return None

    @staticmethod
    def get_media_by_id(media_id: str) -> Optional[dict]:
        if not FirebaseService._is_db_active():
            return None
        try:
            doc = db.collection("media").document(media_id).get()
            if doc.exists:
                return doc.to_dict()
            return None
        except Exception as e:
            print(f"Error fetching media by id: {e}")
            return None

    @staticmethod
    def log_moderator_action(moderator_id: str, role: str, action: str, target: str, reason: str, request_id: str, ip_address: str) -> bool:
        if not FirebaseService._is_db_active():
            return False
        try:
            logs_ref = db.collection("moderation_logs")
            prev_docs = logs_ref.order_by("timestamp", direction=firestore.Query.DESCENDING).limit(1).get()
            
            previous_log_hash = "genesis_hash_0000000000000000"
            if prev_docs:
                previous_log_hash = prev_docs[0].to_dict().get("currentLogHash", previous_log_hash)
                
            log_id = hashlib.sha256(f"{moderator_id}:{action}:{time.time()}".encode()).hexdigest()[:16]
            ip_hash = hashlib.sha256(ip_address.encode()).hexdigest()
            timestamp_sec = int(time.time())
            
            raw_data = f"{log_id}:{moderator_id}:{role}:{action}:{target}:{reason}:{timestamp_sec}:{request_id}:{ip_hash}:{previous_log_hash}"
            current_log_hash = hashlib.sha256(raw_data.encode()).hexdigest()
            
            logs_ref.document(log_id).set({
                "logId": log_id,
                "moderatorId": moderator_id,
                "role": role,
                "action": action,
                "target": target,
                "reason": reason,
                "timestamp": firestore.SERVER_TIMESTAMP,
                "requestId": request_id,
                "ipHash": ip_hash,
                "previousLogHash": previous_log_hash,
                "currentLogHash": current_log_hash
            })
            return True
        except Exception as e:
            print(f"Error writing moderator audit log: {e}")
            return False
