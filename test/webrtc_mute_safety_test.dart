import 'package:flutter_test/flutter_test.dart';
import 'package:nearhood/services/webrtc_call_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebRtcCallService - Mute & Stream Safety Rules', () {
    final callService = WebRtcCallService.instance;

    test('Initial State: localStream is null, isCallActive is false, isMicMuted is false', () {
      expect(callService.localStream, isNull);
      expect(callService.remoteStream, isNull);
      expect(callService.isCallActive, isFalse);
      expect(callService.isMicMuted, isFalse);
      expect(callService.isCameraOff, isFalse);
    });

    test('Guard 1: toggleMicrophone returns false and no-ops when stream is null (calling/ringing state)', () {
      expect(callService.localStream, isNull);

      // Attempt to toggle mic before stream is initialized
      final result = callService.toggleMicrophone();

      // Must safely return false without throwing Exception('Can\'t be muted: The MediaStream is null')
      expect(result, isFalse);
      expect(callService.isMicMuted, isFalse);
    });

    test('Guard 2: toggleCamera returns false and no-ops when stream is null', () {
      expect(callService.localStream, isNull);

      // Attempt to toggle camera before stream is initialized
      final result = callService.toggleCamera();

      // Must safely return false without throwing
      expect(result, isFalse);
      expect(callService.isCameraOff, isFalse);
    });

    test('Guard 3: cleanup sets isCallActive = false FIRST and resets all streams and mute states', () async {
      await callService.cleanup();

      expect(callService.isCallActive, isFalse);
      expect(callService.localStream, isNull);
      expect(callService.remoteStream, isNull);
      expect(callService.isMicMuted, isFalse);
      expect(callService.isCameraOff, isFalse);
      expect(callService.currentCall, isNull);
    });
  });
}
