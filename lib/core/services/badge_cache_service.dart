import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BadgeCacheService extends ChangeNotifier {
  static final BadgeCacheService _instance = BadgeCacheService._internal();
  factory BadgeCacheService() => _instance;
  static BadgeCacheService get instance => _instance;

  BadgeCacheService._internal() {
    _initFromDisk();
  }

  static const String _kBadgeCacheKey = 'disk_badge_cache_map_v1';

  final Map<String, Map<String, dynamic>> _cache = {};
  Timer? _diskSaveDebounce;

  Future<void> _initFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kBadgeCacheKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        decoded.forEach((key, val) {
          if (val is Map<String, dynamic>) {
            _cache[key] = val;
          } else if (val is Map) {
            _cache[key] = Map<String, dynamic>.from(val);
          }
        });
        notifyListeners();
      }
    } catch (e) {
      debugPrint('BadgeCacheService init error: $e');
    }
  }

  void _scheduleSaveToDisk() {
    _diskSaveDebounce?.cancel();
    _diskSaveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kBadgeCacheKey, jsonEncode(_cache));
      } catch (e) {
        debugPrint('BadgeCacheService save error: $e');
      }
    });
  }

  String _cleanKey(String handle) {
    return handle.replaceAll('@', '').trim().toLowerCase();
  }

  bool isUserVerified(String handle, {bool fallback = false}) {
    final clean = _cleanKey(handle);
    if (clean.isEmpty) return fallback;
    final data = _cache[clean];
    if (data != null && data['isVerified'] != null) {
      return data['isVerified'] == true;
    }
    return fallback;
  }

  bool isVerified(String handle, {bool fallback = false}) =>
      isUserVerified(handle, fallback: fallback);

  String? getUserBadge(String handle, {String? fallback}) {
    final clean = _cleanKey(handle);
    if (clean.isEmpty) return fallback;
    final data = _cache[clean];
    if (data != null && data['badge'] != null && data['badge'].toString().trim().isNotEmpty) {
      if (data['isVerified'] == false && data['badge'].toString().toUpperCase().contains('FOUNDING')) {
        return fallback;
      }
      return data['badge'].toString().trim();
    }
    return fallback;
  }

  String? getBadge(String handle, {String? fallback}) =>
      getUserBadge(handle, fallback: fallback);

  void removeBadge(String handle) {
    final clean = _cleanKey(handle);
    if (clean.isEmpty) return;
    final existing = _cache[clean];
    if (existing != null) {
      existing.remove('badge');
      existing.remove('founderSeq');
      existing['isVerified'] = false;
      _cache[clean] = existing;
      _scheduleSaveToDisk();
      notifyListeners();
    }
  }

  void setBadge(String handle, {bool? isVerified, String? badgeText, int? founderSeq}) {
    final clean = _cleanKey(handle);
    if (clean.isEmpty) return;

    final existing = _cache[clean] ?? <String, dynamic>{};
    bool changed = false;

    if (isVerified != null && existing['isVerified'] != isVerified) {
      existing['isVerified'] = isVerified;
      changed = true;
    }

    if (badgeText != null && badgeText.trim().isNotEmpty) {
      if (existing['badge'] != badgeText) {
        existing['badge'] = badgeText;
        changed = true;
      }
    } else if (isVerified == false && existing['badge'] != null) {
      existing.remove('badge');
      existing.remove('founderSeq');
      changed = true;
    }

    if (founderSeq != null) {
      if (existing['founderSeq'] != founderSeq) {
        existing['founderSeq'] = founderSeq;
        changed = true;
      }
    } else if (isVerified == false && existing['founderSeq'] != null) {
      existing.remove('founderSeq');
      changed = true;
    }

    if (changed) {
      _cache[clean] = existing;
      _scheduleSaveToDisk();
      notifyListeners();
    }
  }

  void primeCache(Map<String, Map<String, dynamic>> entries) {
    bool hasChanged = false;
    entries.forEach((handle, data) {
      final clean = _cleanKey(handle);
      if (clean.isNotEmpty) {
        _cache[clean] = data;
        hasChanged = true;
      }
    });
    if (hasChanged) {
      _scheduleSaveToDisk();
      notifyListeners();
    }
  }

  void clear() {
    _cache.clear();
    _scheduleSaveToDisk();
    notifyListeners();
  }
}
