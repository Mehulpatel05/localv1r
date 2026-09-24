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
import '../screens/profile/other_user_profile_sheet.dart';
import 'chat_preferences_service.dart';

/// Top-level background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are handled automatically by the system tray.
  debugPrint('BG message received: ${message.notification?.title} | data: ${message.data}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  static NotificationService get instance => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  StreamSubscription<QuerySnapshot>? _userNotificationsSubscription;

  /// Currently open chat partner handle (to suppress heads-up notification while chatting)
  String? activeChatPartnerHandle;

  /// Currently open community ID (to suppress heads-up notification while in that community)
  String? activeCommunityId;

  // Android notification channel for general messages & posts
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'nearhood_channel',
    'Nearhood Notifications',
    description: 'Notifications for friend requests, messages, posts, and communities',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  // Dedicated high-priority Call channel for Voice & Video calls
  static const AndroidNotificationChannel _callChannel = AndroidNotificationChannel(
    'nearhood_call_channel',
    'Nearhood Calls',
    description: 'High priority incoming voice and video call alerts',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
    audioAttributesUsage: AudioAttributesUsage.voiceCommunication,
  );

  /// Initialize the notification service. Call once at app start.
  Future<void> initialize() async {
    try {
      // 1. Request FCM permission
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('Notification permission: ${settings.authorizationStatus}');

      // 2. Initialize local notifications
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // 3. Request Android 13+ (API 33+) runtime notification permission & create channels
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(_channel);
      await androidPlugin?.createNotificationChannel(_callChannel);

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

  final Set<String> _processedNotificationIds = {};

  /// Start realtime notification listener for a specific handle
  void startListening(String handle) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty) return;

    _userNotificationsSubscription?.cancel();
    final sessionThreshold = DateTime.now().subtract(const Duration(seconds: 30));

    _userNotificationsSubscription = FirebaseFirestore.instance
        .collection('notifications')
        .where('targetHandle', isEqualTo: cleanHandle)
        .snapshots()
        .listen(
      (snapshot) async {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final docId = change.doc.id;
            if (_processedNotificationIds.contains(docId)) continue;
            _processedNotificationIds.add(docId);

            final data = change.doc.data();
            if (data == null) continue;

            final isRead = data['isRead'] as bool? ?? false;
            final createdAt = data['createdAt'] as Timestamp?;

            // If it's an old notification already marked read or before session start, skip
            if (isRead) continue;
            if (createdAt != null && createdAt.toDate().isBefore(sessionThreshold)) {
              continue;
            }

            final title = data['title'] as String? ?? 'Nearhood';
            final body = data['body'] as String? ?? '';
            final payloadData = (data['data'] as Map<String, dynamic>?) ?? {};
            final type = payloadData['type'] as String?;

            // Check user notification preferences
            final isAllowed = await _checkIfCategoryAllowed(type);
            if (!isAllowed) continue;

            // Smart suppression: don't ring if user is actively on this chat screen
            if (type == 'chat' || type == 'message') {
              final sender = (payloadData['senderHandle'] ?? payloadData['partnerHandle'] as String?)?.replaceAll('@', '').trim();
              if (sender != null && sender.toLowerCase() == activeChatPartnerHandle?.toLowerCase()) {
                continue; // User is already in active conversation with this person
              }
              // Check if chat is muted for this user (re-checks absolute UTC expiry)
              if (sender != null && sender.isNotEmpty) {
                final isMuted = await ChatPreferencesService.instance.isChatMutedForUser(cleanHandle, sender);
                if (isMuted) {
                  continue; // Suppress notification for muted conversation
                }
              }
            } else if (type == 'community_message' || type == 'community') {
              final commId = payloadData['communityId'] as String?;
              if (commId != null && commId == activeCommunityId) {
                continue; // User is currently looking at this community chat
              }
            }

            // Show floating in-app banner if app is foreground and context is active (Skip for calls since IncomingCallScreen presents directly)
            final currentContext = navigatorKey.currentContext;
            if (type != 'call' && currentContext != null && currentContext.mounted) {
              final sender = (payloadData['senderHandle'] ?? payloadData['partnerHandle'] as String?)?.replaceAll('@', '').trim();
              InAppNotificationBanner.show(
                currentContext,
                title: title,
                body: body,
                handle: sender,
                onTap: () => navigateToScreen(payloadData),
              );
            }

            // Also show system heads-up notification with sound
            showLocalNotification(
              title: title,
              body: body,
              data: payloadData,
            );
          }
        }
      },
      onError: (e) {
        debugPrint('Notification listener error for @$cleanHandle: $e');
      },
    );
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

        if (clean.toLowerCase() != clean) {
          await FirebaseFirestore.instance.collection('profiles').doc(clean.toLowerCase()).set({
            'fcmToken': token,
            'tokenUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        debugPrint('FCM token saved for @$clean');
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

  /// Get stream of unread social notifications count for badge (excludes 1-on-1 chat messages)
  Stream<int> getUnreadNotificationCount(String handle) {
    final clean = handle.replaceAll('@', '').trim();
    if (clean.isEmpty) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('targetHandle', isEqualTo: clean)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) {
          int count = 0;
          for (final doc in snap.docs) {
            final data = doc.data();
            final payload = (data['data'] as Map<String, dynamic>?) ?? {};
            final type = payload['type'] as String?;
            // Only count Instagram-style social and system notifications (chats are in Chat tab)
            if (type != 'chat' && type != 'message') {
              count++;
            }
          }
          return count;
        })
        .handleError((e) {
          debugPrint('Error getting unread count: $e');
          return 0;
        });
  }

  /// Get stream of total unread chat messages count across all conversations
  Stream<int> getUnreadChatCount(String handle) {
    final rawHandle = handle.trim();
    final cleanHandle = rawHandle.replaceAll('@', '');
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    final handles = <String>{
      rawHandle,
      cleanHandle,
      '@$cleanHandle',
      rawHandle.toLowerCase(),
      cleanHandle.toLowerCase(),
      '@${cleanHandle.toLowerCase()}',
      if (myUid != null && myUid.isNotEmpty) myUid,
    }.where((h) => h.isNotEmpty).toList();

    if (handles.isEmpty) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContainsAny: handles)
        .snapshots()
        .map((snapshot) {
          int totalUnread = 0;
          for (final doc in snapshot.docs) {
            try {
              final data = doc.data();
              final unreadMap = data['unreadCounts'] as Map<String, dynamic>? ?? {};
              final count = (unreadMap[cleanHandle] ??
                      unreadMap[rawHandle] ??
                      unreadMap['@$cleanHandle'] ??
                      unreadMap[cleanHandle.toLowerCase()] ??
                      unreadMap['@${cleanHandle.toLowerCase()}'] ??
                      (myUid != null ? unreadMap[myUid] : null) ??
                      0) as num;
              totalUnread += count.toInt();
            } catch (_) {}
          }
          return totalUnread;
        })
        .handleError((e) {
          debugPrint('Error getting unread chat count: $e');
          return 0;
        });
  }

  /// Deep linking router for Instagram-style notification types:
  /// 1. 'post', 'post_like', 'post_comment', 'post_upload', 'mention' -> PostDetailScreen
  /// 2. 'friend_request' -> FriendsScreen (Requests tab)
  /// 3. 'friend_accepted' -> OtherUserProfileSheet or FriendsScreen
  /// 4. 'chat', 'message' -> PersonalChatScreen
  /// 5. 'community_message', 'community' -> CommunityChatScreen
  /// 6. 'call' -> IncomingCallScreen
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

    // ── 1. Post Interactions (Like, Comment, Mention, Upload, New Post) ──
    if (type == 'post' ||
        type == 'new_post' ||
        type == 'post_like' ||
        type == 'post_comment' ||
        type == 'post_upload' ||
        type == 'mention') {
      final postId = data['postId'] as String?;
      if (postId != null && postId.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
          if (doc.exists && doc.data() != null && context.mounted) {
            final post = Post.fromFirestore(doc);
            final locService = LocationService();
            final postRepo = PostRepository(locService);
            postRepo.currentUserHandle = cleanCurrentHandle;

            await Navigator.of(context).push(
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
    // ── 2. Friend Request ────────────────────────────────────────────────
    else if (type == 'friend_request') {
      final friendRepo = FriendRepository()..currentUserHandle = cleanCurrentHandle;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FriendsScreen(
            repository: friendRepo,
            currentUserHandle: cleanCurrentHandle,
          ),
        ),
      );
    }
    // ── 3. Friend Request Accepted ───────────────────────────────────────
    else if (type == 'friend_accepted') {
      final senderHandle = (data['senderHandle'] as String?)?.replaceAll('@', '').trim();
      if (senderHandle != null && senderHandle.isNotEmpty) {
        final locService = LocationService();
        final postRepo = PostRepository(locService)..currentUserHandle = cleanCurrentHandle;
        await showOtherUserProfileSheet(
          context,
          partnerHandle: senderHandle,
          currentUserHandle: cleanCurrentHandle,
          repository: postRepo,
        );
      } else {
        final friendRepo = FriendRepository()..currentUserHandle = cleanCurrentHandle;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FriendsScreen(
              repository: friendRepo,
              currentUserHandle: cleanCurrentHandle,
            ),
          ),
        );
      }
    }
    // ── 4. Direct / Private Chat ──────────────────────────────────────────
    else if (type == 'chat' || type == 'message') {
      final partnerHandle = (data['senderHandle'] ?? data['partnerHandle'] ?? data['handle'] as String?)?.replaceAll('@', '').trim();
      if (partnerHandle != null && partnerHandle.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PersonalChatScreen(
              currentUserHandle: cleanCurrentHandle,
              partnerHandle: partnerHandle,
            ),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatListScreen(
              currentUserHandle: cleanCurrentHandle,
            ),
          ),
        );
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

            await Navigator.of(context).push(
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
              await Navigator.of(context).push(
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
        await Navigator.of(context).push(
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

  /// Show a local notification immediately on Android system tray
  Future<void> showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final notifId = (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0x7FFFFFFF;
      final isCall = data?['type'] == 'call';

      await _localNotifications.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            isCall ? _callChannel.id : _channel.id,
            isCall ? _callChannel.name : _channel.name,
            channelDescription: isCall ? _callChannel.description : _channel.description,
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF000000),
            playSound: true,
            enableVibration: true,
            channelShowBadge: true,
            visibility: NotificationVisibility.public,
            fullScreenIntent: isCall,
            category: isCall ? AndroidNotificationCategory.call : AndroidNotificationCategory.message,
            audioAttributesUsage: isCall ? AudioAttributesUsage.voiceCommunication : AudioAttributesUsage.notification,
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: isCall ? 'Incoming Call' : 'Nearhood',
            ),
          ),
        ),
        payload: data != null ? jsonEncode(data) : null,
      );
    } catch (e) {
      debugPrint('Error showing local notification: $e');
    }
  }

  /// Dedicated high-priority full-screen incoming call notification (wakes lock screen)
  Future<int> showIncomingCallNotification({
    required CallModel call,
  }) async {
    final notifId = call.callId.hashCode & 0x7FFFFFFF;
    final callerClean = call.callerHandle.replaceAll('@', '').trim();
    final isVideo = call.callType == CallType.video;
    final title = '@$callerClean';
    final body = 'Incoming ${isVideo ? 'video' : 'voice'} call...';

    try {
      await _localNotifications.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _callChannel.id,
            _callChannel.name,
            channelDescription: _callChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF2563EB),
            playSound: true,
            enableVibration: true,
            ongoing: true,
            autoCancel: false,
            channelShowBadge: true,
            visibility: NotificationVisibility.public,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.call,
            audioAttributesUsage: AudioAttributesUsage.voiceCommunication,
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: 'Incoming Call',
            ),
          ),
        ),
        payload: jsonEncode({
          'type': 'call',
          'callId': call.callId,
          'callerHandle': call.callerHandle,
          'callType': call.callType.name,
        }),
      );
    } catch (e) {
      debugPrint('Error showing incoming call notification: $e');
    }
    return notifId;
  }

  /// Cancel an active incoming call notification
  Future<void> cancelCallNotification(String callId) async {
    try {
      final notifId = callId.hashCode & 0x7FFFFFFF;
      await _localNotifications.cancel(id: notifId);
    } catch (e) {
      debugPrint('Error canceling call notification: $e');
    }
  }
}
