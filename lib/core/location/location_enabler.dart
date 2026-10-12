import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Rapido / Uber style native Google Play Services Location Enabler.
///
/// Prompts the system-level Google Location Accuracy dialog directly inside
/// the app ("To continue, your device will need to use Location Accuracy")
/// with [No, thanks] and [Turn on] buttons, without kicking the user into
/// Android phone settings.
class LocationEnabler {
  static const MethodChannel _channel =
      MethodChannel('com.social.nearhood/location_settings');

  /// Prompts user to turn on GPS / Location Accuracy via Google Play Services.
  /// Returns `true` if user tapped [Turn on] (or GPS is already ON).
  /// Returns `false` if user tapped [No, thanks] or dismissed the dialog.
  static Future<bool> requestEnableLocation() async {
    // If already enabled, return true immediately
    try {
      final isAlreadyEnabled = await Geolocator.isLocationServiceEnabled();
      if (isAlreadyEnabled) return true;
    } catch (_) {}

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final bool? turnedOn =
            await _channel.invokeMethod<bool>('promptEnableLocation');
        if (turnedOn == true) {
          // Double verify with geolocator that GPS state is active
          return await Geolocator.isLocationServiceEnabled();
        }
        return false;
      } on PlatformException catch (e) {
        debugPrint('[LocationEnabler] PlatformException: ${e.message}');
      } catch (e) {
        debugPrint('[LocationEnabler] Error invoking native prompt: $e');
      }
    }

    // Fallback for non-Android platforms
    return await Geolocator.openLocationSettings();
  }
}
