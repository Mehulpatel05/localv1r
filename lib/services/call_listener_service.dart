import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../models/call_model.dart';
import '../screens/chat/incoming_call_screen.dart';
import 'auth_service.dart';
import 'webrtc_call_service.dart';
import 'notification_service.dart';

class CallListenerService {
  static final CallListenerService instance = CallListenerService._internal();
  factory CallListenerService() => instance;
  CallListenerService._internal();

  Timer? _pollingTimer;
  String? _currentUserHandle;
  String? _activeIncomingCallId;

  void startListening(String handle) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty || cleanHandle == 'Guest') return;

    if (_currentUserHandle == cleanHandle && _pollingTimer != null) return;
    _currentUserHandle = cleanHandle;

    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/calls/active?handle=$cleanHandle'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 3));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final callData = body['call'] as Map<String, dynamic>?;
          if (callData == null) return;

          final call = CallModel.fromJson(callData);

          // Only process incoming ringing calls
          if (call.receiverHandle.toLowerCase() != cleanHandle.toLowerCase() ||
              call.status != CallStatus.ringing && call.status != CallStatus.calling) {
            return;
          }

          // Avoid processing stale calls older than 45 seconds
          final now = DateTime.now();
          if (now.difference(call.createdAt).inSeconds.abs() > 45) {
            return;
          }

          // Don't show if already presenting this incoming call
          if (_activeIncomingCallId == call.callId) {
            return;
          }

          // If already in an active call -> mark as busy
          if (WebRtcCallService.instance.currentCall != null) {
            http.post(
              Uri.parse('${AuthService.baseUrl}/calls/${call.callId}/status'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'status': 'busy'}),
            ).catchError((_) => http.Response('', 500));
            return;
          }

          _showIncomingCall(call);
        }
      } catch (_) {}
    });
  }

  void _showIncomingCall(CallModel call) {
    _activeIncomingCallId = call.callId;

    // Wake screen & trigger native high-priority incoming call notification
    NotificationService.instance.showIncomingCallNotification(call: call);

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
        NotificationService.instance.cancelCallNotification(call.callId);
        if (_activeIncomingCallId == call.callId) {
          _activeIncomingCallId = null;
        }
      });
    }
  }

  void stopListening() {
    if (_activeIncomingCallId != null) {
      NotificationService.instance.cancelCallNotification(_activeIncomingCallId!);
    }
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _currentUserHandle = null;
    _activeIncomingCallId = null;
  }
}
