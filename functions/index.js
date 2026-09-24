const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

/**
 * Helper to resolve FCM token for a user by handle and/or uid
 */
async function resolveFcmToken(handle, uid) {
  const cleanHandle = (handle || "").replace("@", "").trim();

  // 1. Check profiles collection by clean handle
  if (cleanHandle) {
    try {
      const profileDoc = await db.collection("profiles").doc(cleanHandle).get();
      if (profileDoc.exists && profileDoc.data().fcmToken) {
        return profileDoc.data().fcmToken;
      }
      // Try lowercase handle
      const lowerDoc = await db.collection("profiles").doc(cleanHandle.toLowerCase()).get();
      if (lowerDoc.exists && lowerDoc.data().fcmToken) {
        return lowerDoc.data().fcmToken;
      }
    } catch (e) {
      console.log("Error checking profile doc for FCM token:", e);
    }
  }

  // 2. Check users collection by uid
  if (uid) {
    try {
      const userDoc = await db.collection("users").doc(uid).get();
      if (userDoc.exists && userDoc.data().fcmToken) {
        return userDoc.data().fcmToken;
      }
    } catch (e) {
      console.log("Error checking user doc for FCM token:", e);
    }
  }

  // 3. Fallback: Query users collection where handle == cleanHandle
  if (cleanHandle) {
    try {
      const query = await db
        .collection("users")
        .where("handle", "in", [cleanHandle, `@${cleanHandle}`, cleanHandle.toLowerCase()])
        .limit(1)
        .get();
      if (!query.empty && query.docs[0].data().fcmToken) {
        return query.docs[0].data().fcmToken;
      }
    } catch (e) {
      console.log("Error querying users collection for handle:", e);
    }
  }

  return null;
}

/**
 * Trigger: When ANY notification document is created in `notifications`
 * Handles all in-app notifications (Chat, Friend Request, Community, Post, etc.)
 */
exports.onNotificationCreated = onDocumentCreated(
  "notifications/{notifId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const targetHandle = data.targetHandle;
    const targetUid = data.targetUid;
    const title = data.title || "Nearhood";
    const body = data.body || "";
    const payloadData = data.data || {};

    try {
      const token = await resolveFcmToken(targetHandle, targetUid);
      if (!token) {
        console.log(`No FCM token found for target ${targetHandle || targetUid}`);
        return;
      }

      // Convert all payload values to string (FCM data block requirement)
      const stringData = {};
      for (const [key, value] of Object.entries(payloadData)) {
        stringData[key] = typeof value === "string" ? value : JSON.stringify(value);
      }
      stringData.click_action = "FLUTTER_NOTIFICATION_CLICK";

      const message = {
        token: token,
        notification: {
          title: title,
          body: body,
        },
        data: stringData,
        android: {
          priority: "high",
          notification: {
            channelId: "nearhood_channel",
            icon: "ic_launcher",
            color: "#000000",
            sound: "default",
            defaultSound: true,
            defaultVibrateTimings: true,
            priority: "max",
            visibility: "public",
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              contentAvailable: true,
            },
          },
        },
      };

      const response = await admin.messaging().send(message);
      console.log(`Sent push notification to ${targetHandle || targetUid}:`, response);
    } catch (error) {
      console.error(`Error sending push notification:`, error);
    }
  }
);

/**
 * Trigger: When a new Audio/Video Call is initiated in `calls/{callId}`
 * High-priority wake-up push notification for incoming calls
 */
exports.onCallCreated = onDocumentCreated(
  "calls/{callId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const callData = snap.data();
    const status = callData.status;
    if (status !== "calling" && status !== "ringing") return;

    const callId = event.params.callId;
    const callerHandle = callData.callerHandle || "Neighbor";
    const receiverHandle = callData.receiverHandle;
    const receiverUid = callData.receiverUid;
    const callType = callData.callType || "audio";

    try {
      const token = await resolveFcmToken(receiverHandle, receiverUid);
      if (!token) {
        console.log(`No FCM token found for call receiver ${receiverHandle || receiverUid}`);
        return;
      }

      const isVideo = callType === "video";
      const title = `@${callerHandle.replace("@", "")} is calling...`;
      const body = isVideo ? "Incoming Video Call 📹" : "Incoming Voice Call 📞";

      const message = {
        token: token,
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: "call",
          callId: callId,
          callerHandle: callerHandle,
          callType: callType,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          ttl: 60 * 1000, // 60s timeout
          notification: {
            channelId: "nearhood_channel",
            icon: "ic_launcher",
            color: "#000000",
            sound: "default",
            defaultSound: true,
            defaultVibrateTimings: true,
            priority: "max",
            visibility: "public",
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              contentAvailable: true,
            },
          },
        },
      };

      const response = await admin.messaging().send(message);
      console.log(`Sent call push alert to ${receiverHandle}:`, response);
    } catch (error) {
      console.error(`Error sending call push notification:`, error);
    }
  }
);
