import time
import uuid
import os
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

# Add backend directory to sys.path so we can import services
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from services.d1_service import D1Service

def seed_communities():
    print("🚀 Initializing D1 Tables...")
    D1Service.init_schema()

    print("🌱 Seeding 1 Channel and 1 Group into Cloudflare D1...")

    # 1. CHANNEL (Broadcast only by Admin)
    channel_name = "Vadodara City Updates 📢"
    channel_desc = "Official neighborhood news, weather advisories, traffic alerts & municipal updates for Vadodara."
    channel_img = "https://images.unsplash.com/photo-1570168007204-dfb528c6958f?auto=format&fit=crop&w=800&q=80"
    channel_admin = "vadodara_admin"

    # Check if channel already exists
    existing = D1Service.query("SELECT id FROM communities WHERE name = ? LIMIT 1;", [channel_name])
    if existing and len(existing) > 0:
        channel_id = existing[0]["id"]
        print(f"ℹ️ Channel already exists (ID: {channel_id}). Cleaning old messages to re-seed...")
        D1Service.execute("DELETE FROM community_messages WHERE community_id = ?;", [channel_id])
    else:
        channel_id = D1Service.create_community(
            name=channel_name,
            description=channel_desc,
            admin_handle=channel_admin,
            is_channel=True,
            image_url=channel_img
        )
        print(f"✅ Created Channel: '{channel_name}' (ID: {channel_id})")

    # Add Channel Messages
    channel_messages = [
        {
            "author": "vadodara_admin",
            "content": "👋 Welcome to the official **Vadodara City Updates** channel! Stay tuned here for daily verified alerts, road construction updates, cultural events, and civic announcements.",
            "img": None,
            "type": "text"
        },
        {
            "author": "vadodara_admin",
            "content": "🚧 **Traffic Advisory: Alkapuri Underbridge Maintenance**\n\nPlease note that the Alkapuri Railway Underpass will undergo routine resurfacing between 11:00 PM and 5:00 AM this weekend. Kindly use the RC Dutt Road flyover alternative.",
            "img": "https://images.unsplash.com/photo-1541888946425-d0fbb18086f6?auto=format&fit=crop&w=800&q=80",
            "type": "image"
        },
        {
            "author": "vadodara_admin",
            "content": "☀️ **Weather & Air Quality Forecast**:\nTemperature: 33°C | AQI: 58 (Satisfactory). Perfect evening for outdoor gatherings around Sayaji Baug garden! 🌳",
            "img": None,
            "type": "text"
        }
    ]

    for msg in channel_messages:
        msg_id = D1Service.send_community_message(
            community_id=channel_id,
            author_handle=msg["author"],
            content=msg["content"],
            image_url=msg["img"],
            message_type=msg["type"]
        )
        print(f"   ↳ Added Channel Broadcast: {msg_id}")
        time.sleep(0.1)

    # 2. GROUP (Interactive Community Chat)
    group_name = "Vadodara Tech & Startups 🚀"
    group_desc = "A vibrant community for developers, founders, designers, and students in Vadodara to collaborate, share jobs & organize meetups."
    group_img = "https://images.unsplash.com/photo-1522071820081-009f0129c71c?auto=format&fit=crop&w=800&q=80"
    group_admin = "parth_dev"

    existing_group = D1Service.query("SELECT id FROM communities WHERE name = ? LIMIT 1;", [group_name])
    if existing_group and len(existing_group) > 0:
        group_id = existing_group[0]["id"]
        print(f"ℹ️ Group already exists (ID: {group_id}). Cleaning old messages to re-seed...")
        D1Service.execute("DELETE FROM community_messages WHERE community_id = ?;", [group_id])
    else:
        group_id = D1Service.create_community(
            name=group_name,
            description=group_desc,
            admin_handle=group_admin,
            is_channel=False,
            image_url=group_img
        )
        print(f"✅ Created Group: '{group_name}' (ID: {group_id})")

    # Add dummy members
    members = ["parth_dev", "ananya_ux", "rahul_cloud", "sneha_ai"]
    for m in members:
        D1Service.join_community(group_id, m)

    # Add Group Chat Messages
    group_messages = [
        {
            "author": "parth_dev",
            "content": "Hey everyone! 👋 Welcome to Vadodara Tech & Startups group. Feel free to introduce yourselves and share what you're currently building.",
            "img": None,
            "type": "text"
        },
        {
            "author": "ananya_ux",
            "content": "Hi guys! I'm a product designer based out of Fatehgunj. Currently designing a Flutter mobile app for local hyper-delivery. Looking forward to connecting with Flutter devs here! 🎨📱",
            "img": None,
            "type": "text"
        },
        {
            "author": "rahul_cloud",
            "content": "Great to meet you Ananya! I work on Cloudflare Workers and FastAPI backends. Here is a snap from our local dev meetup last Saturday at Sayajigunj! ☕💻",
            "img": "https://images.unsplash.com/photo-1531482615713-2afd69097998?auto=format&fit=crop&w=800&q=80",
            "type": "image"
        },
        {
            "author": "sneha_ai",
            "content": "Awesome! When is the next weekend hack session planned? Let's do a co-working sprint this Sunday! 🚀",
            "img": None,
            "type": "text"
        }
    ]

    for msg in group_messages:
        msg_id = D1Service.send_community_message(
            community_id=group_id,
            author_handle=msg["author"],
            content=msg["content"],
            image_url=msg["img"],
            message_type=msg["type"]
        )
        print(f"   ↳ Added Group Message from @{msg['author']}: {msg_id}")
        time.sleep(0.1)

    print("\n🎉 Seeding completed successfully!")

if __name__ == "__main__":
    seed_communities()
