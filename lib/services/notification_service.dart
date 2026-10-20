import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/personal_chat_screen.dart';
import '../screens/detail/post_detail_screen.dart';
import '../services/auth_service.dart';
import '../services/friend_repository.dart';
import '../services/post_repository.dart';
import '../core/widgets/in_app_notification_banner.dart';
import '../models/call_model.dart';
import '../models/post_model.dart';
import '../screens/chat/incoming_call_screen.dart';
import '../screens/profile/widgets/support_request_sheet.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../core/services/name_cache_service.dart';
import '../screens/rewards/rewards_hub_screen.dart';
import 'rewards_service.dart';
import '../core/splash_controller.dart';
import 'chat_preferences_service.dart';
import 'direct_chat_service.dart';
import '../models/chat_conversation_model.dart';

/// Top-level background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('BG message received: ${message.notification?.title} | data: ${message.data}');
  final type = message.data['type']?.toString();

  if (type == 'call_cancelled' || type == 'call_ended') {
    final callId = message.data['callId']?.toString();
    if (callId != null && callId.isNotEmpty) {
      NotificationService.instance.cancelCallNotification(callId);
      IncomingCallScreen.dismissCall(callId);
    }
    return;
  }

  if (message.notification == null && type != 'call') {
    final rawTitle = (message.data['title'] as String?)?.trim() ?? '';
    final rawBody = (message.data['body'] as String?)?.trim() ?? '';
    final title = rawTitle.isNotEmpty ? rawTitle : 'Nearhood';
    final body = rawBody.isNotEmpty
        ? rawBody
        : (type == 'chat' || type == 'message'
            ? 'Sent you a message'
            : (type == 'post_comment'
                ? 'Commented on your post'
                : (type == 'post_like'
                    ? 'Liked your post'
                    : (type == 'friend_request'
                        ? 'Sent you a friend request'
                        : (type == 'friend_accept' || type == 'friend_accepted'
                            ? 'Accepted your friend request'
                            : (type == 'post_upload'
                                ? 'Your post is now live in Nearhood!'
                                : 'You have a new notification'))))));
    final localNotifs = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    await localNotifs.initialize(settings: const InitializationSettings(android: androidInit));
    await localNotifs.show(
      id: (message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) & 0x7FFFFFFF,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.channel.id,
          NotificationService.channel.name,
          channelDescription: NotificationService.channel.description,
          importance: Importance.max,
          priority: Priority.max,
          icon: '@drawable/ic_notification',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  debugPrint('BG FCM notification handled: $type');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  static NotificationService get instance => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  Timer? _pollingTimer;

  /// Guards against a second initialize() registering duplicate FCM stream
  /// listeners. main.dart calls initialize() from two places (cold-start
  /// bootstrap and the onLoggedIn callback); without this guard a re-login in
  /// the same process would attach onMessage/onMessageOpenedApp twice and every
  /// notification tap would push the destination screen twice.
  bool _initialized = false;

  /// Currently open chat partner handle (to suppress heads-up notification while chatting)
  String? activeChatPartnerHandle;

  /// Currently open community ID (to suppress heads-up notification while in that community)
  String? activeCommunityId;

  final ValueNotifier<int> unreadBadgeNotifier = ValueNotifier<int>(0);

  Future<int> prefetchBadgeCounts(String userHandle) async {
    final clean = userHandle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return 0;

    try {
      final token = await AuthService.instance.getAccessToken();
      final uri = Uri.parse('${AuthService.baseUrl}/actions/counters?handle=$clean');
      final res = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final counters = body['counters'] as Map<String, dynamic>? ?? {};
        final unread = (counters['unreadNotifications'] as int?) ?? 0;
        unreadBadgeNotifier.value = unread;
        return unread;
      }

      final fallbackRes = await http.get(
        Uri.parse('${AuthService.baseUrl}/notifications?handle=$clean'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 4));

      if (fallbackRes.statusCode == 200) {
        final data = jsonDecode(fallbackRes.body);
        final notifs = (data['notifications'] as List<dynamic>?) ?? [];
        int count = 0;
        for (final raw in notifs) {
          final notif = raw as Map<String, dynamic>;
          final isRead = notif['isRead'] == true || notif['is_read'] == 1 || notif['is_read'] == true;
          final payloadData = (notif['data'] as Map<String, dynamic>?) ?? {};
          final type = payloadData['type'] as String? ?? notif['type'] as String?;
          if (!isRead && type != 'chat' && type != 'message') {
            count++;
          }
        }
        unreadBadgeNotifier.value = count;
        return count;
      }
    } catch (e) {
      debugPrint('[NotificationService] prefetchBadgeCounts error: $e');
    }
    return unreadBadgeNotifier.value;
  }

  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'nearhood_channel',
    'Nearhood Notifications',
    description: 'Notifications for friend requests, messages, posts, and communities',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );
  static const AndroidNotificationChannel _channel = channel;

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
      // ── One-time setup: permissions, channels and stream listeners ──
      // Re-running these would attach a second onMessage/onMessageOpenedApp
      // listener and every tap would navigate twice.
      if (!_initialized) {
        // 0. Read the launch message FIRST.
        //    When the app was terminated and the user taps a notification,
        //    Android starts MainActivity with the FCM payload attached and this
        //    is the only way to recover it. It must be read before
        //    requestPermission() below, because on a fresh install that call
        //    blocks on the OS permission dialog — if the user leaves the dialog
        //    sitting there, the tap that launched the app would never be handled.
        final initialMessage = await _fcm.getInitialMessage();

        // 1. Request FCM permission
        final settings = await _fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        debugPrint('Notification permission: ${settings.authorizationStatus}');

        // 2. Initialize local notifications
        const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
        await _localNotifications.initialize(
          settings: const InitializationSettings(android: androidInit),
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );

        final localLaunchDetails = await _localNotifications.getNotificationAppLaunchDetails();

        // 3. Request Android 13+ runtime notification permission & create channels
        final androidPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
        await androidPlugin?.createNotificationChannel(_channel);
        await androidPlugin?.createNotificationChannel(_callChannel);

        // 4. Set foreground notification presentation options.
        //    alert: FALSE — prevents FCM from auto-showing a system-tray banner
        //    in the foreground. We show our own in-app banner via onMessage listener.
        //    (On iOS alert:true would show a system notification AND our local one → duplicates)
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );

        // 5. Listen for foreground FCM messages
        FirebaseMessaging.onMessage.listen(_showForegroundNotification);

        // 6. Listen for notification taps while the app is in the background
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

        // 7. Keep the backend's copy of the token current
        _fcm.onTokenRefresh.listen((newToken) {
          debugPrint('[NotificationService] Refreshed FCM Token: $newToken');
          _syncFcmToken(newToken);
        });

        _initialized = true;

        if (initialMessage != null) {
          debugPrint('[NotificationService] Cold-start launch message: ${initialMessage.data}');
          _handleNotificationTap(initialMessage);
        } else if (localLaunchDetails?.didNotificationLaunchApp ?? false) {
          final payload = localLaunchDetails?.notificationResponse?.payload;
          if (payload != null && payload.isNotEmpty) {
            try {
              final raw = jsonDecode(payload) as Map<String, dynamic>;
              final normalized = _normalizePayload(raw);
              _navigateWhenReady(normalized);
            } catch (e) {
              debugPrint('[NotificationService] Error parsing launch payload: $e');
            }
          }
        }
      }

      // ── Per-call: bind the *current* user ──
      // This must run on every initialize(), including the second call made
      // after a fresh login, otherwise that user's device token is never
      // registered and they receive no pushes at all.
      try {
        final fcmToken = await _fcm.getToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          debugPrint('[NotificationService] Registered FCM Token: $fcmToken');
          _syncFcmToken(fcmToken);
        }
      } catch (e) {
        debugPrint('[NotificationService] Error retrieving FCM token: $e');
      }

      // Start polling realtime notifications for the logged-in user.
      // startListening() cancels any previous timer, so this is safe to repeat.
      final currentHandle = await AuthService.instance.getUserHandle();
      if (currentHandle != null && currentHandle.isNotEmpty) {
        startListening(currentHandle);
      }
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  Future<void> _syncFcmToken(String fcmToken) async {
    try {
      final currentHandle = await AuthService.instance.getUserHandle();
      final cleanHandle = currentHandle?.replaceAll('@', '').trim();
      if (cleanHandle == null || cleanHandle.isEmpty || cleanHandle == 'Guest') return;

      var token = await AuthService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        token = await AuthService.instance.refreshToken();
      }
      if (token == null || token.isEmpty) return;

      final uri = Uri.parse('${AuthService.baseUrl}/users/fcm-token');
      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'handle': cleanHandle,
          'fcm_token': fcmToken,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[NotificationService] _syncFcmToken error: $e');
    }
  }

  Future<void> syncFcmTokenForUser(String userHandle) async {
    try {
      final fcmToken = await _fcm.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        final cleanHandle = userHandle.replaceAll('@', '').trim();
        if (cleanHandle.isEmpty || cleanHandle == 'Guest') return;

        var token = await AuthService.instance.getAccessToken();
        if (token == null || token.isEmpty) {
          token = await AuthService.instance.refreshToken();
        }
        if (token == null || token.isEmpty) return;

        final uri = Uri.parse('${AuthService.baseUrl}/users/fcm-token');
        await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'handle': cleanHandle,
            'fcm_token': fcmToken,
          }),
        ).timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      debugPrint('[NotificationService] syncFcmTokenForUser error: $e');
    }
  }

  /// Check if user has enabled alerts for this notification category
  Future<bool> _checkIfCategoryAllowed(String? type) async {
    final prefs = await SharedPreferences.getInstance();
    if (type == 'chat' || type == 'message') {
      return prefs.getBool('notif_chat_enabled') ?? true;
    } else if (type == 'friend_request' || type == 'friend_accept' || type == 'friend_accepted' || type == 'friend') {
      return prefs.getBool('notif_friends_enabled') ?? true;
    } else if (type == 'community_message' || type == 'community' || type == 'community_join_request' || type == 'community_request_response') {
      return prefs.getBool('notif_communities_enabled') ?? true;
    } else if (type == 'post' || type == 'new_post' || type == 'post_like' || type == 'post_comment' || type == 'post_upload') {
      return prefs.getBool('notif_posts_enabled') ?? true;
    }
    return true;
  }

  // Tracks IDs of notifications already shown — prevents duplicates between
  // FCM foreground handler and the 3-sec polling loop.
  // Capped at 500 entries to avoid unbounded memory growth.
  final Set<String> _processedNotificationIds = {};

  void _addProcessed(String id) {
    if (_processedNotificationIds.length >= 500) {
      // Remove oldest ~100 entries (Set doesn't have index, so take/skip trick)
      final toRemove = _processedNotificationIds.take(100).toList();
      _processedNotificationIds.removeAll(toRemove);
    }
    _processedNotificationIds.add(id);
  }

  String _extractNotifId(Map<String, dynamic> notif) {
    final id = notif['id'] ?? notif['_id'] ?? notif['notification_id'] ?? notif['doc_id'];
    if (id != null && id.toString().trim().isNotEmpty) {
      return id.toString().trim();
    }
    // Fallback: composite key from content + timestamp
    final title = notif['title'] ?? '';
    final body  = notif['body']  ?? '';
    final time  = notif['timestamp'] ?? notif['createdAt'] ?? notif['created_at'] ?? '';
    return '${title}_${body}_$time';
  }

  void startListening(String handle) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty) return;

    syncFcmTokenForUser(cleanHandle);

    _pollingTimer?.cancel();
    bool isInitialTick = true;

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final token = await AuthService.instance.getAccessToken();
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/notifications?handle=$cleanHandle'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final notifs = (data['notifications'] as List<dynamic>?) ?? [];

          int unreadCount = 0;
          for (final raw in notifs) {
            final notif = raw as Map<String, dynamic>;
            final isRead = notif['isRead'] == true || notif['is_read'] == 1 || notif['is_read'] == true;
            final payloadData = (notif['data'] as Map<String, dynamic>?) ?? {};
            final type = payloadData['type'] as String? ?? notif['type'] as String?;
            if (!isRead && type != 'chat' && type != 'message') {
              unreadCount++;
            }
          }
          unreadBadgeNotifier.value = unreadCount;

          if (isInitialTick) {
            for (final raw in notifs) {
              final notif = raw as Map<String, dynamic>;
              final docId = _extractNotifId(notif);
              if (docId.isNotEmpty) {
                _addProcessed(docId);
              }
              final rawT = (notif['title'] as String?)?.trim() ?? '';
              final rawB = (notif['body'] as String?)?.trim() ?? '';
              if (rawT.isNotEmpty || rawB.isNotEmpty) {
                _addProcessed('${rawT}_$rawB');
              }
              final pData = (notif['data'] as Map<String, dynamic>?) ?? {};
              final mId = (pData['messageId'] ?? pData['id'] ?? pData['notifId'])?.toString();
              if (mId != null && mId.isNotEmpty) {
                _addProcessed(mId);
              }
            }
            isInitialTick = false;
            return;
          }

          for (final raw in notifs) {
            final notif = raw as Map<String, dynamic>;
            final docId = _extractNotifId(notif);
            final payloadData = (notif['data'] as Map<String, dynamic>?) ?? {};
            final type = payloadData['type'] as String? ?? notif['type'] as String?;
            final rawTitle = (notif['title'] as String?)?.trim() ?? '';
            final title = rawTitle.isNotEmpty ? rawTitle : 'Nearhood';
            final rawBody = (notif['body'] as String?)?.trim() ?? '';
            final body = rawBody.isNotEmpty
                ? rawBody
                : (type == 'chat' || type == 'message'
                    ? 'Sent you a message'
                    : (type == 'post_comment'
                        ? 'Commented on your post'
                        : (type == 'post_like'
                            ? 'Liked your post'
                            : (type == 'friend_request'
                                ? 'Sent you a friend request'
                                : (type == 'friend_accept' || type == 'friend_accepted'
                                    ? 'Accepted your friend request'
                                    : (type == 'post_upload'
                                        ? 'Your post is now live in Nearhood!'
                                        : 'You have a new notification'))))));

            final titleBodyKey = '${title}_$body';
            final mId = (payloadData['messageId'] ?? payloadData['id'] ?? payloadData['notifId'])?.toString();

            if (docId.isNotEmpty && _processedNotificationIds.contains(docId)) continue;
            if (_processedNotificationIds.contains(titleBodyKey)) continue;
            if (mId != null && mId.isNotEmpty && _processedNotificationIds.contains(mId)) continue;

            if (docId.isNotEmpty) _addProcessed(docId);
            _addProcessed(titleBodyKey);
            if (mId != null && mId.isNotEmpty) _addProcessed(mId);

            final isRead = notif['isRead'] == true || notif['is_read'] == 1 || notif['is_read'] == true;
            if (isRead) continue;

            if (type == 'call_cancelled' || type == 'call_ended') {
              final callId = (payloadData['callId'] ?? notif['callId'])?.toString();
              if (callId != null && callId.isNotEmpty) {
                cancelCallNotification(callId);
                IncomingCallScreen.dismissCall(callId);
              }
              continue;
            }

            if (type == 'friend_request' || type == 'friend_accept' || type == 'friend_rejected' || type == 'friend') {
              FriendRepository.instance.refreshAll().catchError((_) {});
            } else if (type == 'chat' || type == 'message') {
              DirectChatService.instance.getChats(cleanHandle).catchError((_) => <ChatConversation>[]);
            }

            final isAllowed = await _checkIfCategoryAllowed(type);
            if (!isAllowed) continue;

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

            final isEmergency = type == 'safety_alert' ||
                payloadData['isEmergency'] == true ||
                payloadData['isEmergency'] == 'true' ||
                notif['isEmergency'] == true ||
                notif['isEmergency'] == 'true';

            if (isEmergency) {
              HapticFeedback.heavyImpact();
              SystemSound.play(SystemSoundType.alert);
            } else {
              HapticFeedback.lightImpact();
            }

            final notifPayload = payloadData.isNotEmpty ? payloadData : notif;
            final notifIdInt = (docId.hashCode ^ DateTime.now().millisecondsSinceEpoch) & 0x7FFFFFFF;

            ByteArrayAndroidBitmap? largeIconBitmap;
            final avatarUrl = (payloadData['senderAvatarUrl'] ?? payloadData['avatarUrl'] ?? payloadData['imageUrl'] ?? notif['avatarUrl'])?.toString().trim();
            if (avatarUrl != null && avatarUrl.isNotEmpty && (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://'))) {
              try {
                final imgRes = await http.get(Uri.parse(avatarUrl)).timeout(const Duration(seconds: 2));
                if (imgRes.statusCode == 200 && imgRes.bodyBytes.isNotEmpty) {
                  largeIconBitmap = ByteArrayAndroidBitmap(imgRes.bodyBytes);
                }
              } catch (_) {}
            }

            if (type != 'call') {
              _localNotifications.show(
                id: notifIdInt,
                title: title,
                body: body,
                notificationDetails: NotificationDetails(
                  android: AndroidNotificationDetails(
                    channel.id,
                    channel.name,
                    channelDescription: channel.description,
                    importance: Importance.max,
                    priority: Priority.max,
                    icon: '@drawable/ic_notification',
                    largeIcon: largeIconBitmap,
                    playSound: true,
                    enableVibration: true,
                  ),
                ),
                payload: jsonEncode(notifPayload),
              );
            }

            final currentContext = navigatorKey.currentContext;
            if (type != 'call' && currentContext != null && currentContext.mounted) {
              final sender = (payloadData['senderHandle'] ?? payloadData['partnerHandle'] as String?)?.replaceAll('@', '').trim();
              InAppNotificationBanner.show(
                currentContext,
                title: title,
                body: body,
                handle: sender,
                isEmergency: isEmergency,
                onTap: () => navigateToScreen(notifPayload),
              );
            }
          }
        }
      } catch (_) {}
    });
  }

  void stopListening() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _processedNotificationIds.clear();
    unreadBadgeNotifier.value = 0;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final type = message.data['type']?.toString();

    if (type == 'call_cancelled' || type == 'call_ended') {
      final callId = message.data['callId']?.toString();
      if (callId != null && callId.isNotEmpty) {
        cancelCallNotification(callId);
        IncomingCallScreen.dismissCall(callId);
      }
      return;
    }

    final fcmMsgId = message.messageId ?? '';
    if (fcmMsgId.isNotEmpty) {
      _addProcessed(fcmMsgId);
    }
    final rawId = (message.data['id'] ?? message.data['notifId'] ?? message.data['notification_id'])?.toString();
    if (rawId != null && rawId.isNotEmpty) {
      _addProcessed(rawId);
    }
    final mId = message.data['messageId']?.toString();
    if (mId != null && mId.isNotEmpty) {
      _addProcessed(mId);
    }

    final notification = message.notification;
    final rawTitle = (notification?.title ?? (message.data['title'] as String?))?.trim() ?? '';
    final title = rawTitle.isNotEmpty ? rawTitle : 'Nearhood';
    final rawBody = (notification?.body ?? (message.data['body'] as String?))?.trim() ?? '';
    final body = rawBody.isNotEmpty
        ? rawBody
        : (type == 'chat' || type == 'message'
            ? 'Sent you a message'
            : (type == 'post_comment'
                ? 'Commented on your post'
                : (type == 'post_like'
                    ? 'Liked your post'
                    : (type == 'friend_request'
                        ? 'Sent you a friend request'
                        : (type == 'friend_accept' || type == 'friend_accepted'
                            ? 'Accepted your friend request'
                            : (type == 'post_upload'
                                ? 'Your post is now live in Nearhood!'
                                : 'You have a new notification'))))));

    _addProcessed('${title}_$body');

    if (type == 'call') {
      _localNotifications.show(
        id: (message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) & 0x7FFFFFFF,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _callChannel.id, _callChannel.name,
            channelDescription: _callChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            icon: '@drawable/ic_notification',
            fullScreenIntent: true,
            category: AndroidNotificationCategory.call,
            audioAttributesUsage: AudioAttributesUsage.voiceCommunication,
          ),
        ),
        payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
      );
      return;
    }

    final isEmergency = type == 'safety_alert' ||
        message.data['isEmergency'] == true ||
        message.data['isEmergency'] == 'true';

    if (isEmergency) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    }

    final sender = (message.data['senderHandle'] ?? message.data['partnerHandle'] as String?)
        ?.replaceAll('@', '')
        .trim();

    if ((type == 'chat' || type == 'message') &&
        sender != null &&
        sender.toLowerCase() == activeChatPartnerHandle?.toLowerCase()) {
      return;
    }

    ByteArrayAndroidBitmap? largeIconBitmap;
    final avatarUrl = (message.data['senderAvatarUrl'] ?? message.data['avatarUrl'] ?? message.data['imageUrl'] ?? notification?.android?.imageUrl)?.toString().trim();
    if (avatarUrl != null && avatarUrl.isNotEmpty && (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://'))) {
      try {
        final imgRes = await http.get(Uri.parse(avatarUrl)).timeout(const Duration(seconds: 2));
        if (imgRes.statusCode == 200 && imgRes.bodyBytes.isNotEmpty) {
          largeIconBitmap = ByteArrayAndroidBitmap(imgRes.bodyBytes);
        }
      } catch (_) {}
    }

    _localNotifications.show(
      id: (message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) & 0x7FFFFFFF,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.max,
          icon: '@drawable/ic_notification',
          largeIcon: largeIconBitmap,
        ),
      ),
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );

    final currentContext = navigatorKey.currentContext;
    if (currentContext != null && currentContext.mounted) {
      InAppNotificationBanner.show(
        currentContext,
        title: title,
        body: body,
        handle: sender,
        isEmergency: isEmergency,
        onTap: () => navigateToScreen(message.data),
      );
    }
  }

  /// Called when user taps a notification (foreground local notification)
  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final raw = jsonDecode(response.payload!) as Map<String, dynamic>;
        debugPrint('[NotificationService] Local notification tapped. Raw: $raw');
        final normalized = _normalizePayload(raw);
        _navigateWhenReady(normalized);
      } catch (e) {
        debugPrint('[NotificationService] Error parsing notification payload: $e');
      }
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[NotificationService] Notification tapped. Raw data: ${message.data}');
    final normalized = _normalizePayload(message.data);
    debugPrint('[NotificationService] Normalized payload: $normalized');
    _navigateWhenReady(normalized);
  }

  Map<String, dynamic> _normalizePayload(Map<String, dynamic> raw) {
    final result = Map<String, dynamic>.from(raw);

    final nestedRaw = raw['data'] ?? raw['payload'] ?? raw['payload_json'];
    if (nestedRaw is Map<String, dynamic> && nestedRaw.isNotEmpty) {
      nestedRaw.forEach((k, v) => result.putIfAbsent(k, () => v));
    } else if (nestedRaw is String && nestedRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(nestedRaw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((k, v) => result.putIfAbsent(k, () => v));
        }
      } catch (_) {}
    }

    if (result['type'] == null) {
      final topType = raw['type']?.toString() ??
          raw['notification_type']?.toString() ??
          raw['category']?.toString();
      if (topType != null) result['type'] = topType;
    }

    return result;
  }

  void _navigateWhenReady(Map<String, dynamic> data, {int attempts = 0}) async {
    final navState = navigatorKey.currentState;
    var userHandle = await AuthService.instance.getUserHandle();
    if (userHandle == null || userHandle.isEmpty || userHandle == 'Guest') {
      try {
        final prefs = await SharedPreferences.getInstance();
        userHandle = prefs.getString('user_handle') ??
            prefs.getString('current_user_handle') ??
            prefs.getString('active_user_handle');
      } catch (_) {}
    }
    if (userHandle == null || userHandle.isEmpty || userHandle == 'Guest') {
      final repoHandle = PostRepository.instance.currentUserHandle;
      if (repoHandle.isNotEmpty && repoHandle != 'Guest') {
        userHandle = repoHandle;
      }
    }

    final hasUser = userHandle != null && userHandle.isNotEmpty && userHandle != 'Guest';
    final isFlowReady = SplashController.instance.isMainFlowVisible;

    if (navState != null && hasUser && isFlowReady) {
      navigateToScreen(data);
    } else if (attempts < 30) {
      Future.delayed(const Duration(milliseconds: 200), () {
        _navigateWhenReady(data, attempts: attempts + 1);
      });
    } else if (navState != null && hasUser) {
      navigateToScreen(data);
    } else {
      debugPrint('[NotificationService] Navigator not ready after retries, skipping tap navigation.');
    }
  }

  Stream<int> getUnreadNotificationCount(String handle) async* {
    final clean = handle.replaceAll('@', '').trim();
    if (clean.isEmpty) {
      yield 0;
      return;
    }

    while (true) {
      try {
        final token = await AuthService.instance.getAccessToken();
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/notifications?handle=$clean'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
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

  Stream<int> getUnreadChatCount(String handle) async* {
    final clean = handle.replaceAll('@', '').trim();
    if (clean.isEmpty) {
      yield 0;
      return;
    }

    while (true) {
      try {
        final token = await AuthService.instance.getAccessToken();
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/chats?handle=$clean'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
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

  Future<void> navigateToScreen(Map<String, dynamic> data, {bool fromNotificationCenter = false}) async {
    final navState = navigatorKey.currentState;
    if (navState == null) return;

    final type = (data['type'] ?? data['notification_type'] ?? data['category'])?.toString().toLowerCase().trim();

    var currentHandle = await AuthService.instance.getUserHandle();
    if (currentHandle == null || currentHandle.isEmpty || currentHandle == 'Guest') {
      try {
        final prefs = await SharedPreferences.getInstance();
        currentHandle = prefs.getString('user_handle') ??
            prefs.getString('current_user_handle') ??
            prefs.getString('active_user_handle');
      } catch (_) {}
    }
    if (currentHandle == null || currentHandle.isEmpty || currentHandle == 'Guest') {
      final repoHandle = PostRepository.instance.currentUserHandle;
      if (repoHandle.isNotEmpty && repoHandle != 'Guest') {
        currentHandle = repoHandle;
      }
    }
    final cleanCurrentHandle = (currentHandle ?? 'Guest').replaceAll('@', '').trim();

    if (cleanCurrentHandle.isEmpty || cleanCurrentHandle == 'Guest') {
      debugPrint('[NotificationService] Tap ignored — no signed-in user.');
      return;
    }

    final notifId = (data['notification_id'] ?? data['notifId'] ?? data['doc_id'])?.toString().trim();
    if (notifId != null && notifId.isNotEmpty && cleanCurrentHandle.isNotEmpty) {
      AuthService.instance.getAccessToken().then((token) {
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
        http.post(
          Uri.parse('${AuthService.baseUrl}/notifications/$notifId/read?handle=$cleanCurrentHandle'),
          headers: headers,
        ).catchError((_) => http.Response('', 500));
      });
      if (unreadBadgeNotifier.value > 0) {
        unreadBadgeNotifier.value--;
      }
    }

    final partnerHandle = (data['senderHandle'] ??
            data['sender_handle'] ??
            data['partnerHandle'] ??
            data['partner_handle'] ??
            data['callerHandle'] ??
            data['caller_handle'] ??
            data['authorHandle'] ??
            data['author_handle'] ??
            data['sender'] ??
            data['from'] ??
            data['handle'] ??
            data['userHandle'] ??
            data['user_handle'])
        ?.toString()
        .replaceAll('@', '')
        .trim();

    final postId = (data['postId'] ??
            data['post_id'] ??
            data['targetId'] ??
            data['target_id'] ??
            data['id'])
        ?.toString()
        .trim();

    void goToNotifications() {
      if (fromNotificationCenter) return;
      navState.push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationsScreen(currentUserHandle: cleanCurrentHandle),
        ),
      );
    }

    if (type == 'post' ||
        type == 'new_post' ||
        type == 'post_like' ||
        type == 'comment_like' ||
        type == 'post_comment' ||
        type == 'post_upload' ||
        type == 'mention' ||
        type == 'like' ||
        type == 'comment') {
      if (postId != null && postId.isNotEmpty) {
        try {
          final postRepo = PostRepository.instance;
          postRepo.currentUserHandle = cleanCurrentHandle;
          Post? post = postRepo.getPostById(postId);
          post ??= await postRepo.fetchPostById(postId);
          if (post != null) {
            navState.push(
              MaterialPageRoute<void>(
                builder: (_) => PostDetailScreen(
                  post: post!,
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
      goToNotifications();
    } else if (type == 'friend_request' || type == 'friend_req' || type == 'friend_accepted' || type == 'friend_accept' || type == 'friend') {
      if (partnerHandle != null && partnerHandle.isNotEmpty) {
        navState.push(
          MaterialPageRoute<void>(
            builder: (_) => PersonalChatScreen(
              currentUserHandle: cleanCurrentHandle,
              partnerHandle: partnerHandle,
            ),
          ),
        );
      } else {
        goToNotifications();
      }
    } else if (type == 'chat' || type == 'message' || type == 'personal_chat' || type == 'direct_chat') {
      if (partnerHandle != null && partnerHandle.isNotEmpty) {
        if (activeChatPartnerHandle?.toLowerCase() == partnerHandle.toLowerCase()) {
          return;
        }
        navState.push(
          MaterialPageRoute<void>(
            builder: (_) => PersonalChatScreen(
              currentUserHandle: cleanCurrentHandle,
              partnerHandle: partnerHandle,
            ),
          ),
        );
      } else {
        navState.push(
          MaterialPageRoute<void>(
            builder: (_) => ChatListScreen(
              currentUserHandle: cleanCurrentHandle,
            ),
          ),
        );
      }
    } else if (type == 'community_message' || type == 'community' || type == 'group_chat') {
      navState.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatListScreen(
            currentUserHandle: cleanCurrentHandle,
          ),
        ),
      );
    } else if (type == 'call') {
      final callId = data['callId']?.toString();
      if (callId != null && callId.isNotEmpty) {
        try {
          final res = await http.get(
            Uri.parse('${AuthService.baseUrl}/calls/$callId'),
            headers: {'Content-Type': 'application/json'},
          ).timeout(const Duration(seconds: 4));

          if (res.statusCode == 200) {
            final json = jsonDecode(res.body);
            final callData = json['call'] as Map<String, dynamic>?;
            if (callData != null) {
              final call = CallModel.fromJson(callData);
              if (call.status == CallStatus.calling || call.status == CallStatus.ringing) {
                navState.push(
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

      if (partnerHandle != null && partnerHandle.isNotEmpty) {
        navState.push(
          MaterialPageRoute<void>(
            builder: (_) => PersonalChatScreen(
              currentUserHandle: cleanCurrentHandle,
              partnerHandle: partnerHandle,
            ),
          ),
        );
      } else {
        goToNotifications();
      }
    } else if (type == 'support' || type == 'ticket' || type == 'support_ticket' || type == 'feedback') {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        SupportRequestSheet.show(
          ctx,
          userHandle: cleanCurrentHandle,
          initialTab: 1,
        );
      } else {
        goToNotifications();
      }
    } else if (type == 'broadcast' || type == 'safety_alert' || type == 'alert') {
      final broadcastTitle = data['title'] as String? ?? 'Nearhood City Alert';
      final broadcastBody = data['body'] as String? ?? data['message'] as String? ?? '';
      final broadcastArea = data['area'] as String? ?? 'All Vadodara';
      final isEmergency = type == 'safety_alert' || data['isEmergency'] == true || data['isEmergency'] == 'true';

      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        showDialog<void>(
          context: ctx,
          builder: (dialogCtx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: isEmergency ? const Color(0xFF1E0707) : null,
            title: Row(
              children: [
                Icon(
                  isEmergency ? Icons.warning_amber_rounded : Icons.campaign_rounded,
                  color: isEmergency ? const Color(0xFFFF5252) : const Color(0xFF2DD4BF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    broadcastTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isEmergency ? const Color(0xFFFF5252) : null,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  broadcastBody,
                  style: TextStyle(
                    fontSize: 14,
                    color: isEmergency ? const Color(0xFFFFCDD2) : null,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isEmergency ? const Color(0xFF451111) : Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Area: $broadcastArea',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isEmergency ? const Color(0xFFFF8A80) : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: Text(
                  'Dismiss',
                  style: TextStyle(
                    color: isEmergency ? const Color(0xFFFF5252) : const Color(0xFF2DD4BF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        if (!fromNotificationCenter) {
          goToNotifications();
        }
      }
    } else if (type == 'reward' ||
        type == 'badge' ||
        type == 'streak' ||
        type == 'points' ||
        type == 'rewards' ||
        type == 'helpful') {
      if (RewardsService.isRewardsEnabled) {
        navState.push(
          MaterialPageRoute<void>(
            builder: (_) => RewardsHubScreen(currentUserHandle: cleanCurrentHandle),
          ),
        );
      } else if (!fromNotificationCenter) {
        goToNotifications();
      }
    } else if (type == 'founding_approved' ||
        type == 'founding_rejected' ||
        type == 'founding' ||
        type == 'founder') {
      navState.push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(
            repository: PostRepository.instance,
            currentUserHandle: cleanCurrentHandle,
          ),
        ),
      );
    } else {
      if (!fromNotificationCenter) {
        goToNotifications();
      }
    }
  }


  // ── Dispatch & Helper Methods ──

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
      final token = await AuthService.instance.getAccessToken();
      final sender = (data['senderHandle'] ?? data['partnerHandle'] ?? '').toString();
      final type = (data['type'] ?? 'general').toString();

      final flatData = <String, String>{
        'type': type,
        if (sender.isNotEmpty) 'senderHandle': sender,
        if (sender.isNotEmpty) 'partnerHandle': sender,
      };
      data.forEach((k, v) {
        if (v != null) flatData[k] = v.toString();
      });
      flatData['data'] = jsonEncode(data);

      final payload = {
        'target_handle': cleanTarget,
        'title': title,
        'body': body,
        'type': type,
        'sender_handle': sender,
        'data': flatData,
      };

      await http.post(
        Uri.parse('${AuthService.baseUrl}/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
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
            icon: '@drawable/ic_notification',
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
    final title = getDisplayName(callerClean);
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
            icon: '@drawable/ic_notification',
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
