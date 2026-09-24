import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:just_audio/just_audio.dart';

/// Manages call audio states:
/// - Incoming Call: System incoming ringtone + vibration on Receiver device
/// - Outgoing Call: Synthesized telecom ringback tone ("tring... tring...") on Caller device
/// - Busy / Declined: Rapid busy signal tone
class CallAudioToneService {
  static final CallAudioToneService instance = CallAudioToneService._internal();
  factory CallAudioToneService() => instance;
  CallAudioToneService._internal();

  AudioPlayer? _player;
  bool _isPlayingOutgoing = false;

  /// 1. Play Incoming Ringtone on Receiver device (Loud ringtone + vibration)
  Future<void> playIncomingRingtone() async {
    await stop();
    try {
      HapticFeedback.vibrate();
      FlutterRingtonePlayer().playRingtone(
        looping: true,
        volume: 1.0,
        asAlarm: false,
      );
    } catch (e) {
      debugPrint('Error playing incoming ringtone: $e');
    }
  }

  /// 2. Play Outgoing Ringback Tone on Caller device ("tring... tring...")
  Future<void> playOutgoingRingbackTone() async {
    if (_isPlayingOutgoing) return;
    await stop();
    _isPlayingOutgoing = true;

    try {
      _player = AudioPlayer();
      final wavBytes = _generateRingbackWav();
      final uri = Uri.dataFromBytes(wavBytes, mimeType: 'audio/wav');
      await _player!.setAudioSource(AudioSource.uri(uri));
      await _player!.setLoopMode(LoopMode.one);
      await _player!.setVolume(0.55);
      await _player!.play();
    } catch (e) {
      debugPrint('Error playing outgoing ringback tone: $e');
      // Fallback: subtle system notification chime
      try {
        FlutterRingtonePlayer().playNotification();
      } catch (_) {}
    }
  }

  /// 3. Play Busy / Declined Tone (3 short beeps)
  Future<void> playBusyTone() async {
    await stop();
    try {
      _player = AudioPlayer();
      final wavBytes = _generateBusyWav();
      final uri = Uri.dataFromBytes(wavBytes, mimeType: 'audio/wav');
      await _player!.setAudioSource(AudioSource.uri(uri));
      await _player!.setLoopMode(LoopMode.off);
      await _player!.setVolume(0.6);
      await _player!.play();
    } catch (e) {
      debugPrint('Error playing busy tone: $e');
    }
  }

  /// 4. Stop all audio playback immediately
  Future<void> stop() async {
    _isPlayingOutgoing = false;
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
    try {
      if (_player != null) {
        await _player!.stop();
        await _player!.dispose();
        _player = null;
      }
    } catch (e) {
      debugPrint('Error stopping CallAudioToneService: $e');
      _player = null;
    }
  }

  /// Generates a standard VoIP Ringback Tone (440Hz + 480Hz dual frequency)
  /// Pattern: 1.6 seconds ON tone + 3.4 seconds OFF silence (5.0 seconds cycle)
  Uint8List _generateRingbackWav() {
    const int sampleRate = 8000;
    const int totalSamples = 40000; // 8000 * 5.0s
    const int toneSamples = 12800;  // 8000 * 1.6s

    final ByteData byteData = ByteData(44 + (totalSamples * 2));

    // RIFF Header
    _writeWavHeader(byteData, totalSamples * 2, sampleRate);

    // Audio Data Samples
    int offset = 44;
    for (int i = 0; i < totalSamples; i++) {
      if (i < toneSamples) {
        final double t = i / sampleRate;
        // Dual-tone frequencies: 440Hz and 480Hz with smooth envelope
        final double s1 = math.sin(2 * math.pi * 440 * t);
        final double s2 = math.sin(2 * math.pi * 480 * t);

        // Attack and decay envelope to prevent click artifacts
        double env = 1.0;
        if (i < 200) {
          env = i / 200.0;
        } else if (i > toneSamples - 200) {
          env = (toneSamples - i) / 200.0;
        }

        final double mixed = ((s1 + s2) * 0.5) * env * 0.35;
        final int sampleValue = (mixed * 32767).clamp(-32768, 32767).toInt();
        byteData.setInt16(offset, sampleValue, Endian.little);
      } else {
        byteData.setInt16(offset, 0, Endian.little);
      }
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }

  /// Generates a Busy Tone (480Hz + 620Hz, 3 fast bursts of 0.4s ON / 0.4s OFF)
  Uint8List _generateBusyWav() {
    const int sampleRate = 8000;
    const int totalSamples = 19200; // 8000 * 2.4s
    const int burstSamples = 3200;  // 8000 * 0.4s

    final ByteData byteData = ByteData(44 + (totalSamples * 2));
    _writeWavHeader(byteData, totalSamples * 2, sampleRate);

    int offset = 44;
    for (int i = 0; i < totalSamples; i++) {
      final int cycleIndex = i % (burstSamples * 2);
      if (cycleIndex < burstSamples) {
        final double t = i / sampleRate;
        final double s1 = math.sin(2 * math.pi * 480 * t);
        final double s2 = math.sin(2 * math.pi * 620 * t);
        final double mixed = ((s1 + s2) * 0.5) * 0.4;
        final int sampleValue = (mixed * 32767).clamp(-32768, 32767).toInt();
        byteData.setInt16(offset, sampleValue, Endian.little);
      } else {
        byteData.setInt16(offset, 0, Endian.little);
      }
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }

  void _writeWavHeader(ByteData byteData, int dataSize, int sampleRate) {
    // "RIFF"
    byteData.setUint8(0, 0x52);
    byteData.setUint8(1, 0x49);
    byteData.setUint8(2, 0x46);
    byteData.setUint8(3, 0x46);
    byteData.setUint32(4, 36 + dataSize, Endian.little);

    // "WAVE"
    byteData.setUint8(8, 0x57);
    byteData.setUint8(9, 0x41);
    byteData.setUint8(10, 0x56);
    byteData.setUint8(11, 0x45);

    // "fmt "
    byteData.setUint8(12, 0x66);
    byteData.setUint8(13, 0x6D);
    byteData.setUint8(14, 0x74);
    byteData.setUint8(15, 0x20);
    byteData.setUint32(16, 16, Endian.little); // PCM SubChunk1Size
    byteData.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    byteData.setUint16(22, 1, Endian.little);  // NumChannels (1 = Mono)
    byteData.setUint32(24, sampleRate, Endian.little); // SampleRate
    byteData.setUint32(28, sampleRate * 2, Endian.little); // ByteRate (sampleRate * channels * bytesPerSample)
    byteData.setUint16(32, 2, Endian.little);  // BlockAlign (channels * bytesPerSample)
    byteData.setUint16(34, 16, Endian.little); // BitsPerSample (16-bit)

    // "data"
    byteData.setUint8(36, 0x64);
    byteData.setUint8(37, 0x61);
    byteData.setUint8(38, 0x74);
    byteData.setUint8(39, 0x61);
    byteData.setUint32(40, dataSize, Endian.little);
  }
}
