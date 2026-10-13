import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../models/user_profile.dart';

class NameCacheService extends ChangeNotifier {
  static final NameCacheService _instance = NameCacheService._internal();
  factory NameCacheService() => _instance;
  static NameCacheService get instance => _instance;

  NameCacheService._internal() {
    _initFromDisk();
  }

  static const String baseUrl = ApiConstants.baseUrl;
  static const String _kNameCacheKey = 'disk_name_cache_map';
  static const String _kMyNameKey = 'disk_my_display_name';

  final Map<String, String?> _cache = {};
  final Map<String, Completer<String?>> _inFlightCompleters = {};
  String? _myName;
  Timer? _diskSaveDebounce;

  static bool isPlaceholderName(String? value) {
    if (value == null) return true;
    final clean = value.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty || clean == 'guest' || clean == 'anon') return true;
    if (clean.startsWith('user_') || clean.startsWith('anon#')) return true;
    if (RegExp(r'^user\s*\d+').hasMatch(clean)) return true;
    return false;
  }

  Future<void> _initFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMyName = prefs.getString(_kMyNameKey);
      _myName = isPlaceholderName(savedMyName) ? null : savedMyName?.trim();
      final jsonStr = prefs.getString(_kNameCacheKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        decoded.forEach((key, val) {
          if (val is String && val.trim().isNotEmpty && !isPlaceholderName(val)) {
            _cache[key] = val.trim();
          }
        });
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[NameCacheService] Error initializing name disk cache: $e');
    }
  }

  void _scheduleSaveToDisk() {
    _diskSaveDebounce?.cancel();
    _diskSaveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final mapToSave = <String, String>{};
        _cache.forEach((k, v) {
          if (v != null && v.trim().isNotEmpty && !isPlaceholderName(v)) {
            mapToSave[k] = v.trim();
          }
        });
        await prefs.setString(_kNameCacheKey, jsonEncode(mapToSave));
      } catch (e) {
        debugPrint('[NameCacheService] Error saving names to disk: $e');
      }
    });
  }

  Future<void> ensureInitialized() async {
    await _initFromDisk();
  }

  String? getCachedName(String handle) {
    final clean = handle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return null;
    final val = _cache[clean];
    if (isPlaceholderName(val)) return null;
    return val;
  }

  String getDisplayName(String handle, {String? fallback}) {
    final clean = handle.replaceAll('@', '').trim();
    final lower = clean.toLowerCase();
    if (clean.isEmpty) {
      if (fallback != null && fallback.trim().isNotEmpty && !isPlaceholderName(fallback)) {
        final cleanFb = fallback.replaceAll('@', '').trim();
        return cleanFb.isNotEmpty ? cleanFb : '';
      }
      return '';
    }
    final cached = _cache[lower];
    if (cached != null && cached.trim().isNotEmpty && !isPlaceholderName(cached)) {
      return cached.trim();
    }
    if (fallback != null && fallback.trim().isNotEmpty) {
      final cleanFallback = fallback.replaceAll('@', '').trim();
      if (cleanFallback.isNotEmpty && !isPlaceholderName(cleanFallback)) {
        return cleanFallback;
      }
    }
    if (!isPlaceholderName(clean)) {
      return clean[0].toUpperCase() + clean.substring(1);
    }
    if (_myName != null && _myName!.trim().isNotEmpty && !isPlaceholderName(_myName)) {
      return _myName!.trim();
    }
    if (fallback != null && fallback.trim().isNotEmpty) {
      final cleanFb = fallback.replaceAll('@', '').trim();
      if (!isPlaceholderName(cleanFb)) return cleanFb;
    }
    return 'Neighbor';
  }

  void setCachedName(String handle, String? name, {bool persist = true}) {
    final clean = handle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return;
    final val = (name != null && name.trim().isNotEmpty && !isPlaceholderName(name))
        ? name.trim()
        : null;
    if (val == null) return;

    if (_cache[clean] != val) {
      _cache[clean] = val;
      if (persist) _scheduleSaveToDisk();
      notifyListeners();
    }
  }

  void primeCache(Map<String, String?> entries) {
    bool hasChanged = false;
    entries.forEach((handle, name) {
      final clean = handle.replaceAll('@', '').trim().toLowerCase();
      if (clean.isNotEmpty) {
        final val = (name != null && name.trim().isNotEmpty && !isPlaceholderName(name))
            ? name.trim()
            : null;
        if (val != null && _cache[clean] != val) {
          _cache[clean] = val;
          hasChanged = true;
        }
      }
    });
    if (hasChanged) {
      _scheduleSaveToDisk();
      notifyListeners();
    }
  }

  Future<String?> fetchName(String handle, {bool forceRefresh = false}) async {
    final clean = handle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return null;

    if (!forceRefresh && _cache.containsKey(clean) && _cache[clean] != null && !isPlaceholderName(_cache[clean])) {
      return _cache[clean];
    }

    if (_inFlightCompleters.containsKey(clean)) {
      return _inFlightCompleters[clean]!.future;
    }

    final completer = Completer<String?>();
    _inFlightCompleters[clean] = completer;

    try {
      final uri = Uri.parse('$baseUrl/profile/${Uri.encodeComponent(clean)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final profile = data['profile'] as Map<String, dynamic>?;
        final user = data['user'] as Map<String, dynamic>?;
        final rawName = (profile?['displayName'] ??
                profile?['display_name'] ??
                profile?['name'] ??
                profile?['fullName'] ??
                user?['name'] ??
                user?['displayName']) as String?;
        final validName = (rawName != null && rawName.trim().isNotEmpty && !isPlaceholderName(rawName))
            ? rawName.trim()
            : null;
        if (validName != null) {
          _cache[clean] = validName;
          _scheduleSaveToDisk();
        }
        completer.complete(validName);
      } else if (res.statusCode == 404) {
        _cache[clean] = null;
        completer.complete(null);
      } else {
        completer.complete(_cache[clean]);
      }
    } catch (e) {
      debugPrint('[NameCacheService] Error fetching name for @$clean: $e');
      if (!completer.isCompleted) {
        completer.complete(_cache[clean]);
      }
    } finally {
      _inFlightCompleters.remove(clean);
      notifyListeners();
    }

    return _cache[clean];
  }

  Future<void> saveMyNameLocally(String name) async {
    if (isPlaceholderName(name)) return;
    _myName = name.trim();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMyNameKey, name.trim());
    } catch (_) {}
  }

  Future<String?> getMyNameLocally() async {
    if (_myName != null && _myName!.trim().isNotEmpty && !isPlaceholderName(_myName)) {
      return _myName;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kMyNameKey);
      _myName = isPlaceholderName(saved) ? null : saved?.trim();
      return _myName;
    } catch (_) {
      return null;
    }
  }

  void clearAll() {
    _cache.clear();
    _inFlightCompleters.clear();
    _myName = null;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_kNameCacheKey);
      prefs.remove(_kMyNameKey);
    }).catchError((_) {});
  }
}

String getDisplayName(dynamic userOrHandle, {String? fallback}) {
  if (userOrHandle == null) return fallback?.replaceAll('@', '').trim() ?? '';
  if (userOrHandle is UserProfile) {
    if (userOrHandle.displayName != null &&
        userOrHandle.displayName!.trim().isNotEmpty &&
        !NameCacheService.isPlaceholderName(userOrHandle.displayName)) {
      return userOrHandle.displayName!.trim();
    }
    return NameCacheService.instance.getDisplayName(userOrHandle.handle, fallback: fallback);
  }
  final str = userOrHandle.toString();
  return NameCacheService.instance.getDisplayName(str, fallback: fallback);
}
