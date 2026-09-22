import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/community_model.dart';
import '../models/post_model.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/personal_chat_screen.dart';
import '../screens/communities/community_chat_screen.dart';
import '../screens/detail/post_detail_screen.dart';
import '../screens/friends/friends_screen.dart';
import '../services/auth_service.dart';
import '../services/community_repository.dart';
import '../services/friend_repository.dart';
import '../services/post_repository.dart';
import '../core/location/location_service.dart';
import '../core/widgets/in_app_notification_banner.dart';
import '../models/call_model.dart';
import '../screens/chat/incoming_call_screen.dart';

/// Top-level background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are handled automatically by the system tray.
  debugPrint('BG message received: ${message.notification?.title} | data: ${message.data}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  StreamSubscription<QuerySnapshot>? _userNotificationsSubscription;
  DateTime _sessionStartTime = DateTime.now();

  /// Currently open chat partner handle (to suppress heads-up notification while chatting)
  String? activeChatPartnerHandle;

  /// Currently open community ID (to suppress heads-up notification while in that community)
  String? activeCommunityId;

  // Android notification channel
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'nearhood_channel',
    'Nearhood Notifications',
    description: 'Notifications for friend requests, messages, posts, and communities',
    importance: Importance.high,
    playSound: true,
  );

  /// Initialize the notification service. Call once at app start.
  Future<void> initialize() async {
    try {
      _sessionStartTime = DateTime.now();

      // 1. Request permission
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('Notification permission: ${settings.authorizationStatus}');

      // 2. Create Android notification channel
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // 3. Initialize local notifications
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // 4. Set foreground notification presentation
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 5. Listen for foreground FCM messages
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      // 6. Listen for notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // 7. Check if app was opened from a terminated-state notification
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      // 8. Save/refresh FCM token
      await _saveToken();

      // 9. Listen for token refresh
      _fcm.onTokenRefresh.listen((newToken) {
        _saveTokenToFirestore(newToken);
      });

      // 10. Start listening to realtime notifications for logged in user
      final currentHandle = await AuthService.instance.getUserHandle();
      if (currentHandle != null && currentHandle.isNotEmpty) {
        startListening(currentHandle);
      }
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  /// Check if user has enabled alerts for this notification category
  Future<bool> _checkIfCategoryAllowed(String? type) async {
    final prefs = await SharedPreferences.getInstance();
    if (type == 'chat' || type == 'message') {
      return prefs.getBool('notif_chat_enabled') ?? true;
    } else if (type == 'friend_request') {
      return prefs.getBool('notif_friends_enabled') ?? true;
    } else if (type == 'community_message' || type == 'community') {
      return prefs.getBool('notif_communities_enabled') ?? true;
    } else if (type == 'post' || type == 'new_post') {
      return prefs.getBool('notif_posts_enabled') ?? true;
    }
    return true;
  }

  /// Start realtime notification listener for a specific handle
  void startListening(String handle) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty) return;

    _userNotificationsSubscription?.cancel();

    _userNotificationsSubscription = FirebaseFirestore.instance
        .collection('notifications')
        .where('targetHandle', isEqualTo: cleanHandle)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_sessionStartTime))
        .snapshots()
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          final title = data['title'] as String? ?? 'Nearhood';
          final body = data['body'] as String? ?? '';
          final payloadData = (data['data'] as Map<String, dynamic>?) ?? {};
          final type = payloadData['type'] as String?;

          // Check user notification preferences
          final isAllowed = await _checkIfCategoryAllowed(type);
          if (!isAllowed) continue;

          // Smart suppression: don't ring if user is actively on this chat screen
          if (type == 'chat' || type == 'message') {
            final sender = (payloadData['senderHandle'] as String?)?.replaceAll('@', '').trim();
            if (sender != null && sender == activeChatPartnerHandle) {
              continue; // User is already in active conversation with this person
            }
          } else if (type == 'community_message' || type == 'community') {
            final commId = payloadData['communityId'] as String?;
            if (commId != null && commId == activeCommunityId) {
              continue; // User is currently looking at this community chat
            }
          }

          // Show floating in-app banner if app is foreground and context is active
          final currentContext = navigatorKey.currentContext;
          if (currentContext != null && currentContext.mounted) {
            final sender = (payloadData['senderHandle'] ?? payloadData['partnerHandle'] as String?)?.replaceAll('@', '').trim();
            InAppNotificationBanner.show(
              currentContext,
              title: title,
              body: body,
              handle: sender,
              onTap: () => navigateToScreen(payloadData),
            );
          } else {
            showLocalNotification(
              title: title,
              body: body,
              data: payloadData,
            );
          }
        }
      }
    });
  }

  void stopListening() {
    _userNotificationsSubscription?.cancel();
    _userNotificationsSubscription = null;
  }

  /// Save FCM token to Firestore under the current user's document
  Future<void> _saveToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final storedUserId = await AuthService.instance.getUserId();
      final uid = storedUserId ?? FirebaseAuth.instance.currentUser?.uid;
      final handle = await AuthService.instance.getUserHandle();

      if (uid != null && uid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmToken': token,
          'tokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('FCM token saved for user $uid');
      }

      if (handle != null && handle.isNotEmpty) {
        final clean = handle.replaceAll('@', '').trim();
        await FirebaseFirestore.instance.collection('profiles').doc(clean).set({
          'fcmToken': token,
          'tokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  /// Show a local notification when an FCM message arrives in the foreground
  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? (message.data['title'] as String?);
    final body = notification?.body ?? (message.data['body'] as String?);

    if (title == null && body == null) return;

    _localNotifications.show(
      id: notification?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF000000),
        ),
      ),
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }

  /// Called when user taps a notification (foreground local notification)
  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        debugPrint('Notification tapped with data: $data');
        navigateToScreen(data);
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
    }
  }

  /// Called when user taps a notification (background/terminated FCM)
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification opened: ${message.data}');
    navigateToScreen(message.data);
  }

  /// Get stream of unread notifications count for badge
  Stream<int> getUnreadNotificationCount(String handle) {
    final clean = handle.replaceAll('@', '').trim();
    if (clean.isEmpty) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('targetHandle', isEqualTo: clean)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((e) {
          debugPrint('Error getting unread count: $e');
          return 0;
        });
  }

  /// Deep linking router for all 4 notification types:
  /// 1. 'chat' -> PersonalChatScreen
  /// 2. 'friend_request' -> FriendsScreen (Requests tab)
  /// 3. 'post' -> PostDetailScreen
  /// 4. 'community_message' or 'community' -> CommunityChatScreen
  Future<void> navigateToScreen(Map<String, dynamic> data) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final type = data['type'] as String?;
    
    // Fetch currentUserHandle from SharedPreferences / AuthService
    final prefs = await SharedPreferences.getInstance();
    final currentHandle = await AuthService.instance.getUserHandle() ??
        prefs.getString('user_handle') ??
        'Guest';
    final cleanCurrentHandle = currentHandle.replaceAll('@', '').trim();

    if (!context.mounted) return;

    // ── 1. Direct / Private Chat ──────────────────────────────────────────
    if (type == 'chat' || type == 'message') {
      final partnerHandle = (data['senderHandle'] ?? data['partnerHandle'] ?? data['handle'] as String?)?.replaceAll('@', '').trim();
      if (partnerHandle != null && partnerHandle.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PersonalChatScreen(
              currentUserHandle: cleanCurrentHandle,
              partnerHandle: partnerHandle,
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatListScreen(
              currentUserHandle: cleanCurrentHandle,
            ),
          ),
        );
      }
    }
    // ── 2. Friend Request ────────────────────────────────────────────────
    else if (type == 'friend_request') {
      final friendRepo = FriendRepository()..currentUserHandle = cleanCurrentHandle;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FriendsScreen(
            repository: friendRepo,
            currentUserHandle: cleanCurrentHandle,
          ),
        ),
      );
    }
    // ── 3. Post (General Feed / Area Post) ────────────────────────────────
    else if (type == 'post' || type == 'new_post') {
      final postId = data['postId'] as String?;
      if (postId != null && postId.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
          if (doc.exists && doc.data() != null && context.mounted) {
            final post = Post.fromFirestore(doc);
            final locService = LocationService();
            final postRepo = PostRepository(locService);
            postRepo.currentUserHandle = cleanCurrentHandle;

            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PostDetailScreen(
                  post: post,
                  repository: postRepo,
                  currentUserHandle: cleanCurrentHandle,
                ),
              ),
            );
            return;
          }
        } catch (e) {
          debugPrint('Error navigating to post detail: $e');
        }
      }
    }
    // ── 4. Community Message ─────────────────────────────────────────────
    else if (type == 'community_message' || type == 'community') {
      final communityId = data['communityId'] as String?;
      if (communityId != null && communityId.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('communities').doc(communityId).get();
          if (doc.exists && doc.data() != null && context.mounted) {
            final community = CommunityModel.fromFirestore(doc);
            final commRepo = CommunityRepository()..currentUserHandle = cleanCurrentHandle;

            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CommunityChatScreen(
                  repository: commRepo,
                  community: community,
                ),
              ),
            );
            return;
          }
        } catch (e) {
          debugPrint('Error navigating to community chat: $e');
        }
      }
    }
    // ── 5. Incoming Call ────────────────────────────────────────────────
    else if (type == 'call') {
      final callId = data['callId'] as String?;
      final callerHandle = (data['callerHandle'] as String?)?.replaceAll('@', '').trim();
      if (callId != null && callId.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('calls').doc(callId).get();
          if (doc.exists && doc.data() != null && context.mounted) {
            final call = CallModel.fromFirestore(doc);
            if (call.status == CallStatus.calling || call.status == CallStatus.ringing) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => IncomingCallScreen(
                    call: call,
                    currentUserHandle: cleanCurrentHandle,
                  ),
                  fullscreenDialog: true,
                ),
              );
              return;
            }
          }
        } catch (e) {
          debugPrint('Error opening call from notification: $e');
        }
      }

      // If call is already ended/missed or callId not found, open chat
      if (callerHandle != null && callerHandle.isNotEmpty && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PersonalChatScreen(
              currentUserHandle: cleanCurrentHandle,
              partnerHandle: callerHandle,
            ),
          ),
        );
      }
    }
  }

  // ── Dispatch & Helper Methods ──

  /// Dispatch an in-app and remote notification to a target user
  Future<void> sendNotification({
    required String targetHandle,
    String? targetUid,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    final cleanTarget = targetHandle.replaceAll('@', '').trim();
    if (cleanTarget.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'targetHandle': cleanTarget,
        'targetUid': targetUid,
        'title': title,
        'body': body,
        'data': data,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error dispatching notification to $cleanTarget: $e');
    }
  }

  /// Show a local notification immediately
  Future<void> showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF000000),
        ),
      ),
      payload: data != null ? jsonEncode(data) : null,
    );
  }
}
