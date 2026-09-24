import os
import sys
import uuid
import time

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from services.d1_service import D1Service

def seed():
    print("[START] Starting Cloudflare D1 category seed for Vadodara...")

    posts_to_create = [
        # 1. 💬 General Chat
        {
            "category": "general",
            "content": "Excited to connect with everyone in Vadodara! What are your favorite spots to hang out on weekends? ☕🌳",
            "image_url": "https://images.unsplash.com/photo-1517245386807-bb43f82c33c4?auto=format&fit=crop&w=1200&q=80",
            "author_handle": "Aarav_Vadodara",
            "cityId": "GJ-VAD",
            "areaId": "GJ-VAD",
            "mediaUrls": ["https://images.unsplash.com/photo-1517245386807-bb43f82c33c4?auto=format&fit=crop&w=1200&q=80"],
        },
        # 2. 🔧 Local Services
        {
            "category": "services",
            "content": "Professional home AC servicing & appliance repair across Vadodara. Fast doorstep service, transparent pricing, and 30-day service warranty! ❄️⚡",
            "image_url": "https://images.unsplash.com/photo-1581092918056-0c4c3acd3789?auto=format&fit=crop&w=1200&q=80",
            "author_handle": "CoolAir_Services",
            "cityId": "GJ-VAD",
            "areaId": "GJ-VAD",
            "serviceTitle": "CoolAir Pro AC & Appliance Repair",
            "servicePrice": "₹299",
            "serviceCategoryText": "Electrical & AC",
        },
        # 3. 🍲 Food & Restaurants
        {
            "category": "food",
            "content": "Tried the famous Sev Usal & Kathiyawadi thali in Vadodara today! Super delicious, perfectly spiced, and pocket-friendly. Must visit! 🍲🍛",
            "image_url": "https://images.unsplash.com/photo-1589302168068-964664d93dc0?auto=format&fit=crop&w=1200&q=80",
            "author_handle": "FoodieVlogger_Gita",
            "cityId": "GJ-VAD",
            "areaId": "GJ-VAD",
            "foodTitle": "Mahakali Sev Usal & Kathiyawadi Thali",
            "foodPrice": "₹150 for two",
            "foodRating": 4.8,
            "mediaUrls": ["https://images.unsplash.com/photo-1589302168068-964664d93dc0?auto=format&fit=crop&w=1200&q=80"],
        },
        # 4. 🏠 Rentals & PG / Rooms
        {
            "category": "rooms",
            "content": "Spacious & fully furnished 2 BHK flat available for rent. Modular kitchen, high-speed WiFi, 24x7 water and parking. Ready to move! 🏠🔑",
            "image_url": "https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?auto=format&fit=crop&w=1200&q=80",
            "author_handle": "VadodaraProperties",
            "cityId": "GJ-VAD",
            "areaId": "GJ-VAD",
            "roomTitle": "Modern Furnished 2 BHK Flat",
            "roomRent": "₹14,500/mo",
            "roomArea": "Vadodara",
            "mediaUrls": [
                "https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?auto=format&fit=crop&w=1200&q=80",
                "https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?auto=format&fit=crop&w=1200&q=80"
            ],
        },
        # 5. 🛍️ Shop & Marketplace
        {
            "category": "shop",
            "content": "Handcrafted premium leather jacket & artisan accessories. Limited festival collection with 20% discount this week! 🛍️✨",
            "image_url": "https://images.unsplash.com/photo-1551028719-00167b16eac5?auto=format&fit=crop&w=1200&q=80",
            "author_handle": "UrbanLeather_Co",
            "cityId": "GJ-VAD",
            "areaId": "GJ-VAD",
            "shopTitle": "Handcrafted Leather Jacket & Accessories",
            "shopPrice": "₹2,499",
            "shopCategory": "Fashion & Apparel",
            "mediaUrls": ["https://images.unsplash.com/photo-1551028719-00167b16eac5?auto=format&fit=crop&w=1200&q=80"],
        },
        # 6. 🎉 Events
        {
            "category": "events",
            "content": "Join us for the Vadodara Tech & Startup Networking Meetup 2026! Connect with local founders, developers, and designers. Free snacks & coffee! 🎉🚀",
            "image_url": "https://images.unsplash.com/photo-1511578314322-379afb476865?auto=format&fit=crop&w=1200&q=80",
            "author_handle": "VadodaraTechHub",
            "cityId": "GJ-VAD",
            "areaId": "GJ-VAD",
            "eventTitle": "Vadodara Tech & Startup Meetup 2026",
            "eventDate": "This Saturday, 5:00 PM",
            "eventLocationText": "Sayaji Baug Amphitheatre, Vadodara",
            "eventPrice": "Free Entry",
        },
        # 7. 💼 Jobs & Referrals
        {
            "category": "jobs",
            "content": "We are hiring a Senior Flutter Developer in Vadodara! Competitive salary, flexible hours, and great team culture. Apply today! 💼💻",
            "image_url": "https://images.unsplash.com/photo-1498050108023-c5249f4df085?auto=format&fit=crop&w=1200&q=80",
            "author_handle": "ApexDigital_HR",
            "cityId": "GJ-VAD",
            "areaId": "GJ-VAD",
            "jobTitle": "Senior Flutter Developer",
            "jobCompany": "Apex Digital Solutions",
            "jobLocation": "Vadodara (Hybrid)",
            "jobType": "Full-time",
        }
    ]

    for p in posts_to_create:
        cat = p["category"]
        post_id = D1Service.create_post(
            author_handle=p["author_handle"],
            content=p["content"],
            category=p["category"],
            cityId=p["cityId"],
            areaId=p.get("areaId"),
            image_url=p.get("image_url"),
            serviceTitle=p.get("serviceTitle"),
            servicePrice=p.get("servicePrice"),
            serviceCategoryText=p.get("serviceCategoryText"),
            foodTitle=p.get("foodTitle"),
            foodPrice=p.get("foodPrice"),
            foodRating=p.get("foodRating"),
            roomTitle=p.get("roomTitle"),
            roomRent=p.get("roomRent"),
            roomArea=p.get("roomArea"),
            shopTitle=p.get("shopTitle"),
            shopPrice=p.get("shopPrice"),
            shopCategory=p.get("shopCategory"),
            eventTitle=p.get("eventTitle"),
            eventDate=p.get("eventDate"),
            eventLocationText=p.get("eventLocationText"),
            eventPrice=p.get("eventPrice"),
            jobTitle=p.get("jobTitle"),
            jobCompany=p.get("jobCompany"),
            jobLocation=p.get("jobLocation"),
            jobType=p.get("jobType"),
            mediaUrls=p.get("mediaUrls"),
        )
        if post_id:
            print(f"[SUCCESS] Created post in category '{cat}': id={post_id}")
        else:
            print(f"[FAIL] Failed to create post in category '{cat}'")

    print("[DONE] All 7 categories successfully seeded in Cloudflare D1.")

if __name__ == "__main__":
    seed()
