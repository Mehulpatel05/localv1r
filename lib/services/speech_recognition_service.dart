import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechRecognitionService {
  static final SpeechRecognitionService _instance = SpeechRecognitionService._internal();
  factory SpeechRecognitionService() => _instance;
  SpeechRecognitionService._internal();

  static SpeechRecognitionService get instance => _instance;

  final SpeechToText _speechToText = SpeechToText();
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get isListening => _speechToText.isListening;
  bool get isAvailable => _speechToText.isAvailable;

  Future<bool> checkPermission() async {
    return await Permission.microphone.isGranted;
  }

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> isPermissionPermanentlyDenied() async {
    return await Permission.microphone.isPermanentlyDenied;
  }

  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  Future<bool> initialize() async {
    if (_isInitialized && _speechToText.isAvailable) return true;
    try {
      final hasPerm = await requestPermission();
      if (!hasPerm) {
        return false;
      }

      bool success = await _speechToText.initialize(
        onError: (errorNotification) {
          debugPrint('Speech recognition error: ${errorNotification.errorMsg}');
        },
        onStatus: (status) {
          debugPrint('Speech recognition status: $status');
        },
        debugLogging: true,
        options: [
          SpeechToText.androidIntentLookup,
          SpeechToText.androidNoBluetooth,
          SpeechToText.androidAlwaysUseStop,
        ],
      );

      if (!success) {
        success = await _speechToText.initialize(
          debugLogging: true,
          options: [
            SpeechToText.androidNoBluetooth,
            SpeechToText.androidAlwaysUseStop,
          ],
        );
      }

      _isInitialized = success;
      return _isInitialized;
    } catch (e) {
      debugPrint('Speech initialization failed: $e');
      return false;
    }
  }

  Future<bool> startListening({
    required void Function(String recognizedWords, bool isFinal) onResult,
    void Function(double soundLevel)? onSoundLevelChange,
    void Function(String status)? onStatusChange,
    String? localeId,
  }) async {
    final available = await initialize();
    if (!available) return false;

    if (_speechToText.isListening) {
      await _speechToText.stop();
    }

    try {
      String? effectiveLocale = localeId;
      if (effectiveLocale == null) {
        try {
          final sysLocale = await _speechToText.systemLocale();
          effectiveLocale = sysLocale?.localeId;
        } catch (_) {}
      }

      await _speechToText.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        onSoundLevelChange: onSoundLevelChange,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 4),
          localeId: effectiveLocale,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Failed to start speech listening: $e');
      return false;
    }
  }

  Future<void> stopListening() async {
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
  }

  Future<void> cancelListening() async {
    if (_speechToText.isListening) {
      await _speechToText.cancel();
    }
  }
}
