import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/personal_chat_screen.dart';
import '../screens/communities/community_chat_screen.dart';
import '../screens/communities/join_requests_screen.dart';
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
  debugPrint('BG message received: ${message.notification?.title} | data: ${message.data}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  static NotificationService get instance => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  Timer? _pollingTimer;

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

      // 3. Request Android 13+ runtime notification permission & create channels
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

      // 8. Start listening to realtime notifications for logged in user
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
    } else if (type == 'community_message' || type == 'community' || type == 'community_join_request' || type == 'community_request_response') {
      return prefs.getBool('notif_communities_enabled') ?? true;
    } else if (type == 'post' || type == 'new_post') {
      return prefs.getBool('notif_posts_enabled') ?? true;
    }
    return true;
  }

  final Set<String> _processedNotificationIds = {};

  /// Start realtime notification poller for a specific handle
  void startListening(String handle) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty) return;

    _pollingTimer?.cancel();
    final sessionThreshold = DateTime.now().subtract(const Duration(seconds: 30));

    _pollingTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      try {
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/notifications?handle=$cleanHandle'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final notifs = (data['notifications'] as List<dynamic>?) ?? [];

          for (final raw in notifs) {
            final notif = raw as Map<String, dynamic>;
            final docId = (notif['id'] ?? '').toString();
            if (_processedNotificationIds.contains(docId)) continue;
            _processedNotificationIds.add(docId);

            final isRead = notif['isRead'] == true;
            if (isRead) continue;

            final rawCreated = notif['timestamp'] ?? notif['createdAt'];
            DateTime? createdAt;
            if (rawCreated is int) {
              createdAt = DateTime.fromMillisecondsSinceEpoch(rawCreated * 1000);
            } else if (rawCreated is String) {
              createdAt = DateTime.tryParse(rawCreated);
            }

            if (createdAt != null && createdAt.isBefore(sessionThreshold)) {
              continue;
            }

            final title = notif['title'] as String? ?? 'Nearhood';
            final body = notif['body'] as String? ?? '';
            final payloadData = (notif['data'] as Map<String, dynamic>?) ?? {};
            final type = payloadData['type'] as String? ?? notif['type'] as String?;

            // Check user notification preferences
            final isAllowed = await _checkIfCategoryAllowed(type);
            if (!isAllowed) continue;

            // Smart suppression: don't ring if user is actively on this chat screen
            if (type == 'chat' || type == 'message') {
              final sender = (payloadData['senderHandle'] ?? payloadData['partnerHandle'] as String?)?.replaceAll('@', '').trim();
              if (sender != null && sender.toLowerCase() == activeChatPartnerHandle?.toLowerCase()) {
                continue;
              }
              if (sender != null && sender.isNotEmpty) {
                final isMuted = await ChatPreferencesService.instance.isChatMutedForUser(cleanHandle, sender);
                if (isMuted) continue;
              }
            } else if (type == 'community_message' || type == 'community') {
              final commId = payloadData['communityId'] as String?;
              if (commId != null && commId == activeCommunityId) {
                continue;
              }
            }

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

            showLocalNotification(
              title: title,
              body: body,
              data: payloadData,
            );
          }
        }
      } catch (_) {}
    });
  }

  void stopListening() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
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

  /// Get stream of unread social notifications count for badge
  Stream<int> getUnreadNotificationCount(String handle) async* {
    final clean = handle.replaceAll('@', '').trim();
    if (clean.isEmpty) {
      yield 0;
      return;
    }

    while (true) {
      try {
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/notifications?handle=$clean'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final notifs = (data['notifications'] as List<dynamic>?) ?? [];
          int count = 0;
          for (final n in notifs) {
            final isRead = n['isRead'] == true;
            final type = (n['data']?['type'] ?? n['type']) as String?;
            if (!isRead && type != 'chat' && type != 'message') {
              count++;
            }
          }
          yield count;
        }
      } catch (_) {}

      await Future.delayed(const Duration(seconds: 10));
    }
  }

  /// Get stream of total unread chat messages count across all conversations
  Stream<int> getUnreadChatCount(String handle) async* {
    final clean = handle.replaceAll('@', '').trim();
    if (clean.isEmpty) {
      yield 0;
      return;
    }

    while (true) {
      try {
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/chats?handle=$clean'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final chats = (data['chats'] as List<dynamic>?) ?? [];
          int totalUnread = 0;
          for (final c in chats) {
            final unread = (c['unreadCount'] as num?)?.toInt() ?? 0;
            totalUnread += unread;
          }
          yield totalUnread;
        }
      } catch (_) {}

      await Future.delayed(const Duration(seconds: 10));
    }
  }

  /// Deep linking router
  Future<void> navigateToScreen(Map<String, dynamic> data) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final type = data['type'] as String?;
    
    final prefs = await SharedPreferences.getInstance();
    final currentHandle = await AuthService.instance.getUserHandle() ??
        prefs.getString('user_handle') ??
        'Guest';
    final cleanCurrentHandle = currentHandle.replaceAll('@', '').trim();

    if (!context.mounted) return;

    // ── 1. Post Interactions ──
    if (type == 'post' ||
        type == 'new_post' ||
        type == 'post_like' ||
        type == 'post_comment' ||
        type == 'post_upload' ||
        type == 'mention') {
      final postId = data['postId'] as String?;
      if (postId != null && postId.isNotEmpty) {
        try {
          final locService = LocationService();
          final postRepo = PostRepository(locService);
          postRepo.currentUserHandle = cleanCurrentHandle;
          final post = postRepo.getPostById(postId);
          if (post != null && context.mounted) {
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
    // ── 2. Friend Request ──
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
    // ── 3. Friend Request Accepted ──
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
    // ── 4. Direct / Private Chat ──
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
    // ── 4. Community Message ──
    else if (type == 'community_message' || type == 'community') {
      final communityId = data['communityId'] as String?;
      if (communityId != null && communityId.isNotEmpty) {
        try {
          final commRepo = CommunityRepository()..currentUserHandle = cleanCurrentHandle;
          final community = await commRepo.getCommunityById(communityId, forceRefresh: true);
          if (community != null && context.mounted) {
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
    // ── 5. Community Join Request ──
    else if (type == 'community_join_request') {
      final communityId = data['communityId'] as String?;
      if (communityId != null && communityId.isNotEmpty) {
        try {
          final commRepo = CommunityRepository()..currentUserHandle = cleanCurrentHandle;
          final community = await commRepo.getCommunityById(communityId, forceRefresh: true);
          if (community != null && context.mounted) {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => JoinRequestsScreen(
                  community: community,
                  repository: commRepo,
                ),
              ),
            );
            return;
          }
        } catch (e) {
          debugPrint('Error navigating to join requests: $e');
        }
      }
    }
    // ── 6. Community Request Response ──
    else if (type == 'community_request_response') {
      final communityId = data['communityId'] as String?;
      final approved = data['approved'] == true;
      if (communityId != null && communityId.isNotEmpty && approved) {
        try {
          final commRepo = CommunityRepository()..currentUserHandle = cleanCurrentHandle;
          final community = await commRepo.getCommunityById(communityId, forceRefresh: true);
          if (community != null && context.mounted) {
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
          debugPrint('Error navigating to community: $e');
        }
      }
    }
    // ── 5. Incoming Call ──
    else if (type == 'call') {
      final callId = data['callId'] as String?;
      final callerHandle = (data['callerHandle'] as String?)?.replaceAll('@', '').trim();
      if (callId != null && callId.isNotEmpty) {
        try {
          final res = await http.get(
            Uri.parse('${AuthService.baseUrl}/calls/$callId'),
            headers: {'Content-Type': 'application/json'},
          ).timeout(const Duration(seconds: 4));

          if (res.statusCode == 200) {
            final json = jsonDecode(res.body);
            final callData = json['call'] as Map<String, dynamic>?;
            if (callData != null && context.mounted) {
              final call = CallModel.fromJson(callData);
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
          }
        } catch (e) {
          debugPrint('Error opening call from notification: $e');
        }
      }

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

  /// Dispatch an in-app notification via D1 REST API
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
      final payload = {
        'target_handle': cleanTarget,
        'title': title,
        'body': body,
        'type': data['type'] ?? 'general',
        'sender_handle': data['senderHandle'] ?? data['partnerHandle'],
        'data': data,
      };

      await http.post(
        Uri.parse('${AuthService.baseUrl}/notifications'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));
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

  /// Dedicated high-priority full-screen incoming call notification
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
