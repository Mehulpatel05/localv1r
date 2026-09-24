import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AvatarCacheService extends ChangeNotifier {
  static final AvatarCacheService _instance = AvatarCacheService._internal();
  factory AvatarCacheService() => _instance;
  static AvatarCacheService get instance => _instance;

  AvatarCacheService._internal();

  static const String baseUrl = 'https://localv1r.onrender.com/api/v1';

  final Map<String, String?> _cache = {};
  final Set<String> _inFlightFetches = {};

  /// Retrieves cached avatar URL synchronously if present, else null
  String? getCachedUrl(String handle) {
    final clean = handle.replaceAll('@', '').trim().toLowerCase();
    return _cache[clean];
  }

  /// Sets or updates the cached avatar URL for a handle and notifies listeners
  void setCachedUrl(String handle, String? photoUrl) {
    final clean = handle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return;
    final val = (photoUrl != null && photoUrl.trim().isNotEmpty) ? photoUrl.trim() : null;
    if (_cache[clean] != val) {
      _cache[clean] = val;
      notifyListeners();
    }
  }

  /// Bulk prime cache
  void primeCache(Map<String, String?> entries) {
    bool hasChanged = false;
    entries.forEach((handle, url) {
      final clean = handle.replaceAll('@', '').trim().toLowerCase();
      if (clean.isNotEmpty) {
        final val = (url != null && url.trim().isNotEmpty) ? url.trim() : null;
        if (_cache[clean] != val) {
          _cache[clean] = val;
          hasChanged = true;
        }
      }
    });
    if (hasChanged) {
      notifyListeners();
    }
  }

  /// Fetches avatar URL from Backend D1 `profiles/{handle}` if not already cached
  Future<String?> fetchAvatarUrl(String handle) async {
    final clean = handle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return null;

    if (_cache.containsKey(clean)) {
      return _cache[clean];
    }

    if (_inFlightFetches.contains(clean)) {
      // Wait briefly for in-flight request
      int wait = 0;
      while (_inFlightFetches.contains(clean) && wait < 10) {
        await Future.delayed(const Duration(milliseconds: 100));
        wait++;
      }
      return _cache[clean];
    }

    _inFlightFetches.add(clean);

    try {
      final uri = Uri.parse('$baseUrl/auth/profile/${Uri.encodeComponent(clean)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final user = data['user'] as Map<String, dynamic>?;
        final photoUrl = (user?['avatarUrl'] as String?)?.trim();
        _cache[clean] = (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null;
      } else {
        _cache[clean] = null;
      }
    } catch (e) {
      debugPrint('[AvatarCacheService] Error fetching avatar for @$clean: $e');
      return null;
    } finally {
      _inFlightFetches.remove(clean);
      notifyListeners();
    }

    return _cache[clean];
  }

  /// Saves current user's photoUrl into SharedPreferences cache for instant cold starts
  Future<void> saveMyPhotoUrlLocally(String photoUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_photo_url', photoUrl);
    } catch (_) {}
  }

  /// Loads current user's locally cached photoUrl
  Future<String?> getMyPhotoUrlLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_photo_url');
    } catch (_) {
      return null;
    }
  }
}
