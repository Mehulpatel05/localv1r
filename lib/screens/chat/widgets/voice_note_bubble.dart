import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../../../theme/app_colors.dart';

class VoiceNoteBubble extends StatefulWidget {
  final String audioUrl;
  final int durationSeconds;
  final List<double> waveformData;
  final bool isMe;
  final String timeStr;
  final bool isRead;
  final String status;

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

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> with TickerProviderStateMixin {
  late final AudioPlayer _player;
  late final AnimationController _playPauseController;
  late final AnimationController _waveAnimController;
  bool _isPlaying = false;
  double _progress = 0.0;
  int _remainingSeconds = 0;
  double _playbackSpeed = 1.0;
  bool _isSeeking = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _remainingSeconds = widget.durationSeconds;
    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _waveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    VoiceNoteBubble.activeAudioUrlNotifier.addListener(_onActiveAudioChanged);

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing && state.processingState != ProcessingState.completed;
      if (playing) {
        _playPauseController.forward();
        _waveAnimController.repeat(reverse: true);
      } else {
        _playPauseController.reverse();
        _waveAnimController.stop();
        _waveAnimController.reset();
      }
      setState(() {
        _isPlaying = playing;
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
    _playPauseController.dispose();
    _waveAnimController.dispose();
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
        await _setupAudioSource(widget.audioUrl);
      }
      await _player.seek(Duration(milliseconds: targetMs));
    } catch (e) {
      debugPrint('Error seeking voice note: $e');
    }
  }

  Future<void> _setupAudioSource(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) return;
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      await _player.setUrl(clean);
    } else if (File(clean).existsSync()) {
      await _player.setFilePath(clean);
    } else {
      await _player.setUrl(clean);
    }
  }

  Future<void> _togglePlay() async {
    final url = widget.audioUrl.trim();
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio file is unavailable'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        VoiceNoteBubble.activeAudioUrlNotifier.value = url;
        if (_player.processingState == ProcessingState.idle) {
          await _setupAudioSource(url);
          await _player.setSpeed(_playbackSpeed);
        } else if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
      }
    } catch (e) {
      debugPrint('Error playing voice note: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to play audio'),
            duration: Duration(milliseconds: 1505),
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
    final iconColor = widget.isMe ? Colors.white : AppColors.textPrimary;
    final mutedColor = widget.isMe ? Colors.white70 : AppColors.textMuted;
    final activeBarColor = widget.isMe ? Colors.white : AppColors.primary;
    final inactiveBarColor = widget.isMe ? Colors.white38 : AppColors.divider;

    final rawWave = widget.waveformData;
    final List<double> wave = List.generate(
      40,
      (i) {
        if (rawWave.isEmpty) return 0.3;
        final idx = (i / 39 * (rawWave.length - 1)).round();
        return rawWave[idx.clamp(0, rawWave.length - 1)];
      },
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _togglePlay,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isMe
                        ? Colors.white.withValues(alpha: 0.2)
                        : AppColors.chipBg,
                  ),
                  child: Center(
                    child: AnimatedIcon(
                      icon: AnimatedIcons.play_pause,
                      progress: _playPauseController,
                      color: iconColor,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              Expanded(
                child: GestureDetector(
                  onHorizontalDragStart: (details) => _isSeeking = true,
                  onHorizontalDragUpdate: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box != null) {
                      final local = details.localPosition.dx;
                      final frac = (local / box.size.width).clamp(0.0, 1.0);
                      _seekToFraction(frac);
                    }
                  },
                  onHorizontalDragEnd: (details) => _isSeeking = false,
                  onTapUp: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box != null) {
                      final local = details.localPosition.dx;
                      final frac = (local / box.size.width).clamp(0.0, 1.0);
                      _seekToFraction(frac);
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    height: 30,
                    child: AnimatedBuilder(
                      animation: _waveAnimController,
                      builder: (context, _) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(wave.length, (i) {
                            final barProgress = i / wave.length;
                            final isPlayed = barProgress <= _progress;
                            final baseHeight = (wave[i] * 22).clamp(4.0, 26.0);
                            final animatedOffset = _isPlaying
                                ? math.sin((_waveAnimController.value * 2 * math.pi) + (i * 0.45)) * 4.0
                                : 0.0;
                            final height = (baseHeight + animatedOffset).clamp(4.0, 28.0);

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 80),
                              width: 2.2,
                              height: height,
                              decoration: BoxDecoration(
                                color: isPlayed ? activeBarColor : inactiveBarColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              GestureDetector(
                onTap: _cyclePlaybackSpeed,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.isMe
                        ? Colors.white.withValues(alpha: 0.2)
                        : AppColors.chipBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_playbackSpeed.toStringAsFixed(_playbackSpeed == 1.0 ? 0 : 1)}x',
                    style: TextStyle(
                      color: iconColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 3),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isPlaying
                    ? _formatSeconds(_remainingSeconds)
                    : _formatSeconds(widget.durationSeconds),
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.timeStr,
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
                          ? (widget.isMe ? Colors.white : AppColors.primary)
                          : mutedColor,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
