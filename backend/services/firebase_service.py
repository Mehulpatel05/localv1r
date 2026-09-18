import os
import json
import hashlib
import hmac
import time
from typing import Optional
import firebase_admin
from firebase_admin import credentials, firestore

from config import Config

# Initialize Firebase Admin Client
db = None

try:
    cred_json = os.getenv("GOOGLE_APPLICATION_CREDENTIALS_JSON")
    if cred_json:
        # Load credentials from environment variable (Render/production)
        cred = credentials.Certificate(json.loads(cred_json))
        firebase_admin.initialize_app(cred)
        print("[INFO] Firebase Admin initialized via environment credentials.")
    elif os.path.exists(Config.FIREBASE_CREDENTIALS_PATH):
        cred = credentials.Certificate(Config.FIREBASE_CREDENTIALS_PATH)
        firebase_admin.initialize_app(cred)
        print("[INFO] Firebase Admin initialized via service-account credentials.")
    else:
        firebase_admin.initialize_app()
        print("[WARN] Falling back to Application Default Credentials (ADC).")
    
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
    def create_post(author_handle: str, content: str, category: str, cityId: str, areaId: str, image_url: Optional[str] = None, **kwargs) -> bool:
        if not FirebaseService._is_db_active():
            return False
        try:
            posts_ref = db.collection("posts")
            
            # Base document
            doc_data = {
                "authorHandle": author_handle,
                "content": content,
                "imageUrl": image_url,
                "cityId": cityId,
                "stateId": cityId.split("-")[0] if "-" in cityId else "GJ",
                "areaId": areaId,
                "category": category,
                "createdAt": firestore.SERVER_TIMESTAMP,
                "upvotes": 0,
                "downvotes": 0,
                "score": 0,
                "totalScore": 0,
                "commentCount": 0,
                "isEmergency": category == "emergency",
                "userVotes": {},
                "hiddenByMod": False,
                "reporters": [],
                "reportCount": 0
            }
            
            # Add all non-None kwargs
            for k, v in kwargs.items():
                if v is not None:
                    doc_data[k] = v
                    
            posts_ref.add(doc_data)
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

    NUM_SHARDS = 20

    @staticmethod
    def vote_post(post_id: str, user_handle: str, direction: int) -> dict:
        if not FirebaseService._is_db_active():
            return {"success": False, "error": "Database inactive"}
        
        post_ref = db.collection("posts").document(post_id)
        vote_ref = post_ref.collection("votes").document(user_handle)
        
        # Select shard via hash to evenly spread writes across shards
        shard_id = str(int(hashlib.md5(user_handle.encode('utf-8')).hexdigest(), 16) % FirebaseService.NUM_SHARDS)
        shard_ref = post_ref.collection("scoreShards").document(shard_id)
        
        @firestore.transactional
        def run_vote_transaction(transaction, v_ref, s_ref):
            vote_snapshot = v_ref.get(transaction=transaction)
            
            previous_vote = 0
            if vote_snapshot.exists:
                vote_data = vote_snapshot.to_dict() or {}
                previous_vote = vote_data.get("value", vote_data.get("direction", 0))
            
            # Toggle matrix logic (Reddit/StackOverflow style)
            if previous_vote == direction:
                # Cancel/toggle off existing vote
                new_vote = 0
                if direction == 1:
                    score_delta = -1
                    upvote_delta = -1
                    downvote_delta = 0
                else:
                    score_delta = 1
                    upvote_delta = 0
                    downvote_delta = -1
                transaction.delete(v_ref)
            elif previous_vote == 0:
                # Cast new vote
                new_vote = direction
                if direction == 1:
                    score_delta = 1
                    upvote_delta = 1
                    downvote_delta = 0
                else:
                    score_delta = -1
                    upvote_delta = 0
                    downvote_delta = 1
                transaction.set(v_ref, {
                    "value": new_vote,
                    "direction": new_vote,
                    "userHandle": user_handle,
                    "updatedAt": firestore.SERVER_TIMESTAMP
                })
            else:
                # Switch vote direction (+1 to -1 or -1 to +1)
                new_vote = direction
                if direction == 1:
                    score_delta = 2
                    upvote_delta = 1
                    downvote_delta = -1
                else:
                    score_delta = -2
                    upvote_delta = -1
                    downvote_delta = 1
                transaction.set(v_ref, {
                    "value": new_vote,
                    "direction": new_vote,
                    "userHandle": user_handle,
                    "updatedAt": firestore.SERVER_TIMESTAMP
                })
            
            # Atomically increment chosen shard counter without locking the main post doc
            transaction.set(s_ref, {
                "score": firestore.Increment(score_delta),
                "upvotes": firestore.Increment(upvote_delta),
                "downvotes": firestore.Increment(downvote_delta),
                "updatedAt": firestore.SERVER_TIMESTAMP
            }, merge=True)
            
            return {
                "success": True,
                "newVote": new_vote,
                "scoreDelta": score_delta,
                "upvoteDelta": upvote_delta,
                "downvoteDelta": downvote_delta
            }

        try:
            transaction = db.transaction()
            res = run_vote_transaction(transaction, vote_ref, shard_ref)
            return res
        except Exception as e:
            print(f"Error casting vote in Firestore: {e}")
            return {"success": False, "error": str(e)}

    @staticmethod
    def aggregate_post_shards(post_id: str) -> dict:
        """
        Sums all shard counters for a post and writes the total back to the main post document.
        Called asynchronously after votes to maintain cached totalScore without contention.
        """
        if not FirebaseService._is_db_active():
            return {}
        try:
            post_ref = db.collection("posts").document(post_id)
            shards = post_ref.collection("scoreShards").get()
            
            total_score = 0
            total_upvotes = 0
            total_downvotes = 0
            has_shards = False
            
            for shard in shards:
                has_shards = True
                data = shard.to_dict() or {}
                total_score += data.get("score", 0)
                total_upvotes += data.get("upvotes", 0)
                total_downvotes += data.get("downvotes", 0)
                
            if not has_shards:
                post_doc = post_ref.get()
                if post_doc.exists:
                    pdata = post_doc.to_dict() or {}
                    total_upvotes = pdata.get("upvotes", 0)
                    total_downvotes = pdata.get("downvotes", 0)
                    total_score = pdata.get("score", total_upvotes - total_downvotes)
            
            total_upvotes = max(0, total_upvotes)
            total_downvotes = max(0, total_downvotes)
            
            post_ref.update({
                "score": total_score,
                "totalScore": total_score,
                "upvotes": total_upvotes,
                "downvotes": total_downvotes,
            })
            return {
                "score": total_score,
                "upvotes": total_upvotes,
                "downvotes": total_downvotes
            }
        except Exception as e:
            print(f"Error aggregating score shards for post {post_id}: {e}")
            return {}

    @staticmethod
    def backfill_post_shards(post_id: Optional[str] = None) -> int:
        """
        Backfills legacy posts with shard 0 to prevent breaking existing posts.
        """
        if not FirebaseService._is_db_active():
            return 0
        try:
            if post_id:
                posts = [db.collection("posts").document(post_id).get()]
            else:
                posts = db.collection("posts").get()
                
            count = 0
            for doc in posts:
                if not doc.exists:
                    continue
                p_ref = db.collection("posts").document(doc.id)
                shards = list(p_ref.collection("scoreShards").limit(1).get())
                if not shards:
                    data = doc.to_dict() or {}
                    up = data.get("upvotes", 0)
                    down = data.get("downvotes", 0)
                    score = data.get("score", up - down)
                    
                    p_ref.collection("scoreShards").document("0").set({
                        "score": score,
                        "upvotes": up,
                        "downvotes": down,
                        "updatedAt": firestore.SERVER_TIMESTAMP
                    })
                    p_ref.update({
                        "score": score,
                        "totalScore": score,
                        "upvotes": up,
                        "downvotes": down
                    })
                    count += 1
            return count
        except Exception as e:
            print(f"Error backfilling post shards: {e}")
            return 0

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
            db.collection("posts").document(post_id).delete()
            return True
        except Exception as e:
            print(f"Error deleting post in Firestore: {e}")
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
            
        transaction = db.transaction()
        meta_ref = db.collection("moderation_logs_meta").document("latest")
        logs_ref = db.collection("moderation_logs")
        
        @firestore.transactional
        def _log_in_transaction(transaction, meta_ref, logs_ref):
            meta_doc = meta_ref.get(transaction=transaction)
            previous_log_hash = "genesis_hash_0000000000000000"
            if meta_doc.exists:
                previous_log_hash = meta_doc.to_dict().get("currentLogHash", previous_log_hash)
                
            log_id = hashlib.sha256(f"{moderator_id}:{action}:{time.time()}".encode()).hexdigest()[:16]
            ip_hash = hmac.new(Config.JWT_SECRET.encode(), ip_address.encode(), hashlib.sha256).hexdigest()
            timestamp_sec = int(time.time())
            
            raw_data = f"{log_id}:{moderator_id}:{role}:{action}:{target}:{reason}:{timestamp_sec}:{request_id}:{ip_hash}:{previous_log_hash}"
            current_log_hash = hmac.new(Config.JWT_SECRET.encode(), raw_data.encode(), hashlib.sha256).hexdigest()
            
            transaction.set(logs_ref.document(log_id), {
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
            
            transaction.set(meta_ref, {
                "currentLogHash": current_log_hash,
                "lastLogId": log_id,
                "updatedAt": firestore.SERVER_TIMESTAMP
            })
            return True

        try:
            return _log_in_transaction(transaction, meta_ref, logs_ref)
        except Exception as e:
            print(f"Error writing moderator audit log: {e}")
            return False
