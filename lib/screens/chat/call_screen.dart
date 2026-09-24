import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_service.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/call_model.dart';
import '../../services/webrtc_call_service.dart';
import '../../services/call_audio_tone_service.dart';

class CallScreen extends StatefulWidget {
  final CallModel call;
  final String currentUserHandle;
  final bool isCaller;

  const CallScreen({
    super.key,
    required this.call,
    required this.currentUserHandle,
    required this.isCaller,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  final WebRtcCallService _callService = WebRtcCallService.instance;

  CallStatus _status = CallStatus.calling;
  final ValueNotifier<int> _durationNotifier = ValueNotifier<int>(0);
  Timer? _callTimer;
  Timer? _ringTimeoutTimer;
  Timer? _statusPollingTimer;
  StreamSubscription<dynamic>? _proximitySubscription;

  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = false;
  bool _isEnding = false;
  bool _isDismissed = false;
  bool _isLocalFullScreen = false; // Video PiP swap state
  bool _isNear = false; // Proximity sensor (phone at ear) state

  void _safeDismiss() {
    if (_isDismissed) return;
    _isDismissed = true;
    _ringTimeoutTimer?.cancel();
    _callTimer?.cancel();
    _statusPollingTimer?.cancel();
    _statusPollingTimer = null;
    _proximitySubscription?.cancel();
    _proximitySubscription = null;
    CallAudioToneService.instance.stop();

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // PIP offset
  Offset _pipOffset = const Offset(20, 70);

  @override
  void initState() {
    super.initState();
    _status = widget.call.status;
    _isSpeakerOn = widget.call.callType == CallType.video;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (_status != CallStatus.connected) {
      _pulseController.repeat(reverse: true);
    }

    // Play subtle outgoing ringback tone ("tring... tring...") on caller device
    if (widget.isCaller && _status != CallStatus.connected) {
      CallAudioToneService.instance.playOutgoingRingbackTone();

      // 45s Auto-timeout if call is not answered by receiver
      _ringTimeoutTimer = Timer(const Duration(seconds: 45), () {
        if (mounted && _status != CallStatus.connected && !_isEnding) {
          _handleAutoMissedTimeout();
        }
      });
    }

    if (widget.isCaller) {
      _callService.listenForAnswerAndCandidates(widget.call.callId);
    }

    _listenToCallDoc();

    if (_status == CallStatus.connected) {
      _startTimer();
    }

    // Initialize Proximity Sensor for audio calls (ear touch blanking)
    if (widget.call.callType == CallType.audio) {
      try {
        _proximitySubscription = ProximitySensor.events.listen((int event) {
          if (!mounted) return;
          setState(() {
            _isNear = event > 0;
          });
        });
      } catch (e) {
        debugPrint('Proximity sensor not available: $e');
      }
    }
  }

  void _listenToCallDoc() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/calls/${widget.call.callId}'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 2));

        if (res.statusCode != 200) {
          if (res.statusCode == 404) {
            _ringTimeoutTimer?.cancel();
            CallAudioToneService.instance.stop();
            _handleCallTerminated(CallStatus.ended);
          }
          return;
        }

        final body = jsonDecode(res.body);
        final data = body['call'] as Map<String, dynamic>? ?? {};
        final statusStr = (data['status'] ?? '').toString().toLowerCase();

        if (!mounted) return;

        if (statusStr == 'ringing' && _status != CallStatus.ringing && _status != CallStatus.connected) {
          setState(() {
            _status = CallStatus.ringing;
          });
        } else if ((statusStr == 'connected' || statusStr == 'accepted') && _status != CallStatus.connected) {
          _ringTimeoutTimer?.cancel();
          CallAudioToneService.instance.stop();
          if (_pulseController.isAnimating) {
            _pulseController.stop();
          }
          setState(() {
            _status = CallStatus.connected;
          });
          HapticFeedback.mediumImpact();
          _startTimer();
        } else if (statusStr == 'rejected') {
          _ringTimeoutTimer?.cancel();
          CallAudioToneService.instance.stop();
          _handleCallTerminated(CallStatus.rejected);
        } else if (statusStr == 'ended') {
          _ringTimeoutTimer?.cancel();
          CallAudioToneService.instance.stop();
          _handleCallTerminated(CallStatus.ended);
        } else if (statusStr == 'missed') {
          _ringTimeoutTimer?.cancel();
          CallAudioToneService.instance.stop();
          _handleCallTerminated(CallStatus.missed);
        } else if (statusStr == 'busy') {
          _ringTimeoutTimer?.cancel();
          CallAudioToneService.instance.playBusyTone();
          _handleCallTerminated(CallStatus.busy);
        }
      } catch (_) {}
    });
  }

  void _startTimer() {
    _callTimer?.cancel();
    if (_pulseController.isAnimating) {
      _pulseController.stop();
    }
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _durationNotifier.value++;
    });
  }

  void _handleAutoMissedTimeout() {
    if (_isEnding || _isDismissed) return;
    _isEnding = true;
    _ringTimeoutTimer?.cancel();
    _callTimer?.cancel();
    _statusPollingTimer?.cancel();
    _proximitySubscription?.cancel();
    _proximitySubscription = null;
    CallAudioToneService.instance.stop();

    if (mounted) {
      setState(() {
        _status = CallStatus.missed;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No answer · Call timed out'),
          duration: Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Future.delayed(const Duration(milliseconds: 400), () {
        _safeDismiss();
      });
    } else {
      _safeDismiss();
    }

    _callService.endCall(
      call: widget.call,
      endStatus: CallStatus.missed,
      durationSeconds: 0,
    );
  }

  void _handleCallTerminated(CallStatus terminalStatus) {
    if (_isEnding || _isDismissed) return;
    _isEnding = true;
    _ringTimeoutTimer?.cancel();
    _callTimer?.cancel();
    _statusPollingTimer?.cancel();
    _proximitySubscription?.cancel();
    _proximitySubscription = null;
    CallAudioToneService.instance.stop();

    if (mounted) {
      setState(() {
        _status = terminalStatus;
      });
      String msg = 'Call ended';
      if (terminalStatus == CallStatus.rejected) msg = 'Call declined';
      if (terminalStatus == CallStatus.missed) msg = 'Call missed';
      if (terminalStatus == CallStatus.busy) msg = 'User is busy on another call';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Future.delayed(const Duration(milliseconds: 400), () {
        _safeDismiss();
      });
    } else {
      _safeDismiss();
    }
  }

  Future<void> _endCall() async {
    if (_isEnding || _isDismissed) return;
    _isEnding = true;
    _ringTimeoutTimer?.cancel();
    _callTimer?.cancel();
    _statusPollingTimer?.cancel();
    _proximitySubscription?.cancel();
    _proximitySubscription = null;
    CallAudioToneService.instance.stop();
    HapticFeedback.mediumImpact();

    final endStatus = _status == CallStatus.connected
        ? CallStatus.ended
        : (widget.isCaller ? CallStatus.missed : CallStatus.rejected);

    final duration = _durationNotifier.value;

    _safeDismiss();

    // Process network endCall & WebRTC cleanup in background
    _callService.endCall(
      call: widget.call,
      endStatus: endStatus,
      durationSeconds: duration,
    );
  }

  void _toggleMic() {
    if (_status != CallStatus.connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait, connecting...'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      final success = _callService.toggleMicrophone();
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait, connecting...'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() {
        _isMicMuted = _callService.isMicMuted;
      });
    } catch (e) {
      debugPrint('Error toggling mic: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait, connecting...'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _toggleCamera() {
    if (_status != CallStatus.connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait, connecting...'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      final success = _callService.toggleCamera();
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait, connecting...'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() {
        _isCameraOff = _callService.isCameraOff;
      });
    } catch (e) {
      debugPrint('Error toggling camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait, connecting...'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    await _callService.switchCamera();
    setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    await _callService.toggleSpeakerphone();
    setState(() {
      _isSpeakerOn = _callService.isSpeakerOn;
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _getStatusText() {
    switch (_status) {
      case CallStatus.calling:
        return 'Calling...';
      case CallStatus.ringing:
        return 'Ringing...';
      case CallStatus.connected:
        return _formatDuration(_durationNotifier.value);
      case CallStatus.rejected:
        return 'Call Declined';
      case CallStatus.ended:
        return 'Call Ended';
      case CallStatus.missed:
        return 'Missed Call';
      case CallStatus.accepted:
        return 'Connecting...';
      case CallStatus.busy:
        return 'User Busy';
    }
  }

  @override
  void dispose() {
    _isDismissed = true;
    _proximitySubscription?.cancel();
    _proximitySubscription = null;
    _ringTimeoutTimer?.cancel();
    _statusPollingTimer?.cancel();
    _statusPollingTimer = null;
    CallAudioToneService.instance.stop();
    _pulseController.dispose();
    _callTimer?.cancel();
    _durationNotifier.dispose();
    _callService.cleanup();
    super.dispose();
  }

  Widget _buildAvatarFallback(String cleanPartner) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
            Color(0xFF020617),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                      blurRadius: 36,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: UserAvatar(
                  handle: cleanPartner,
                  size: 110,
                  fontSize: 42,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '@$cleanPartner',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _getStatusText(),
                style: const TextStyle(
                  color: Color(0xFF60A5FA),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.callType == CallType.video;
    final partnerHandle = widget.isCaller
        ? widget.call.receiverHandle
        : widget.call.callerHandle;
    final cleanPartner = partnerHandle.replaceAll('@', '');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !_isDismissed) {
          await _endCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090D16),
        body: Stack(
          children: [
            // ── 1. Video Views (If Video Call) ─────────────────────────
            if (isVideo) ...[
              // Main Fullscreen Video View (Smooth Swapped)
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeInOutCubic,
                  switchOutCurve: Curves.easeInOutCubic,
                  child: _isLocalFullScreen
                      // Self Camera as Fullscreen
                      ? KeyedSubtree(
                          key: const ValueKey('local_fullscreen'),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (!_isCameraOff)
                                RepaintBoundary(
                                  child: RTCVideoView(
                                    _callService.localRenderer,
                                    mirror: _callService.isFrontCamera,
                                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                  ),
                                )
                              else
                                _buildAvatarFallback(widget.currentUserHandle),
                            ],
                          ),
                        )
                      // Remote Partner as Fullscreen
                      : KeyedSubtree(
                          key: const ValueKey('remote_fullscreen'),
                          child: ValueListenableBuilder<MediaStream?>(
                            valueListenable: _callService.remoteStreamNotifier,
                            builder: (context, remoteStream, _) {
                              final hasRemoteVideo = remoteStream != null &&
                                  remoteStream.getVideoTracks().isNotEmpty;

                              if (hasRemoteVideo) {
                                return RepaintBoundary(
                                  child: RTCVideoView(
                                    _callService.remoteRenderer,
                                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                  ),
                                );
                              }

                              return _buildAvatarFallback(cleanPartner);
                            },
                          ),
                        ),
                ),
              ),

              // Floating Corner PiP Preview (Tap to Swap, Drag to Reposition)
              Positioned(
                top: _pipOffset.dy,
                right: _pipOffset.dx,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _pipOffset = Offset(
                        (_pipOffset.dx - details.delta.dx).clamp(10.0, MediaQuery.of(context).size.width - 130),
                        (_pipOffset.dy + details.delta.dy).clamp(50.0, MediaQuery.of(context).size.height - 240),
                      );
                    });
                  },
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isLocalFullScreen = !_isLocalFullScreen;
                    });
                  },
                  child: Container(
                    width: 110,
                    height: 155,
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        // PiP Content (Swapped)
                        Positioned.fill(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            switchInCurve: Curves.easeInOutCubic,
                            switchOutCurve: Curves.easeInOutCubic,
                            child: _isLocalFullScreen
                                // In local fullscreen mode, PiP shows Remote Partner
                                ? KeyedSubtree(
                                    key: const ValueKey('pip_remote'),
                                    child: ValueListenableBuilder<MediaStream?>(
                                      valueListenable: _callService.remoteStreamNotifier,
                                      builder: (context, remoteStream, _) {
                                        final hasRemote = remoteStream != null &&
                                            remoteStream.getVideoTracks().isNotEmpty;
                                        if (hasRemote) {
                                          return RepaintBoundary(
                                            child: RTCVideoView(
                                              _callService.remoteRenderer,
                                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                            ),
                                          );
                                        }
                                        return Container(
                                          color: const Color(0xFF1E293B),
                                          child: Center(
                                            child: UserAvatar(
                                              handle: cleanPartner,
                                              size: 40,
                                              fontSize: 16,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                // In remote fullscreen mode, PiP shows Local Camera
                                : KeyedSubtree(
                                    key: const ValueKey('pip_local'),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (!_isCameraOff)
                                          RepaintBoundary(
                                            child: RTCVideoView(
                                              _callService.localRenderer,
                                              mirror: _callService.isFrontCamera,
                                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                            ),
                                          )
                                        else
                                          Container(
                                            color: const Color(0xFF1E293B),
                                            child: Center(
                                              child: UserAvatar(
                                                handle: widget.currentUserHandle,
                                                size: 40,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),

                        // Swap Hint Badge (Top Left of PiP)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.all(3.5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.swap_horiz_rounded,
                              color: Colors.white,
                              size: 13,
                            ),
                          ),
                        ),

                        // Switch Camera Flip button (Bottom Right of PiP if local video in PiP)
                        if (!_isLocalFullScreen && !_isCameraOff)
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: _switchCamera,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.flip_camera_ios_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // ── 2. Audio Call View ─────────────────────────────────────
            if (!isVideo)
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF0F172A),
                        Color(0xFF020617),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (_status == CallStatus.connected
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFF3B82F6))
                                      .withValues(alpha: 0.25),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: UserAvatar(
                              handle: cleanPartner,
                              size: 120,
                              fontSize: 44,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '@$cleanPartner',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Vadodara Community Call',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _status == CallStatus.connected
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFF60A5FA),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ValueListenableBuilder<int>(
                                valueListenable: _durationNotifier,
                                builder: (context, seconds, _) => Text(
                                  _status == CallStatus.connected
                                      ? _formatDuration(seconds)
                                      : _getStatusText(),
                                  style: TextStyle(
                                    color: _status == CallStatus.connected
                                        ? const Color(0xFF4ADE80)
                                        : Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Reconnecting Banner (WhatsApp Style) ───────────────────
            Positioned(
              top: 95,
              left: 20,
              right: 20,
              child: SafeArea(
                bottom: false,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _callService.isReconnectingNotifier,
                  builder: (context, isReconnecting, _) {
                    if (!isReconnecting) return const SizedBox.shrink();
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD97706).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Reconnecting... Poor connection',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── 3. Top Status Header ───────────────────────────────────
            Positioned(
              top: 50,
              left: 20,
              child: SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_rounded, size: 13, color: Color(0xFF4ADE80)),
                      const SizedBox(width: 6),
                      Text(
                        isVideo ? 'Video Call' : 'Voice Call',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isVideo && _status == CallStatus.connected) ...[
                        const SizedBox(width: 6),
                        ValueListenableBuilder<int>(
                          valueListenable: _durationNotifier,
                          builder: (context, seconds, _) => Text(
                            '• ${_formatDuration(seconds)}',
                            style: const TextStyle(
                              color: Color(0xFF4ADE80),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ── 4. Bottom Floating Action Pill ─────────────────────────
            Positioned(
              left: 20,
              right: 20,
              bottom: 36,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(36),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Mic Mute Button
                      _buildPillButton(
                        icon: _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        isActive: _isMicMuted,
                        isEnabled: _status == CallStatus.connected,
                        activeColor: const Color(0xFFEF4444),
                        tooltip: _isMicMuted ? 'Unmute' : 'Mute',
                        onTap: _toggleMic,
                      ),

                      // Speaker Toggle Button
                      _buildPillButton(
                        icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        isActive: _isSpeakerOn,
                        isEnabled: _status == CallStatus.connected,
                        activeColor: const Color(0xFF3B82F6),
                        tooltip: 'Speaker',
                        onTap: _toggleSpeaker,
                      ),

                      // Video Camera Toggle (If Video Call)
                      if (isVideo) ...[
                        _buildPillButton(
                          icon: _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                          isActive: _isCameraOff,
                          isEnabled: _status == CallStatus.connected,
                          activeColor: const Color(0xFFEF4444),
                          tooltip: 'Camera',
                          onTap: _toggleCamera,
                        ),

                        // Switch Camera Flip Button
                        _buildPillButton(
                          icon: Icons.flip_camera_ios_rounded,
                          isActive: false,
                          isEnabled: _status == CallStatus.connected,
                          tooltip: 'Flip Camera',
                          onTap: _switchCamera,
                        ),
                      ],

                      // End Call Button
                      Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: _endCall,
                          customBorder: const CircleBorder(),
                          splashColor: Colors.white24,
                          highlightColor: Colors.white12,
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.call_end_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── 5. Proximity Sensor Black Screen (Ear touch protection) ──
            if (_isNear && _status == CallStatus.connected && !isVideo)
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(
                    color: Colors.black,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillButton({
    required IconData icon,
    required bool isActive,
    bool isEnabled = true,
    Color? activeColor,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: isEnabled ? onTap : () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please wait, connecting...'),
              duration: Duration(milliseconds: 1500),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        customBorder: const CircleBorder(),
        splashColor: isEnabled ? Colors.white24 : Colors.transparent,
        highlightColor: isEnabled ? Colors.white12 : Colors.transparent,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isEnabled ? 1.0 : 0.4,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isEnabled && isActive
                  ? (activeColor ?? Colors.white)
                  : Colors.white.withValues(alpha: isEnabled ? 0.12 : 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isEnabled ? Colors.white : Colors.white60,
              size: 23,
            ),
          ),
        ),
      ),
    );
  }
}
