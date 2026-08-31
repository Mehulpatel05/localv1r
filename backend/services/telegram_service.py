import requests
from typing import Optional
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
            response = requests.post(url, data=data, files=files, timeout=15)
            
            if response.status_code == 200:
                result = response.json()
                if result.get("ok"):
                    # Extract photo array (last item is highest resolution)
                    photos = result["result"]["photo"]
                    return photos[-1]["file_id"]
            return None
        except Exception as e:
            print(f"Telegram upload error: {e}")
            return None

    @staticmethod
    def get_download_url(file_id: str) -> Optional[str]:
        """
        Resolves a Telegram file_id to a direct public download URL.
        """
        url = f"https://api.telegram.org/bot{Config.TELEGRAM_BOT_TOKEN}/getFile"
        try:
            params = {"file_id": file_id}
            response = requests.get(url, params=params, timeout=10)
            
            if response.status_code == 200:
                result = response.json()
                if result.get("ok"):
                    file_path = result["result"]["file_path"]
                    # Direct link to the hosted file on Telegram CDN
                    return f"https://api.telegram.org/file/bot{Config.TELEGRAM_BOT_TOKEN}/{file_path}"
            return None
        except Exception as e:
            print(f"Telegram getFile error: {e}")
            return None
