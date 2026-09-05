import firebase_admin
from firebase_admin import credentials, firestore
import json

try:
    cred = credentials.Certificate('service-account.json')
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    docs = db.collection('posts').order_by('createdAt', direction=firestore.Query.DESCENDING).limit(10).get()
    for doc in docs:
        d = doc.to_dict()
        print(f"ID: {doc.id}, Category: {d.get('category')}, ServiceTitle: {d.get('serviceTitle')}")
except Exception as e:
    print('Error:', e)
