import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../main.dart';
import '../models/call_model.dart';
import '../screens/chat/incoming_call_screen.dart';
import 'webrtc_call_service.dart';
import 'notification_service.dart';

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
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final doc = change.doc;
          final call = CallModel.fromFirestore(doc);

          // Only process calls created within the last 30 seconds to avoid old stale or late offline-synced calls
          final now = DateTime.now();
          if (now.difference(call.createdAt).inSeconds.abs() > 30) {
            continue;
          }

          // Don't show if already presenting this incoming call
          if (_activeIncomingCallId == call.callId) {
            continue;
          }

          // If already engaged in an active call -> Auto mark as busy
          if (WebRtcCallService.instance.currentCall != null) {
            FirebaseFirestore.instance.collection('calls').doc(call.callId).update({
              'status': 'busy',
              'endedAt': FieldValue.serverTimestamp(),
            }).catchError((_) {});

            WebRtcCallService.instance.endCall(
              call: call,
              endStatus: CallStatus.busy,
              durationSeconds: 0,
            );

            // Subtle call-waiting alert on receiver's device
            try {
              FlutterRingtonePlayer().playNotification();
              final ctx = navigatorKey.currentContext;
              if (ctx != null && ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Call from @${call.callerHandle.replaceAll('@', '')} · Notified busy'),
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } catch (_) {}

            continue;
          }

          final allowed = await _isCallAllowed(call.callerHandle);
          if (!allowed) {
            continue;
          }

          _showIncomingCall(call);
        }
      }
    }, onError: (e) {
      debugPrint('CallListenerService error: $e');
    });
  }

  Future<bool> _isCallAllowed(String callerHandle) async {
    final myHandle = _currentUserHandle ?? '';
    if (myHandle.isEmpty) return true;

    try {
      final cleanCaller = callerHandle.replaceAll('@', '').trim();

      // Check block list first
      final block1 = await FirebaseFirestore.instance.collection('blocks').doc('${myHandle}_$cleanCaller').get();
      final block2 = await FirebaseFirestore.instance.collection('blocks').doc('${cleanCaller}_$myHandle').get();
      if (block1.exists || block2.exists) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      String? privacy;

      try {
        final profileDoc = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(myHandle)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 2));
        if (profileDoc.exists && profileDoc.data() != null) {
          privacy = profileDoc.data()?['callPrivacy'] as String?;
          if (privacy != null) {
            await prefs.setString('call_privacy', privacy);
          }
        }
      } catch (_) {}

      privacy ??= prefs.getString('call_privacy');

      privacy = (privacy ?? 'everyone').toLowerCase().trim();

      if (privacy == 'nobody') {
        return false;
      }

      if (privacy == 'friends') {
        final cleanCaller = callerHandle.replaceAll('@', '').trim();
        final sorted = [myHandle, cleanCaller]..sort();
        final friendshipId = sorted.join('_');
        final friendshipDoc = await FirebaseFirestore.instance
            .collection('friendships')
            .doc(friendshipId)
            .get();
        return friendshipDoc.exists;
      }
    } catch (_) {}

    return true;
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
    _callSub?.cancel();
    _callSub = null;
    _currentUserHandle = null;
    _activeIncomingCallId = null;
  }
}
