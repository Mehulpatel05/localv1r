import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/call_model.dart';
import '../../services/webrtc_call_service.dart';
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
  StreamSubscription<DocumentSnapshot>? _callSubscription;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    HapticFeedback.vibrate();

    // Listen to call doc in Firestore in case caller cancels or times out
    _callSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.call.callId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final data = doc.data();
      final status = (data?['status'] ?? '').toString().toLowerCase();
      if (status == 'ended' || status == 'rejected' || status == 'missed') {
        if (mounted) Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _acceptCall() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    HapticFeedback.heavyImpact();

    try {
      await WebRtcCallService.instance.answerCall(widget.call);
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            call: widget.call.copyWith(status: CallStatus.connected),
            currentUserHandle: widget.currentUserHandle,
            isCaller: false,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not answer call: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _declineCall() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    await WebRtcCallService.instance.rejectCall(widget.call);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.callType == CallType.video;
    final caller = widget.call.callerHandle.replaceAll('@', '');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _declineCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
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
                const SizedBox(height: 40),

                // Top Details
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
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
                          const SizedBox(width: 6),
                          Text(
                            isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '@$caller',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Vadodara Neighbor',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                // Pulsing Avatar in Center
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isVideo ? const Color(0xFF3B82F6) : const Color(0xFF22C55E))
                              .withValues(alpha: 0.25),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: UserAvatar(
                      handle: caller,
                      size: 120,
                      fontSize: 44,
                    ),
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
                          GestureDetector(
                            onTap: _isProcessing ? null : _declineCall,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.call_end_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
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
                          GestureDetector(
                            onTap: _isProcessing ? null : _acceptCall,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
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
