const admin = require('firebase-admin');

// IMPORTANT: Before running this script, ensure you have exported your service account key
// export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"
// Run with: node migrate_profiles.js

admin.initializeApp();

const db = admin.firestore();

async function migrateProfiles() {
  console.log("Starting migration of profiles...");
  
  const usersSnapshot = await db.collection('users').get();
  let count = 0;
  
  for (const doc of usersSnapshot.docs) {
    const data = doc.data();
    if (!data.handle) continue;
    
    // Check if profile already exists
    const profileRef = db.collection('profiles').doc(data.handle);
    const profileDoc = await profileRef.get();
    
    if (!profileDoc.exists) {
      await profileRef.set({
        handle: data.handle,
        ownerUid: doc.id,
        friendCount: 0,
        createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`Migrated profile for handle: ${data.handle}`);
      count++;
    }
  }
  
  console.log(`Migration complete. Created ${count} profiles.`);
}

migrateProfiles().catch(console.error);
