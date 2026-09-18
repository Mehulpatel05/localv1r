import os
from dotenv import load_dotenv
from cryptography.fernet import Fernet

# Load environment variables from .env file
load_dotenv()

class Config:
    # ⚠️ WARNING: In production, configure these variables in a .env file.
    # Do not hardcode secret keys in version control.
    
    TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "PLACEHOLDER_TOKEN_PLEASE_SET_IN_ENV")
    TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "-1000000000000")
    SERVER_SALT = os.getenv("SERVER_SALT", "PLACEHOLDER_SALT_PLEASE_SET_IN_ENV")
    JWT_SECRET = os.getenv("JWT_SECRET", "PLACEHOLDER_JWT_SECRET_PLEASE_SET_IN_ENV")
    
    _FERNET_KEY = os.getenv("FERNET_KEY", Fernet.generate_key().decode('utf-8'))
    crypto = Fernet(_FERNET_KEY.encode('utf-8'))
    
    # Wakit OTP Gateway Configuration
    WAKIT_API_KEY = os.getenv("WAKIT_API_KEY", "")
    WAKIT_BASE_URL = os.getenv("WAKIT_BASE_URL", "https://api.wakit.app/v1")
    
    # JWT Expiration settings
    JWT_ACCESS_EXPIRE_MINUTES = int(os.getenv("JWT_ACCESS_EXPIRE_MINUTES", "30"))
    JWT_REFRESH_EXPIRE_DAYS = int(os.getenv("JWT_REFRESH_EXPIRE_DAYS", "30"))

    # Path to Firebase Admin SDK service account key json
    FIREBASE_CREDENTIALS_PATH = os.getenv(
        "FIREBASE_CREDENTIALS_PATH",
        os.path.join(os.path.dirname(__file__), "service-account.json")
    )
