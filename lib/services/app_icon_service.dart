import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/api_constants.dart';

class AppIconService {
  AppIconService._();
  static final AppIconService instance = AppIconService._();

  static const MethodChannel _channel = MethodChannel('com.social.nearhood/app_icon');
  static const String _prefKey = 'active_app_launcher_icon';

  Future<String> getCurrentAppIcon() async {
    if (kIsWeb || !Platform.isAndroid) {
      return 'default';
    }

    try {
      final icon = await _channel.invokeMethod<String>('getCurrentAppIcon');
      return icon ?? 'default';
    } catch (e) {
      debugPrint('[AppIconService] Failed to get current icon: $e');
      return 'default';
    }
  }

  Future<bool> setAppIcon(String icon) async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }

    final sanitized = icon.trim().toLowerCase();
    if (sanitized != 'default' && sanitized != 'dark' && sanitized != 'festive') {
      return false;
    }

    try {
      final success = await _channel.invokeMethod<bool>('setAppIcon', {'icon': sanitized});
      if (success == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKey, sanitized);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[AppIconService] Failed to set icon: $e');
      return false;
    }
  }

  Future<void> syncAppIcon() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/system/app-icon');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['activeIcon'] != null) {
          final serverIcon = (data['activeIcon'] as String).trim().toLowerCase();
          final prefs = await SharedPreferences.getInstance();
          final localIcon = prefs.getString(_prefKey) ?? 'default';

          if (serverIcon != localIcon) {
            await setAppIcon(serverIcon);
          } else {
            final nativeIcon = await getCurrentAppIcon();
            if (nativeIcon != serverIcon) {
              await setAppIcon(serverIcon);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AppIconService] Sync error: $e');
    }
  }
}
