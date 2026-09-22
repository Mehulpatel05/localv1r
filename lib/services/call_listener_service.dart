import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/call_model.dart';
import '../screens/chat/incoming_call_screen.dart';
import 'webrtc_call_service.dart';

class CallListenerService {
  static final CallListenerService instance = CallListenerService._internal();
  factory CallListenerService() => instance;
  CallListenerService._internal();

  StreamSubscription<QuerySnapshot>? _callSub;
  String? _currentUserHandle;
  String? _activeIncomingCallId;

  void startListening(String handle) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty || cleanHandle == 'Guest') return;

    if (_currentUserHandle == cleanHandle && _callSub != null) return;
    _currentUserHandle = cleanHandle;

    _callSub?.cancel();

    _callSub = FirebaseFirestore.instance
        .collection('calls')
        .where('receiverHandle', isEqualTo: cleanHandle)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final doc = change.doc;
          final call = CallModel.fromFirestore(doc);

          // Only process calls created within the last 45 seconds to avoid old stale calls
          final now = DateTime.now();
          if (now.difference(call.createdAt).inSeconds > 45) {
            continue;
          }

          // Don't show if already in an active call or if already presenting this call
          if (_activeIncomingCallId == call.callId ||
              WebRtcCallService.instance.currentCall != null) {
            continue;
          }

          _showIncomingCall(call);
        }
      }
    }, onError: (e) {
      debugPrint('CallListenerService error: $e');
    });
  }

  void _showIncomingCall(CallModel call) {
    _activeIncomingCallId = call.callId;

    final navContext = navigatorKey.currentContext;
    if (navContext != null && _currentUserHandle != null) {
      Navigator.push(
        navContext,
        MaterialPageRoute(
          builder: (_) => IncomingCallScreen(
            call: call,
            currentUserHandle: _currentUserHandle!,
          ),
          fullscreenDialog: true,
        ),
      ).then((_) {
        if (_activeIncomingCallId == call.callId) {
          _activeIncomingCallId = null;
        }
      });
    }
  }

  void stopListening() {
    _callSub?.cancel();
    _callSub = null;
    _currentUserHandle = null;
    _activeIncomingCallId = null;
  }
}
