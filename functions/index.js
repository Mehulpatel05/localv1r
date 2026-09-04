const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Trigger: When a new Friend Request is created
 * Sends a push notification to the receiver.
 */
exports.sendFriendRequestNotification = onDocumentCreated(
  "friend_requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const requestData = snap.data();
    if (requestData.status !== "pending") return;

    const senderHandle = requestData.senderHandle;
    const receiverHandle = requestData.receiverHandle;

    try {
      // 1. Get receiver's FCM token from users collection
      const usersRef = admin.firestore().collection("users");
      const query = await usersRef.where("handle", "==", receiverHandle).limit(1).get();

      if (query.empty) {
        console.log(`User ${receiverHandle} not found`);
        return;
      }

      const receiverDoc = query.docs[0];
      const fcmToken = receiverDoc.data().fcmToken;

      if (!fcmToken) {
        console.log(`No FCM token for user ${receiverHandle}`);
        return;
      }

      // 2. Build the notification payload
      const message = {
        notification: {
          title: "New Friend Request",
          body: `@${senderHandle} wants to be your friend!`,
        },
        data: {
          type: "friend_request",
          sender: senderHandle,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        token: fcmToken,
      };

      // 3. Send the message
      const response = await admin.messaging().send(message);
      console.log(`Successfully sent friend request notification:`, response);
    } catch (error) {
      console.error(`Error sending friend request notification:`, error);
    }
  }
);

/**
 * Trigger: When a new personal chat message is sent
 * Sends a push notification to the receiver.
 */
exports.sendChatMessageNotification = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const messageData = snap.data();
    const senderHandle = messageData.senderHandle;
    const text = messageData.content || "Sent an image/file";
    
    // We need to figure out who the receiver is.
    const chatId = event.params.chatId;
    const chatDoc = await admin.firestore().collection("chats").doc(chatId).get();
    if (!chatDoc.exists) return;
    
    const participants = chatDoc.data().participants || [];
    const receiverHandle = participants.find(h => h !== senderHandle);

    if (!receiverHandle) return;

    try {
      // 1. Get receiver's FCM token
      const usersRef = admin.firestore().collection("users");
      const query = await usersRef.where("handle", "==", receiverHandle).limit(1).get();

      if (query.empty) return;

      const receiverDoc = query.docs[0];
      const fcmToken = receiverDoc.data().fcmToken;

      if (!fcmToken) return;

      // 2. Build the notification payload
      const message = {
        notification: {
          title: `@${senderHandle}`,
          body: text,
        },
        data: {
          type: "chat_message",
          chatId: chatId,
          sender: senderHandle,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        token: fcmToken,
      };

      // 3. Send the message
      const response = await admin.messaging().send(message);
      console.log(`Successfully sent chat notification:`, response);
    } catch (error) {
      console.error(`Error sending chat notification:`, error);
    }
  }
);
