import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../core/widgets/user_avatar.dart';
import '../../main.dart';
import '../../models/call_model.dart';
import '../../services/auth_service.dart';
import '../../services/webrtc_call_service.dart';
import '../../services/notification_service.dart';
import '../../services/call_audio_tone_service.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final CallModel call;
  final String currentUserHandle;

  const IncomingCallScreen({
    super.key,
    required this.call,
    required this.currentUserHandle,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _statusPollingTimer;
  bool _isProcessing = false;
  bool _isDismissed = false;

  void _safeDismiss() {
    if (_isDismissed) return;
    _isDismissed = true;
    _statusPollingTimer?.cancel();
    _statusPollingTimer = null;
    CallAudioToneService.instance.stop();
    NotificationService().cancelCallNotification(widget.call.callId);
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Notify caller that receiver's phone is ringing
    http.post(
      Uri.parse('${AuthService.baseUrl}/calls/${widget.call.callId}/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'status': 'ringing'}),
    ).catchError((_) => http.Response('', 500));

    // Start playing incoming ringtone + vibration on receiver's phone
    CallAudioToneService.instance.playIncomingRingtone();

    // Poll call status in D1
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/calls/${widget.call.callId}'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 2));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final status = (data['call']?['status'] ?? '').toString().toLowerCase();
          if (status == 'ended' || status == 'rejected' || status == 'missed') {
            _safeDismiss();
          }
        } else if (res.statusCode == 404) {
          _safeDismiss();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = null;
    CallAudioToneService.instance.stop();
    NotificationService().cancelCallNotification(widget.call.callId);
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _acceptCall() async {
    if (_isProcessing || _isDismissed) return;
    _isProcessing = true;
    _statusPollingTimer?.cancel();
    _statusPollingTimer = null;
    HapticFeedback.heavyImpact();
    CallAudioToneService.instance.stop();
    NotificationService().cancelCallNotification(widget.call.callId);

    try {
      final hasPermissions = await WebRtcCallService.instance.requestPermissions(widget.call.callType);
      if (!hasPermissions) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissions required to answer call'),
              duration: Duration(seconds: 2),
            ),
          );
          _safeDismiss();
        }
        await WebRtcCallService.instance.rejectCall(widget.call);
        return;
      }

      final answerFuture = WebRtcCallService.instance.answerCall(widget.call);

      if (mounted) {
        _isDismissed = true;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, anim1, anim2) => CallScreen(
              call: widget.call.copyWith(status: CallStatus.connected),
              currentUserHandle: widget.currentUserHandle,
              isCaller: false,
            ),
            transitionDuration: const Duration(milliseconds: 250),
            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
            fullscreenDialog: true,
          ),
        );
      }

      await answerFuture;
    } catch (e) {
      debugPrint('Error answering call: $e');
      final currentCtx = navigatorKey.currentContext;
      if (currentCtx != null && currentCtx.mounted) {
        ScaffoldMessenger.of(currentCtx).showSnackBar(
          SnackBar(
            content: Text('Call connection failed: ${e.toString().replaceAll('Exception: ', '')}'),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(currentCtx).maybePop();
      }
      await WebRtcCallService.instance.rejectCall(widget.call);
    }
  }

  Future<void> _declineCall() async {
    if (_isProcessing || _isDismissed) return;
    _isProcessing = true;
    HapticFeedback.mediumImpact();
    _safeDismiss();

    WebRtcCallService.instance.rejectCall(widget.call);
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.callType == CallType.video;
    final caller = widget.call.callerHandle.replaceAll('@', '');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !_isDismissed) {
          await _declineCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090D16),
        body: Container(
          width: double.infinity,
          height: double.infinity,
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
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 36),

                // Top Details
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                            color: isVideo ? const Color(0xFF60A5FA) : const Color(0xFF4ADE80),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isVideo ? 'Incoming Video Call...' : 'Incoming Voice Call...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '@$caller',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Nearhood Neighbor',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                // Pulsing Avatar
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (isVideo ? const Color(0xFF3B82F6) : const Color(0xFF22C55E))
                              .withValues(alpha: 0.12),
                        ),
                      ),
                      Container(
                        width: 146,
                        height: 146,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (isVideo ? const Color(0xFF3B82F6) : const Color(0xFF22C55E))
                              .withValues(alpha: 0.2),
                        ),
                      ),
                      UserAvatar(
                        handle: caller,
                        size: 120,
                        fontSize: 44,
                      ),
                    ],
                  ),
                ),

                // Bottom Call Action Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Decline Button
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: _isProcessing ? null : _declineCall,
                              customBorder: const CircleBorder(),
                              splashColor: Colors.white24,
                              highlightColor: Colors.white12,
                              child: Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.call_end_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Decline',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),

                      // Accept Button
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: _isProcessing ? null : _acceptCall,
                              customBorder: const CircleBorder(),
                              splashColor: Colors.white24,
                              highlightColor: Colors.white12,
                              child: Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF22C55E).withValues(alpha: 0.45),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: _isProcessing
                                    ? const Center(
                                        child: SizedBox(
                                          width: 30,
                                          height: 30,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 3,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                                        color: Colors.white,
                                        size: 34,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Accept',
                            style: TextStyle(
                              color: Color(0xFF4ADE80),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
