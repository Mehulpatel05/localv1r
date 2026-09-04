import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/friends/friends_screen.dart';
import '../services/friend_repository.dart';

/// Top-level background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are handled automatically by the system tray.
  debugPrint('BG message: ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Android notification channel
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'vadodara_local_channel',
    'Vadodara Local Notifications',
    description: 'Notifications for friend requests, messages, and more',
    importance: Importance.high,
    playSound: true,
  );

  /// Initialize the notification service. Call once at app start.
  Future<void> initialize() async {
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

    // 5. Listen for foreground messages
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
  }

  /// Save FCM token to Firestore under the current user's document
  Future<void> _saveToken() async {
    final token = await _fcm.getToken();
    if (token != null) {
      await _saveTokenToFirestore(token);
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('FCM token saved: ${token.substring(0, 20)}...');
    }
  }

  /// Show a local notification when a message arrives in the foreground
  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF3B82F6),
        ),
      ),
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }

  /// Called when user taps a notification (foreground local notification)
  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        debugPrint('Notification tapped with data: $data');
        _navigateToScreen(data);
      } catch (_) {}
    }
  }

  /// Called when user taps a notification (background/terminated FCM)
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification opened: ${message.data}');
    _navigateToScreen(message.data);
  }

  Future<void> _navigateToScreen(Map<String, dynamic> data) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final type = data['type'];
    
    // Fetch currentUserHandle from SharedPreferences to pass to screens
    final prefs = await SharedPreferences.getInstance();
    final handle = prefs.getString('user_handle') ?? 'Guest';

    if (type == 'chat') {
      if (context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatListScreen(currentUserHandle: handle)));
      }
    } else if (type == 'friend_request') {
      if (context.mounted) {
        // Need to import FriendRepository and pass it
        // We will just fetch it locally
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => FriendsScreen(
          repository: FriendRepository()..currentUserHandle = handle,
          currentUserHandle: handle,
        )));
      }
    }
  }

  // ── Manual notification sending helpers (for local triggers) ──

  /// Send a local notification immediately (for in-app events)
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
          color: const Color(0xFF3B82F6),
        ),
      ),
      payload: data != null ? jsonEncode(data) : null,
    );
  }
}
