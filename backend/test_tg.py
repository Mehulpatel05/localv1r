import os, requests
from dotenv import load_dotenv
load_dotenv()
url = f"https://api.telegram.org/bot{os.getenv('TELEGRAM_BOT_TOKEN')}/sendPhoto"
# 1x1 valid PNG
valid_png = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\x0bIDAT\x08\x99c\xf8\x0f\x04\x00\x09\xfb\x03\xfd\xe3U\xf2\x9c\x00\x00\x00\x00IEND\xaeB`\x82'
files = {'photo': ('test.png', valid_png)}
data = {'chat_id': os.getenv('TELEGRAM_CHAT_ID')}
response = requests.post(url, data=data, files=files, timeout=15)
print(response.status_code)
print(response.text)
