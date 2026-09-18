import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

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
        map['last_changed'] ??
        map['lastActive'] ??
        map['updatedAt'] ??
        map['lastOnline'];
    if (lastSeenRaw is Timestamp) {
      dt = lastSeenRaw.toDate();
    } else if (lastSeenRaw is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(lastSeenRaw);
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
      'lastSeen': lastSeen != null ? Timestamp.fromDate(lastSeen!) : null,
      'showLastSeen': showLastSeen,
    };
  }
}

class PresenceService with WidgetsBindingObserver {
  static final PresenceService instance = PresenceService._internal();
  PresenceService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _currentUserHandle;
  String? _currentUid;
  bool _isInitialized = false;
  Timer? _heartbeatTimer;
  bool _hasInternet = true;

  // Local cache to eliminate UI loading flicker
  final Map<String, UserPresence> _memoryCache = {};

  void init(String? userHandle) {
    if (userHandle == null || userHandle.isEmpty) return;
    _currentUserHandle = userHandle.replaceAll('@', '').trim();
    _currentUid = _auth.currentUser?.uid;

    if (!_isInitialized) {
      WidgetsBinding.instance.addObserver(this);
      _isInitialized = true;
    }

    _loadCacheFromStorage();
    setOnline();

    // Start periodic heartbeat every 2 minutes while app is active
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _checkInternetAndHeartbeat();
    });
  }

  void updateUserHandle(String userHandle) {
    _currentUserHandle = userHandle.replaceAll('@', '').trim();
    _currentUid = _auth.currentUser?.uid;
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
      // 1. Update Firestore profile doc
      await _firestore.collection('profiles').doc(_currentUserHandle).set({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'ownerUid': _currentUid ?? _auth.currentUser?.uid,
      }, SetOptions(merge: true));

      // 2. Sync to RTDB via REST if project exists
      _syncRtdb(state: 'online');

      // Update local memory cache
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
      // 1. Update Firestore profile doc
      await _firestore.collection('profiles').doc(_currentUserHandle).set({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. Sync to RTDB
      _syncRtdb(state: 'offline');

      // Update local memory cache
      _memoryCache[_currentUserHandle!] = UserPresence(
        isOnline: false,
        lastSeen: now,
      );
    } catch (e) {
      debugPrint('PresenceService setOffline error: $e');
    }
  }

  void _syncRtdb({required String state}) async {
    final uid = _currentUid ?? _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final uri = Uri.parse(
          'https://local1-e61cb-default-rtdb.firebaseio.com/status/$uid.json');
      await http.put(
        uri,
        body: jsonEncode({
          'state': state,
          'last_changed': {'.sv': 'timestamp'},
          'handle': _currentUserHandle,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Gracefully ignore RTDB REST timeout/absence
    }
  }

  /// Live Stream of a partner's presence
  Stream<UserPresence> getPresenceStream(String handle) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty) {
      return Stream.value(const UserPresence(isOnline: false));
    }

    return _firestore
        .collection('profiles')
        .doc(cleanHandle)
        .snapshots()
        .map((doc) {
      if (!doc.exists) {
        return _memoryCache[cleanHandle] ??
            const UserPresence(isOnline: false);
      }
      final data = doc.data();
      final presence = UserPresence.fromMap(data);
      _memoryCache[cleanHandle] = presence;
      _saveCacheToStorage(cleanHandle, presence);
      return presence;
    });
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
