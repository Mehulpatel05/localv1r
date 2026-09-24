import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class VoiceNoteBubble extends StatefulWidget {
  final String audioUrl;
  final int durationSeconds;
  final List<double> waveformData;
  final bool isMe;
  final String timeStr;
  final bool isRead;
  final String status;

  /// Global coordinator ensuring only one voice note plays at any given time
  static final ValueNotifier<String?> activeAudioUrlNotifier = ValueNotifier<String?>(null);

  const VoiceNoteBubble({
    super.key,
    required this.audioUrl,
    required this.durationSeconds,
    required this.waveformData,
    required this.isMe,
    required this.timeStr,
    required this.isRead,
    required this.status,
  });

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  double _progress = 0.0; // 0.0 – 1.0
  int _remainingSeconds = 0;
  double _playbackSpeed = 1.0;
  bool _isSeeking = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _remainingSeconds = widget.durationSeconds;

    VoiceNoteBubble.activeAudioUrlNotifier.addListener(_onActiveAudioChanged);

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing &&
            state.processingState != ProcessingState.completed;
        if (state.processingState == ProcessingState.completed) {
          _progress = 0.0;
          _remainingSeconds = widget.durationSeconds;
        }
      });
    });

    _player.positionStream.listen((position) {
      if (!mounted || _isSeeking) return;
      final total =
          widget.durationSeconds > 0 ? widget.durationSeconds * 1000 : 1;
      final progressValue =
          (position.inMilliseconds / total).clamp(0.0, 1.0);
      final remaining =
          widget.durationSeconds - position.inSeconds;
      setState(() {
        _progress = progressValue;
        _remainingSeconds = remaining.clamp(0, widget.durationSeconds);
      });
    });
  }

  void _onActiveAudioChanged() {
    if (VoiceNoteBubble.activeAudioUrlNotifier.value != widget.audioUrl && _isPlaying) {
      _player.pause();
    }
  }

  @override
  void dispose() {
    VoiceNoteBubble.activeAudioUrlNotifier.removeListener(_onActiveAudioChanged);
    _player.dispose();
    super.dispose();
  }

  Future<void> _cyclePlaybackSpeed() async {
    HapticFeedback.selectionClick();
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
    });
    try {
      await _player.setSpeed(_playbackSpeed);
    } catch (e) {
      debugPrint('Error setting playback speed: $e');
    }
  }

  Future<void> _seekToFraction(double fraction) async {
    final totalMs = widget.durationSeconds > 0 ? widget.durationSeconds * 1000 : 1;
    final targetMs = (fraction.clamp(0.0, 1.0) * totalMs).round();

    setState(() {
      _progress = fraction.clamp(0.0, 1.0);
      _remainingSeconds = (widget.durationSeconds - (targetMs / 1000).round()).clamp(0, widget.durationSeconds);
    });

    try {
      if (_player.processingState == ProcessingState.idle ||
          _player.processingState == ProcessingState.completed) {
        await _player.setUrl(widget.audioUrl);
      }
      await _player.seek(Duration(milliseconds: targetMs));
    } catch (e) {
      debugPrint('Error seeking voice note: $e');
    }
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        VoiceNoteBubble.activeAudioUrlNotifier.value = widget.audioUrl;
        if (_player.processingState == ProcessingState.idle ||
            _player.processingState == ProcessingState.completed) {
          await _player.setUrl(widget.audioUrl);
          await _player.setSpeed(_playbackSpeed);
        }
        await _player.play();
      }
    } catch (e) {
      debugPrint('Error playing voice note: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to play audio'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatSeconds(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final iconColor = widget.isMe
        ? (isDark ? Colors.black : Colors.white)
        : (isDark ? Colors.white : const Color(0xFF0F172A));

    final mutedColor = widget.isMe
        ? (isDark ? Colors.black54 : Colors.white70)
        : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8));

    final activeBarColor = widget.isMe
        ? (isDark ? const Color(0xFF1D4ED8) : const Color(0xFF93C5FD))
        : const Color(0xFF2563EB);

    final inactiveBarColor = widget.isMe
        ? (isDark ? Colors.black38 : Colors.white38)
        : (isDark ? const Color(0xFF444444) : const Color(0xFFCBD5E1));

    // Normalize waveform — ensure 40 bars
    final rawWave = widget.waveformData;
    final List<double> wave = List.generate(
      40,
      (i) {
        if (rawWave.isEmpty) return 0.3;
        final idx = (i / 39 * (rawWave.length - 1)).round();
        return rawWave[idx.clamp(0, rawWave.length - 1)];
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: iconColor,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Waveform + time + speed control
          Flexible(
            child: Column(
              crossAxisAlignment: widget.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Interactive Waveform bars (Scrubbing / Seeking)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (details) {
                        _isSeeking = true;
                        final fraction = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                        _seekToFraction(fraction);
                      },
                      onHorizontalDragUpdate: (details) {
                        final fraction = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                        _seekToFraction(fraction);
                      },
                      onHorizontalDragEnd: (details) {
                        _isSeeking = false;
                      },
                      onTapDown: (details) {
                        final fraction = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                        _seekToFraction(fraction);
                      },
                      child: SizedBox(
                        height: 28,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(wave.length, (i) {
                            final isFilled = i / wave.length <= _progress;
                            final heightFactor = wave[i].clamp(0.15, 1.0);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1.2),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 60),
                                width: 2.5,
                                height: 28 * heightFactor,
                                decoration: BoxDecoration(
                                  color: isFilled ? activeBarColor : inactiveBarColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                // Time + speed pill + read receipt
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatSeconds(_remainingSeconds),
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Playback Speed Toggle Pill (1x, 1.5x, 2x)
                    GestureDetector(
                      onTap: _cyclePlaybackSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_playbackSpeed == 1.0 ? '1' : (_playbackSpeed == 1.5 ? '1.5' : '2')}x',
                          style: TextStyle(
                            color: iconColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (widget.timeStr.isNotEmpty) ...[
                      Text(
                        ' · ${widget.timeStr}',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (widget.isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        widget.isRead
                            ? Icons.done_all_rounded
                            : (widget.status == 'delivered'
                                ? Icons.done_all_rounded
                                : Icons.done_rounded),
                        size: 13,
                        color: widget.isRead
                            ? const Color(0xFF93C5FD)
                            : (isDark
                                ? Colors.black54
                                : Colors.white70),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
