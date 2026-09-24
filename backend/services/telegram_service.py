import requests
from typing import Optional, Dict, Any
from config import Config

class TelegramService:
    @staticmethod
    def upload_photo(file_content: bytes, filename: str) -> Optional[str]:
        """
        Uploads an image file to the configured private Telegram channel.
        Returns the unique Telegram file_id if successful, otherwise None.
        """
        url = f"https://api.telegram.org/bot{Config.TELEGRAM_BOT_TOKEN}/sendPhoto"
        try:
            files = {"photo": (filename, file_content)}
            data = {"chat_id": Config.TELEGRAM_CHAT_ID}
            response = requests.post(url, data=data, files=files, timeout=30)
            
            if response.status_code == 200:
                result = response.json()
                if result.get("ok"):
                    # Extract photo array (last item is highest resolution)
                    photos = result["result"]["photo"]
                    return photos[-1]["file_id"]
            return None
        except Exception as e:
            print(f"[TelegramService] Photo upload error: {e}")
            return None

    @staticmethod
    def upload_video(file_content: bytes, filename: str, duration: Optional[int] = None, width: Optional[int] = None, height: Optional[int] = None) -> Optional[str]:
        """
        Uploads a video file to the configured private Telegram channel with streaming support.
        Falls back to sendDocument if video codec is unrecognized by Telegram.
        Returns the unique Telegram file_id if successful, otherwise None.
        """
        url = f"https://api.telegram.org/bot{Config.TELEGRAM_BOT_TOKEN}/sendVideo"
        try:
            files = {"video": (filename, file_content)}
            data = {
                "chat_id": Config.TELEGRAM_CHAT_ID,
                "supports_streaming": "true"
            }
            if duration is not None:
                data["duration"] = str(duration)
            if width is not None:
                data["width"] = str(width)
            if height is not None:
                data["height"] = str(height)

            response = requests.post(url, data=data, files=files, timeout=60)
            
            if response.status_code == 200:
                result = response.json()
                if result.get("ok"):
                    video_info = result["result"].get("video")
                    if video_info and "file_id" in video_info:
                        return video_info["file_id"]
                    document_info = result["result"].get("document")
                    if document_info and "file_id" in document_info:
                        return document_info["file_id"]

            # Fallback to sendDocument
            doc_url = f"https://api.telegram.org/bot{Config.TELEGRAM_BOT_TOKEN}/sendDocument"
            doc_files = {"document": (filename, file_content)}
            doc_data = {"chat_id": Config.TELEGRAM_CHAT_ID}
            doc_response = requests.post(doc_url, data=doc_data, files=doc_files, timeout=60)
            if doc_response.status_code == 200:
                doc_result = doc_response.json()
                if doc_result.get("ok"):
                    document_info = doc_result["result"].get("document")
                    if document_info and "file_id" in document_info:
                        return document_info["file_id"]
            return None
        except Exception as e:
            print(f"[TelegramService] Video upload error: {e}")
            return None

    @staticmethod
    def get_download_url(file_id: str) -> Optional[str]:
        """
        Resolves a Telegram file_id to a direct download URL on Telegram CDN.
        """
        url = f"https://api.telegram.org/bot{Config.TELEGRAM_BOT_TOKEN}/getFile"
        try:
            params = {"file_id": file_id}
            response = requests.get(url, params=params, timeout=15)
            
            if response.status_code == 200:
                result = response.json()
                if result.get("ok"):
                    file_path = result["result"]["file_path"]
                    # Direct link to the hosted file on Telegram CDN
                    return f"https://api.telegram.org/file/bot{Config.TELEGRAM_BOT_TOKEN}/{file_path}"
            return None
        except Exception as e:
            print(f"[TelegramService] getFile error: {e}")
            return None

    @staticmethod
    def get_file_info(file_id: str) -> Optional[Dict[str, Any]]:
        """
        Fetches metadata for a Telegram file_id (file_path, file_size, etc.).
        """
        url = f"https://api.telegram.org/bot{Config.TELEGRAM_BOT_TOKEN}/getFile"
        try:
            params = {"file_id": file_id}
            response = requests.get(url, params=params, timeout=15)
            if response.status_code == 200:
                result = response.json()
                if result.get("ok"):
                    return result.get("result")
            return None
        except Exception as e:
            print(f"[TelegramService] get_file_info error: {e}")
            return None
