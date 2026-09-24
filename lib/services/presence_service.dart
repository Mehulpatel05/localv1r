import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
          ? DateTime.fromMillisecondsSinceEpoch(lastSeenRaw)
          : DateTime.fromMillisecondsSinceEpoch(lastSeenRaw * 1000);
    } else if (lastSeenRaw is String) {
      dt = DateTime.tryParse(lastSeenRaw);
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
  bool _hasInternet = true;

  // Local cache to eliminate UI loading flicker
  final Map<String, UserPresence> _memoryCache = {};

  void init(String? userHandle) {
    if (userHandle == null || userHandle.isEmpty) return;
    _currentUserHandle = userHandle.replaceAll('@', '').trim();

    if (!_isInitialized) {
      WidgetsBinding.instance.addObserver(this);
      _isInitialized = true;
    }

    _loadCacheFromStorage();
    setOnline();

    // Start periodic heartbeat every 30 seconds while app is active
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkInternetAndHeartbeat();
    });
  }

  void updateUserHandle(String userHandle) {
    _currentUserHandle = userHandle.replaceAll('@', '').trim();
    setOnline();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setOnline();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      setOffline();
    }
  }

  Future<void> _checkInternetAndHeartbeat() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      _hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      _hasInternet = false;
    }

    if (_hasInternet) {
      setOnline();
    }
  }

  Future<void> setOnline() async {
    if (_currentUserHandle == null || _currentUserHandle!.isEmpty) return;
    final now = DateTime.now();

    try {
      final payload = {'handle': _currentUserHandle, 'isOnline': true};
      await http.post(
        Uri.parse('${AuthService.baseUrl}/presence/heartbeat'),
        headers: {'Content-Type': 'application/json'},
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
    if (_currentUserHandle == null || _currentUserHandle!.isEmpty) return;
    final now = DateTime.now();

    try {
      final payload = {'handle': _currentUserHandle, 'isOnline': false};
      await http.post(
        Uri.parse('${AuthService.baseUrl}/presence/heartbeat'),
        headers: {'Content-Type': 'application/json'},
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

  /// Live Stream of a partner's presence via periodic REST polling
  Stream<UserPresence> getPresenceStream(String handle) async* {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty) {
      yield const UserPresence(isOnline: false);
      return;
    }

    // Yield initial cached value
    if (_memoryCache.containsKey(cleanHandle)) {
      yield _memoryCache[cleanHandle]!;
    }

    while (true) {
      try {
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/presence/$cleanHandle'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final presence = UserPresence.fromMap(data);
          _memoryCache[cleanHandle] = presence;
          _saveCacheToStorage(cleanHandle, presence);
          yield presence;
        }
      } catch (_) {}

      await Future.delayed(const Duration(seconds: 10));
    }
  }

  /// Get cached presence synchronously for zero flicker
  UserPresence? getCachedPresence(String handle) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    return _memoryCache[cleanHandle];
  }

  /// WhatsApp-style Last Seen Formatter
  static String formatLastSeen(
    UserPresence? presence, {
    bool myPrivacyAllowed = true,
  }) {
    if (presence == null) return 'Offline';

    if (presence.isOnline) {
      return 'Online';
    }

    // If partner has disabled last seen OR current user has disabled their own last seen (WhatsApp reciprocal rule)
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

  Future<void> _loadCacheFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('presence_'));
      for (final key in keys) {
        final raw = prefs.getString(key);
        if (raw != null) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final handle = key.replaceFirst('presence_', '');
          _memoryCache[handle] = UserPresence.fromMap(map);
        }
      }
    } catch (_) {}
  }

  Future<void> _saveCacheToStorage(String handle, UserPresence presence) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {
        'isOnline': presence.isOnline,
        'lastSeen': presence.lastSeen?.millisecondsSinceEpoch,
        'showLastSeen': presence.showLastSeen,
      };
      await prefs.setString('presence_$handle', jsonEncode(map));
    } catch (_) {}
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
      _isInitialized = false;
    }
  }
}
