import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

class Config:
    # ⚠️ WARNING: In production, configure these variables in a .env file.
    # Do not hardcode secret keys in version control.
    
    TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "PLACEHOLDER_TOKEN_PLEASE_SET_IN_ENV")
    TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "-1000000000000")
    SERVER_SALT = os.getenv("SERVER_SALT", "PLACEHOLDER_SALT_PLEASE_SET_IN_ENV")
    JWT_SECRET = os.getenv("JWT_SECRET", "PLACEHOLDER_JWT_SECRET_PLEASE_SET_IN_ENV")
    
    # Path to Firebase Admin SDK service account key json
    FIREBASE_CREDENTIALS_PATH = os.getenv(
        "FIREBASE_CREDENTIALS_PATH",
        os.path.join(os.path.dirname(__file__), "service-account.json")
    )
