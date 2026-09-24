import os
from dotenv import load_dotenv
from cryptography.fernet import Fernet

# Load environment variables from .env file
load_dotenv()

class Config:
    # ⚠️ WARNING: In production, configure these variables in a .env file.
    # Do not hardcode secret keys in version control.
    
    # Cloudflare Credentials (R2 & D1)
    CLOUDFLARE_ACCOUNT_ID = os.getenv("CLOUDFLARE_ACCOUNT_ID", "")
    CLOUDFLARE_API_TOKEN = os.getenv("CLOUDFLARE_API_TOKEN", "")
    
    # Cloudflare R2 Object Storage
    R2_BUCKET_NAME = os.getenv("R2_BUCKET_NAME", "nearhood")
    R2_ENDPOINT_URL = os.getenv("R2_ENDPOINT_URL", "")
    R2_ACCESS_KEY_ID = os.getenv("R2_ACCESS_KEY_ID", "")
    R2_SECRET_ACCESS_KEY = os.getenv("R2_SECRET_ACCESS_KEY", "")
    R2_PUBLIC_URL_PREFIX = os.getenv("R2_PUBLIC_URL_PREFIX", "")

    # Cloudflare D1 SQL Database
    D1_DATABASE_ID = os.getenv("D1_DATABASE_ID", "")

    # Telegram Bot fallback (deprecated)
    TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
    TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "")

    SERVER_SALT = os.getenv("SERVER_SALT", "nearhood_salt_2026_vadodara_secure")
    JWT_SECRET = os.getenv("JWT_SECRET", "nearhood_jwt_super_secret_key_2026")
    
    _FERNET_KEY = os.getenv("FERNET_KEY", Fernet.generate_key().decode('utf-8'))
    crypto = Fernet(_FERNET_KEY.encode('utf-8'))
    
    # Wakit OTP Gateway Configuration
    WAKIT_API_KEY = os.getenv("WAKIT_API_KEY", "")
    WAKIT_BASE_URL = os.getenv("WAKIT_BASE_URL", "https://wakit.in/api/v1")
    WAKIT_TIMEOUT_SECONDS = int(os.getenv("WAKIT_TIMEOUT_SECONDS", "8"))
    WAKIT_MAX_RETRIES = int(os.getenv("WAKIT_MAX_RETRIES", "1"))
    OTP_FALLBACK_SIMULATION = os.getenv("OTP_FALLBACK_SIMULATION", "true").lower() in ("true", "1", "yes")
    DEFAULT_TEST_OTP = os.getenv("DEFAULT_TEST_OTP", "123456")
    
    # JWT Expiration settings
    JWT_ACCESS_EXPIRE_MINUTES = int(os.getenv("JWT_ACCESS_EXPIRE_MINUTES", "30"))
    JWT_REFRESH_EXPIRE_DAYS = int(os.getenv("JWT_REFRESH_EXPIRE_DAYS", "30"))

    # Path to Firebase Admin SDK service account key json
    FIREBASE_CREDENTIALS_PATH = os.getenv(
        "FIREBASE_CREDENTIALS_PATH",
        os.path.join(os.path.dirname(__file__), "service-account.json")
    )
