import logging
import firebase_admin
from firebase_admin import credentials, messaging

logger = logging.getLogger("fcm_service")

try:
    cred = credentials.Certificate("firebase-key.json")
    firebase_admin.initialize_app(cred)
    logger.info("Firebase Admin SDK initialized successfully.")
except Exception as e:
    logger.warning(f"Firebase Admin SDK init notice: {e}")

def send_push_to_token(fcm_token: str, title: str, body: str, data_payload: dict = None):
    if not fcm_token or not str(fcm_token).strip():
        return False
    try:
        str_data = {}
        if data_payload:
            for k, v in data_payload.items():
                str_data[str(k)] = str(v)

        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data=str_data,
            token=str(fcm_token).strip(),
        )
        response = messaging.send(message)
        logger.info(f"FCM Push sent successfully: {response}")
        return True
    except Exception as e:
        logger.error(f"FCM Push Send Error: {e}")
        return False
