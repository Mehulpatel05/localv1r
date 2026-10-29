import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class UserPresence {
  final bool isOnline;
  final DateTime? lastSeen;
  final bool showLastSeen;

  const UserPresence({
    required this.isOnline,
    this.lastSeen,
    this.showLastSeen = true,
  });

  factory UserPresence.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const UserPresence(isOnline: false);
    }
    final isOnline = map['isOnline'] == true || map['state'] == 'online';
    DateTime? dt;
    final lastSeenRaw = map['lastSeen'] ??
        map['last_seen_at'] ??
        map['lastSeenAt'] ??
        map['last_changed'] ??
        map['lastActive'] ??
        map['updatedAt'] ??
        map['lastOnline'];
    if (lastSeenRaw is int) {
      dt = lastSeenRaw > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(lastSeenRaw, isUtc: true).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(lastSeenRaw * 1000, isUtc: true).toLocal();
    } else if (lastSeenRaw is String) {
      final numVal = int.tryParse(lastSeenRaw);
      if (numVal != null) {
        dt = numVal > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(numVal, isUtc: true).toLocal()
            : DateTime.fromMillisecondsSinceEpoch(numVal * 1000, isUtc: true).toLocal();
      } else {
        final parsed = DateTime.tryParse(lastSeenRaw);
        dt = parsed != null ? (parsed.isUtc ? parsed.toLocal() : parsed) : null;
      }
    }

    final showLastSeen = map['showLastSeen'] != false;
    return UserPresence(
      isOnline: isOnline,
      lastSeen: dt,
      showLastSeen: showLastSeen,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isOnline': isOnline,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
      'showLastSeen': showLastSeen,
    };
  }
}

class PresenceService with WidgetsBindingObserver {
  static final PresenceService instance = PresenceService._internal();
  PresenceService._internal();

  String? _currentUserHandle;
  bool _isInitialized = false;
  Timer? _heartbeatTimer;

  final Map<String, UserPresence> _memoryCache = {};
  final Map<String, StreamController<UserPresence>> _presenceControllers = {};
  final Map<String, Timer?> _presencePollTimers = {};

  void init(String? userHandle) {
    if (userHandle == null || userHandle.isEmpty) return;
    _currentUserHandle = userHandle.replaceAll('@', '').trim();

    if (!_isInitialized) {
      WidgetsBinding.instance.addObserver(this);
      _isInitialized = true;
    }

    setOnline();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkInternetAndHeartbeat();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void updateUserHandle(String userHandle) {
    _currentUserHandle = userHandle.replaceAll('@', '').trim();
    setOnline();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startHeartbeat();
      setOnline();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopHeartbeat();
      setOffline();
    }
  }

  Future<void> _checkInternetAndHeartbeat() async {
    await setOnline();
  }

  Future<void> setOnline() async {
    if (_currentUserHandle == null || _currentUserHandle!.isEmpty) return;
    final now = DateTime.now();

    try {
      final token = await AuthService.instance.getAccessToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final payload = {'handle': _currentUserHandle, 'isOnline': true};
      await http.post(
        Uri.parse('${AuthService.baseUrl}/presence/heartbeat'),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      _memoryCache[_currentUserHandle!] = UserPresence(
        isOnline: true,
        lastSeen: now,
      );
    } catch (e) {
      debugPrint('PresenceService setOnline error: $e');
    }
  }

  Future<void> setOffline() async {
    _stopHeartbeat();
    if (_currentUserHandle == null || _currentUserHandle!.isEmpty) return;
    final now = DateTime.now();

    try {
      final token = await AuthService.instance.getAccessToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final payload = {'handle': _currentUserHandle, 'isOnline': false};
      await http.post(
        Uri.parse('${AuthService.baseUrl}/presence/heartbeat'),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      _memoryCache[_currentUserHandle!] = UserPresence(
        isOnline: false,
        lastSeen: now,
      );
    } catch (e) {
      debugPrint('PresenceService setOffline error: $e');
    }
  }

  Stream<UserPresence> getPresenceStream(String handle) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty) {
      return Stream.value(const UserPresence(isOnline: false));
    }

    final existingController = _presenceControllers[cleanHandle];
    if (existingController != null && !existingController.isClosed) {
      return existingController.stream;
    }

    late StreamController<UserPresence> controller;
    controller = StreamController<UserPresence>.broadcast(
      onListen: () {
        if (_memoryCache.containsKey(cleanHandle)) {
          controller.add(_memoryCache[cleanHandle]!);
        }
        _fetchPresence(cleanHandle, controller);
        _presencePollTimers[cleanHandle]?.cancel();
        _presencePollTimers[cleanHandle] = Timer.periodic(
          const Duration(seconds: 10),
          (_) => _fetchPresence(cleanHandle, controller),
        );
      },
      onCancel: () {
        if (!controller.hasListener) {
          _presencePollTimers[cleanHandle]?.cancel();
          _presencePollTimers.remove(cleanHandle);
          _presenceControllers.remove(cleanHandle);
          controller.close();
        }
      },
    );
    _presenceControllers[cleanHandle] = controller;
    return controller.stream;
  }

  Future<void> _fetchPresence(
    String cleanHandle,
    StreamController<UserPresence> controller,
  ) async {
    if (controller.isClosed) return;
    try {
      final token = await AuthService.instance.getAccessToken();
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/presence/$cleanHandle'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 && !controller.isClosed) {
        final data = jsonDecode(res.body);
        final presence = UserPresence.fromMap(data);
        _memoryCache[cleanHandle] = presence;
        controller.add(presence);
      }
    } catch (_) {}
  }

  UserPresence? getCachedPresence(String handle) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    return _memoryCache[cleanHandle];
  }

  static String formatLastSeen(
    UserPresence? presence, {
    bool myPrivacyAllowed = true,
  }) {
    if (presence == null) return 'Offline';

    if (presence.isOnline) {
      return 'Online';
    }

    if (!presence.showLastSeen || !myPrivacyAllowed) {
      return 'Offline';
    }

    final lastSeen = presence.lastSeen;
    if (lastSeen == null) {
      return 'Offline';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final seenDay = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);
    final diff = today.difference(seenDay).inDays;

    final timeStr = DateFormat('hh:mm a').format(lastSeen);

    if (diff == 0) {
      return 'last seen today at $timeStr';
    } else if (diff == 1) {
      return 'last seen yesterday at $timeStr';
    } else if (diff < 7) {
      final weekday = DateFormat('EEEE').format(lastSeen);
      return 'last seen $weekday at $timeStr';
    } else {
      final dateStr = DateFormat('dd/MM/yyyy').format(lastSeen);
      return 'last seen $dateStr at $timeStr';
    }
  }

  void clearCache() {
    _memoryCache.clear();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    for (final timer in _presencePollTimers.values) {
      timer?.cancel();
    }
    _presencePollTimers.clear();
    for (final controller in _presenceControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _presenceControllers.clear();
    _currentUserHandle = '';
  }

  void dispose() {
    clearCache();
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
      _isInitialized = false;
    }
  }
}
