# Vadodara Local — Secure Backend API Gateway

This FastAPI backend serves as a secure middleware proxy between your mobile Flutter application and the services it uses (Google Cloud Firestore & Telegram CDN).

---

## 🛠️ Security Protections Enabled
1.  **Token Cloaking:** The Telegram Bot Token is isolated to the server. Attackers cannot obtain it by decompiling the APK.
2.  **Firestore Write Shield:** Database write permissions are completely blocked for client app devices. All database creation, commenting, and voting calls must run via this server using the Firebase Admin SDK.
3.  **Spoof-Proof Handles:** Anonymous Handles (`Anon#XXXXXX`) are computed on the server side using the device's hardware signature combined with a secret server-side salt.
4.  **Bypass-Proof Input Filter:** Inputs are verified for slurs, scripting attacks (XSS), doxxing (phone numbers/emails), and phishing links on the server before insertion.

---

## 🚀 How to Run Locally

### 1. Prerequisite: Install Python
Ensure Python 3.9+ is installed on your computer.

### 2. Setup Virtual Environment & Install Dependencies
Run the following commands in your shell within the `backend/` folder:
```bash
# Create a virtual environment
python -m venv venv

# Activate virtual environment (Windows)
venv\Scripts\activate

# Install required packages
pip install -r requirements.txt
```

### 3. Firebase Admin Configuration
1.  Go to the **Firebase Console** -> Project Settings -> Service Accounts.
2.  Click **"Generate new private key"**. This downloads a JSON file containing credential variables.
3.  Rename this file to **`service-account.json`** and place it directly inside this `backend/` folder.

### 4. Run the Server
Start the ASGI web server using Uvicorn:
```bash
uvicorn main:app --reload
```
*   The server will start running at: `http://127.0.0.1:8000`
*   You can view the interactive Swagger API documentation at: `http://127.0.0.1:8000/docs`

---

## ⚙️ Custom Configurations (.env)
You can configure a `.env` file in this directory to override default parameters:
```env
TELEGRAM_BOT_TOKEN=8872354755:AAHpWzgXzyC9etONiX6q38d2m8j6L1wNnsw
TELEGRAM_CHAT_ID=-1003809637534
SERVER_SALT=MySuperSecretCitySalt2026
```
