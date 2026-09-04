import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceInfoService {
  static const _channel = MethodChannel('com.example.localv1/device_id');
  static const _storage = FlutterSecureStorage();

  /// Fetches a permanent, stable installation ID that survives Clear Data and App Uninstalls/Reinstalls.
  static Future<String> getInstallationId() async {
    // 1. Android: Query Native MethodChannel for stable deterministic UUID derived from SSAID
    if (Platform.isAndroid) {
      try {
        final String? nativeId = await _channel.invokeMethod<String>('getInstallationId');
        if (nativeId != null && nativeId.isNotEmpty) {
          return nativeId;
        }
      } catch (e) {
        debugPrint('Native device ID retrieval fallback: $e');
      }
    }

    // 2. iOS: identifierForVendor or Keychain
    if (Platform.isIOS) {
      try {
        final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        final iosInfo = await deviceInfo.iosInfo;
        if (iosInfo.identifierForVendor != null && iosInfo.identifierForVendor!.isNotEmpty) {
          return iosInfo.identifierForVendor!;
        }
      } catch (e) {
        debugPrint('iOS DeviceInfo error: $e');
      }
    }

    // 3. Fallback: Secure Storage (iOS Keychain / Local Keystore)
    try {
      String? installationId = await _storage.read(key: 'app_installation_uuid');
      if (installationId != null && installationId.isNotEmpty) {
        return installationId;
      }
    } catch (_) {}

    // 4. Generate fresh UUID and persist to storage
    final freshUuid = const Uuid().v4();
    try {
      await _storage.write(key: 'app_installation_uuid', value: freshUuid);
    } catch (_) {}
    return freshUuid;
  }

  /// Fetches a Play Integrity Standard Request Token binding the given requestHash.
  static Future<String?> getPlayIntegrityToken(String requestHash) async {
    if (Platform.isAndroid) {
      try {
        final String? token = await _channel.invokeMethod<String>('getPlayIntegrityToken', {'requestHash': requestHash});
        return token;
      } catch (e) {
        debugPrint('Play Integrity Token error: $e');
        throw Exception("Play Integrity attestation failed.");
      }
    }
    // For non-Android platforms, we cannot provide Play Integrity
    throw Exception("Play Integrity attestation is only supported on Android.");
  }
}
