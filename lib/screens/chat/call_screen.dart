import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/call_model.dart';
import '../../services/webrtc_call_service.dart';

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

class _CallScreenState extends State<CallScreen> {
  final WebRtcCallService _callService = WebRtcCallService.instance;

  CallStatus _status = CallStatus.calling;
  int _durationSeconds = 0;
  Timer? _callTimer;
  StreamSubscription<DocumentSnapshot>? _callSubscription;

  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = false;
  bool _isEnding = false;

  @override
  void initState() {
    super.initState();
    _status = widget.call.status;
    _isSpeakerOn = widget.call.callType == CallType.video;

    if (widget.isCaller) {
      _callService.listenForAnswerAndCandidates(widget.call.callId);
    }

    _listenToCallDoc();

    if (_status == CallStatus.connected) {
      _startTimer();
    }
  }

  void _listenToCallDoc() {
    _callSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.call.callId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) {
        _handleCallTerminated(CallStatus.ended);
        return;
      }

      final data = doc.data() ?? {};
      final statusStr = (data['status'] ?? '').toString().toLowerCase();

      if (statusStr == 'connected' && _status != CallStatus.connected) {
        setState(() {
          _status = CallStatus.connected;
        });
        _startTimer();
      } else if (statusStr == 'rejected') {
        _handleCallTerminated(CallStatus.rejected);
      } else if (statusStr == 'ended') {
        _handleCallTerminated(CallStatus.ended);
      } else if (statusStr == 'missed') {
        _handleCallTerminated(CallStatus.missed);
      } else if (statusStr == 'busy') {
        _handleCallTerminated(CallStatus.busy);
      }
    });
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _durationSeconds++;
        });
      }
    });
  }

  void _handleCallTerminated(CallStatus terminalStatus) {
    if (_isEnding) return;
    _isEnding = true;
    _callTimer?.cancel();

    if (mounted) {
      setState(() {
        _status = terminalStatus;
      });
      String msg = 'Call ended';
      if (terminalStatus == CallStatus.rejected) msg = 'Call declined';
      if (terminalStatus == CallStatus.missed) msg = 'Call missed';
      if (terminalStatus == CallStatus.busy) msg = 'User is busy';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> _endCall() async {
    if (_isEnding) return;
    _isEnding = true;
    HapticFeedback.mediumImpact();
    _callTimer?.cancel();

    final endStatus = _status == CallStatus.connected
        ? CallStatus.ended
        : (widget.isCaller ? CallStatus.missed : CallStatus.rejected);

    await _callService.endCall(
      call: widget.call,
      endStatus: endStatus,
      durationSeconds: _durationSeconds,
    );

    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _toggleMic() {
    _callService.toggleMicrophone();
    setState(() {
      _isMicMuted = _callService.isMicMuted;
    });
  }

  void _toggleCamera() {
    _callService.toggleCamera();
    setState(() {
      _isCameraOff = _callService.isCameraOff;
    });
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
        return _formatDuration(_durationSeconds);
      case CallStatus.rejected:
        return 'Call Declined';
      case CallStatus.ended:
        return 'Call Ended';
      case CallStatus.missed:
        return 'Missed Call';
      case CallStatus.busy:
        return 'User Busy';
    }
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    _callTimer?.cancel();
    _callService.cleanup();
    super.dispose();
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
        if (!didPop) {
          await _endCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Stack(
          children: [
            // 1. Video Views if Video Call
            if (isVideo) ...[
              // Remote Video Stream (Fullscreen)
              Positioned.fill(
                child: _status == CallStatus.connected
                    ? RTCVideoView(
                        _callService.remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Container(
                        color: const Color(0xFF0F172A),
                      ),
              ),

              // Local Mini Preview (Top-Right Pip)
              if (!_isCameraOff)
                Positioned(
                  top: 50,
                  right: 20,
                  child: Container(
                    width: 110,
                    height: 155,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RTCVideoView(
                      _callService.localRenderer,
                      mirror: _callService.isFrontCamera,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
            ],

            // 2. Audio Call Background & Avatar
            if (!isVideo || _status != CallStatus.connected)
              Positioned.fill(
                child: Container(
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
                        UserAvatar(
                          handle: cleanPartner,
                          size: 110,
                          fontSize: 40,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '@$cleanPartner',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _getStatusText(),
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
                ),
              ),

            // Top Status Bar (for Video Connected State)
            if (isVideo && _status == CallStatus.connected)
              Positioned(
                top: 50,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4ADE80),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '@$cleanPartner • ${_formatDuration(_durationSeconds)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 3. Bottom Controls Action Bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mic Mute Button
                        _buildControlButton(
                          icon: _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          isActive: _isMicMuted,
                          activeColor: const Color(0xFFEF4444),
                          tooltip: 'Mute',
                          onTap: _toggleMic,
                        ),

                        // Speaker Toggle Button
                        _buildControlButton(
                          icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                          isActive: _isSpeakerOn,
                          activeColor: const Color(0xFF3B82F6),
                          tooltip: 'Speaker',
                          onTap: _toggleSpeaker,
                        ),

                        // Video / Flip Camera Buttons (if Video Call)
                        if (isVideo) ...[
                          _buildControlButton(
                            icon: _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                            isActive: _isCameraOff,
                            activeColor: const Color(0xFFEF4444),
                            tooltip: 'Camera',
                            onTap: _toggleCamera,
                          ),
                          _buildControlButton(
                            icon: Icons.flip_camera_ios_rounded,
                            isActive: false,
                            tooltip: 'Flip',
                            onTap: _switchCamera,
                          ),
                        ],

                        // End Call Button
                        GestureDetector(
                          onTap: _endCall,
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.call_end_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required bool isActive,
    Color? activeColor,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive
              ? (activeColor ?? Colors.white)
              : Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
