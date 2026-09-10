import os
import random
import uuid
import datetime
from google.cloud import firestore
import firebase_admin

# Import DB from backend directly to reuse credentials setup
import sys
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from services.firebase_service import db

AREAS = [
    {"id": "GJ-VAD-ALKAPURI", "name": "Alkapuri"},
    {"id": "GJ-VAD-SAYAJIGUNJ", "name": "Sayajigunj"},
    {"id": "GJ-VAD-GOTRI", "name": "Gotri"},
    {"id": "GJ-VAD-MANJALPUR", "name": "Manjalpur"},
    {"id": "GJ-VAD-KARELIBAUG", "name": "Karelibaug"},
    {"id": "GJ-VAD-FATEHGUNJ", "name": "Fatehgunj"},
    {"id": "GJ-VAD-SUBHANPURA", "name": "Subhanpura"},
    {"id": "GJ-VAD-WAGHODIA", "name": "Waghodia Road"},
    {"id": "GJ-VAD-AKOTA", "name": "Akota"},
    {"id": "GJ-VAD-VASNA", "name": "Vasna"},
    {"id": "GJ-VAD-BHAYLI", "name": "Bhayli"},
    {"id": "GJ-VAD-SAMA", "name": "Sama"},
    {"id": "GJ-VAD-HARNI", "name": "Harni"}
]

CATEGORIES = ["rooms", "food", "events", "jobs", "services", "shop", "general"]

CONTENT_TEMPLATES = {
    "rooms": [
        "1 BHK available for rent immediately. Fully furnished.",
        "Looking for a PG mate. Vegetarian preferred.",
        "2 BHK flat near the main road, nice ventilation.",
        "Spacious room available in a shared apartment.",
        "PG available with food and wifi included."
    ],
    "food": [
        "Tried the new cafe down the street, amazing coffee!",
        "Best pav bhaji in town is here, hands down.",
        "Any recommendations for late night food delivery?",
        "Home cooked tiffin service available. Rs 3000/month.",
        "Great discounts on pizza tonight!"
    ],
    "events": [
        "Weekend garage sale! Come grab some items.",
        "Local tech meetup this Sunday. Everyone is welcome.",
        "Standup comedy open mic at the cafe.",
        "Navratri garba passes available. DM me.",
        "Free yoga session in the park tomorrow morning."
    ],
    "jobs": [
        "Looking for a part-time cashier. Apply within.",
        "Hiring a junior software developer. Freshers welcome.",
        "Need a reliable delivery driver.",
        "Graphic designer needed for a short freelance project.",
        "Looking for a tutor for high school math."
    ],
    "services": [
        "AC repair and servicing at affordable rates.",
        "Professional home cleaning services.",
        "Need a good plumber? Call me.",
        "Freelance photographer for events and weddings.",
        "Laptop and mobile repair."
    ],
    "shop": [
        "Selling my old bicycle, good condition.",
        "Used sofa set for sale. Price negotiable.",
        "Fresh organic vegetables available.",
        "Second hand books for college students.",
        "Selling my gaming console with 5 games."
    ],
    "general": [
        "Traffic is crazy today, avoid the main crossing.",
        "Did anyone else hear that loud noise?",
        "Beautiful weather today!",
        "Does anyone know if the library is open today?",
        "Lost my keys near the supermarket, please let me know if found."
    ]
}

def seed():
    if db is None:
        print("Database not initialized. Check credentials.")
        return
        
    batch = db.batch()
    count = 0
    now = datetime.datetime.now(datetime.timezone.utc)
    
    for area in AREAS:
        for cat in CATEGORIES:
            for _ in range(5):
                post_id = str(uuid.uuid4())
                ref = db.collection('posts').document(post_id)
                
                content = random.choice(CONTENT_TEMPLATES[cat])
                
                post_data = {
                    "id": post_id,
                    "authorHandle": f"user_{random.randint(1000, 9999)}",
                    "content": f"{content} In {area['name']}.",
                    "category": cat,
                    "createdAt": now - datetime.timedelta(minutes=random.randint(1, 10000)),
                    "stateId": "GJ",
                    "cityId": "GJ-VAD",
                    "areaId": area["id"],
                    "areaName": area["name"],
                    "upvotes": random.randint(0, 20),
                    "downvotes": random.randint(0, 5),
                    "commentCount": random.randint(0, 10),
                    "userVote": 0,
                    "isEmergency": False,
                    "reportCount": 0,
                    "reporters": []
                }
                
                # Add category specific dummy fields to make UI look good
                if cat == "rooms":
                    post_data["roomTitle"] = "Room available"
                    post_data["roomRent"] = str(random.randint(3000, 15000))
                elif cat == "food":
                    post_data["foodTitle"] = "Delicious Food"
                    post_data["foodRating"] = round(random.uniform(3.5, 5.0), 1)
                elif cat == "jobs":
                    post_data["jobTitle"] = "Hiring Now"
                    post_data["jobCompany"] = "Local Business"
                
                batch.set(ref, post_data)
                count += 1
                
                # Firestore batches can hold up to 500 writes
                if count % 400 == 0:
                    batch.commit()
                    batch = db.batch()
                    print(f"Committed {count} posts...")
                    
    if count % 400 != 0:
        batch.commit()
    print(f"Successfully seeded {count} posts!")

if __name__ == "__main__":
    seed()
