import requests
try:
    res = requests.post("https://localv1r.onrender.com/api/v1/moderation/login", json={"email": "admin@vadodara.local", "password": "VadodaraLocalSecure2026!"})
    print("STATUS:", res.status_code)
    try:
        print("JSON:", res.json())
    except:
        print("TEXT:", res.text)
except Exception as e:
    print("ERR:", e)
