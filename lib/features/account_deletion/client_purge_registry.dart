import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/auth_service.dart';
import '../../services/bazar_repository.dart';
import '../../services/webrtc_call_service.dart';
import '../../services/call_audio_tone_service.dart';

class ClientPurgeRegistry {
  static final ClientPurgeRegistry instance = ClientPurgeRegistry._internal();
  ClientPurgeRegistry._internal();

  Future<void> purgeAllClientState() async {
    try {
      await WebRtcCallService.instance.cleanup();
    } catch (_) {}

    try {
      await CallAudioToneService.instance.stop();
    } catch (_) {}

    try {
      BazarRepository.instance.clearCache();
    } catch (_) {}

    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final entities = tempDir.listSync();
        for (final entity in entities) {
          try {
            if (entity is File) {
              entity.deleteSync();
            } else if (entity is Directory) {
              entity.deleteSync(recursive: true);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    await AuthService.instance.signOut();
  }
}
