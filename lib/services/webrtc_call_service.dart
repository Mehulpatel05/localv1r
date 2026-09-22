import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/call_model.dart';
import 'notification_service.dart';

typedef OnCallStateChanged = void Function(CallStatus status);

class WebRtcCallService {
  static final WebRtcCallService instance = WebRtcCallService._internal();
  factory WebRtcCallService() => instance;
  WebRtcCallService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  CallModel? currentCall;
  StreamSubscription<DocumentSnapshot>? _callDocSub;
  StreamSubscription<QuerySnapshot>? _candidatesSub;

  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = false;
  bool _isFrontCamera = true;
  bool _renderersInitialized = false;

  bool get isMicMuted => _isMicMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isFrontCamera => _isFrontCamera;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  Future<void> initRenderers() async {
    if (!_renderersInitialized) {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersInitialized = true;
    }
  }

  /// Request required mic and camera permissions before starting/answering a call
  Future<bool> requestPermissions(CallType callType) async {
    final micStatus = await Permission.microphone.request();
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      return false;
    }

    if (callType == CallType.video) {
      final camStatus = await Permission.camera.request();
      if (camStatus.isDenied || camStatus.isPermanentlyDenied) {
        return false;
      }
    }
    return true;
  }

  /// Helper to get consistent 1-on-1 chatId between two users
  String _getChatId(String user1, String user2) {
    final u1 = user1.replaceAll('@', '').trim().toLowerCase();
    final u2 = user2.replaceAll('@', '').trim().toLowerCase();
    final users = [u1, u2]..sort();
    return users.join('_');
  }

  /// Start an outgoing call (Audio or Video)
  Future<CallModel> makeCall({
    required String callerHandle,
    required String receiverHandle,
    required CallType callType,
  }) async {
    final hasPermissions = await requestPermissions(callType);
    if (!hasPermissions) {
      throw Exception('Camera or Microphone permissions not granted.');
    }

    await initRenderers();

    final cleanCaller = callerHandle.replaceAll('@', '').trim();
    final cleanReceiver = receiverHandle.replaceAll('@', '').trim();
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Fetch receiver profile to get target UID for notification
    String receiverUid = '';
    try {
      final doc = await _firestore.collection('profiles').doc(cleanReceiver).get();
      receiverUid = doc.data()?['ownerUid'] ?? '';
    } catch (_) {}

    final callDoc = _firestore.collection('calls').doc();
    final callId = callDoc.id;

    final initialCall = CallModel(
      callId: callId,
      callerHandle: cleanCaller,
      callerUid: myUid,
      receiverHandle: cleanReceiver,
      receiverUid: receiverUid,
      callType: callType,
      status: CallStatus.calling,
      createdAt: DateTime.now(),
    );

    currentCall = initialCall;

    // 1. Get user media (local audio / video)
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': callType == CallType.video
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localRenderer.srcObject = _localStream;

    // 2. Create peer connection
    _peerConnection = await createPeerConnection(_iceServers);

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
      }
    };

    // Add local tracks to peer connection
    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // 3. ICE candidate handling
    final callerCandidatesCol = callDoc.collection('callerCandidates');
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        callerCandidatesCol.add(candidate.toMap());
      }
    };

    // 4. Create WebRTC Offer
    final offerConstraints = <String, dynamic>{
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': callType == CallType.video ? 1 : 0,
    };
    final offer = await _peerConnection!.createOffer(offerConstraints);
    await _peerConnection!.setLocalDescription(offer);

    final callPayload = initialCall.toFirestore();
    callPayload['offer'] = {
      'type': offer.type,
      'sdp': offer.sdp,
    };

    await callDoc.set(callPayload);

    // Send push notification to target receiver
    NotificationService().sendNotification(
      targetHandle: cleanReceiver,
      targetUid: receiverUid.isNotEmpty ? receiverUid : null,
      title: '@$cleanCaller is calling...',
      body: callType == CallType.video ? 'Incoming Video Call 📹' : 'Incoming Voice Call 📞',
      data: {
        'type': 'call',
        'callId': callId,
        'callType': callType.name,
        'callerHandle': cleanCaller,
      },
    );

    // Default speaker settings
    if (callType == CallType.video) {
      setSpeakerphone(true);
    } else {
      setSpeakerphone(false);
    }

    _isMicMuted = false;
    _isCameraOff = false;
    _isFrontCamera = true;

    return initialCall;
  }

  /// Answer an incoming call
  Future<void> answerCall(CallModel call) async {
    final hasPermissions = await requestPermissions(call.callType);
    if (!hasPermissions) {
      await rejectCall(call);
      throw Exception('Camera or Microphone permissions not granted.');
    }

    await initRenderers();
    currentCall = call;

    final callDoc = _firestore.collection('calls').doc(call.callId);

    // 1. Get user media
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': call.callType == CallType.video
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localRenderer.srcObject = _localStream;

    // 2. Create peer connection
    _peerConnection = await createPeerConnection(_iceServers);

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
      }
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // 3. ICE candidate handling
    final receiverCandidatesCol = callDoc.collection('receiverCandidates');
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        receiverCandidatesCol.add(candidate.toMap());
      }
    };

    // 4. Set remote description from caller offer
    if (call.offer != null) {
      final sdp = call.offer!['sdp'] as String?;
      final type = call.offer!['type'] as String?;
      if (sdp != null && type != null) {
        final rtcSessionDesc = RTCSessionDescription(sdp, type);
        await _peerConnection!.setRemoteDescription(rtcSessionDesc);
      }
    }

    // 5. Create WebRTC Answer
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    // Update call doc in Firestore to connected
    await callDoc.update({
      'status': 'connected',
      'startedAt': FieldValue.serverTimestamp(),
      'answer': {
        'type': answer.type,
        'sdp': answer.sdp,
      },
    });

    // Listen for caller's ICE candidates
    final callerCandidatesCol = callDoc.collection('callerCandidates');
    _candidatesSub = callerCandidatesCol.snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            _peerConnection?.addCandidate(
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ),
            );
          }
        }
      }
    });

    // Speakerphone configuration
    if (call.callType == CallType.video) {
      setSpeakerphone(true);
    } else {
      setSpeakerphone(false);
    }

    _isMicMuted = false;
    _isCameraOff = false;
    _isFrontCamera = true;
  }

  /// Listen for remote answer (used by caller)
  void listenForAnswerAndCandidates(String callId) {
    final callDoc = _firestore.collection('calls').doc(callId);

    _callDocSub?.cancel();
    _callDocSub = callDoc.snapshots().listen((snapshot) async {
      if (!snapshot.exists || snapshot.data() == null) return;
      final data = snapshot.data()!;
      final status = data['status'] as String?;

      if (status == 'connected' && _peerConnection != null) {
        final answerMap = data['answer'] as Map<String, dynamic>?;
        if (answerMap != null && _peerConnection?.getRemoteDescription() == null) {
          final sdp = answerMap['sdp'] as String?;
          final type = answerMap['type'] as String?;
          if (sdp != null && type != null) {
            final desc = RTCSessionDescription(sdp, type);
            await _peerConnection!.setRemoteDescription(desc);
          }
        }
      }
    });

    // Listen for receiver's ICE candidates
    _candidatesSub?.cancel();
    final receiverCandidatesCol = callDoc.collection('receiverCandidates');
    _candidatesSub = receiverCandidatesCol.snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            _peerConnection?.addCandidate(
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ),
            );
          }
        }
      }
    });
  }

  /// Toggle Microphone Mute
  void toggleMicrophone() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        _isMicMuted = !_isMicMuted;
        for (final track in audioTracks) {
          track.enabled = !_isMicMuted;
        }
      }
    }
  }

  /// Toggle Camera On / Off
  void toggleCamera() {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        _isCameraOff = !_isCameraOff;
        for (final track in videoTracks) {
          track.enabled = !_isCameraOff;
        }
      }
    }
  }

  /// Switch between Front and Back camera
  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks.first);
        _isFrontCamera = !_isFrontCamera;
      }
    }
  }

  /// Toggle Speakerphone vs Earpiece
  Future<void> toggleSpeakerphone() async {
    _isSpeakerOn = !_isSpeakerOn;
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  /// Set Speakerphone explicitly
  Future<void> setSpeakerphone(bool enable) async {
    _isSpeakerOn = enable;
    await Helper.setSpeakerphoneOn(enable);
  }

  /// Reject an incoming call
  Future<void> rejectCall(CallModel call) async {
    try {
      await _firestore.collection('calls').doc(call.callId).update({
        'status': 'rejected',
        'endedAt': FieldValue.serverTimestamp(),
      });
      await _writeCallHistoryMessage(
        call: call.copyWith(status: CallStatus.rejected),
        finalStatus: 'declined',
        durationSeconds: 0,
      );
    } catch (e) {
      debugPrint('Error rejecting call: $e');
    } finally {
      await cleanup();
    }
  }

  /// End an active or outgoing call
  Future<void> endCall({
    required CallModel call,
    required CallStatus endStatus,
    int durationSeconds = 0,
  }) async {
    try {
      await _firestore.collection('calls').doc(call.callId).update({
        'status': endStatus.name,
        'endedAt': FieldValue.serverTimestamp(),
        'durationSeconds': durationSeconds,
      });

      String logStatus = 'ended';
      if (endStatus == CallStatus.missed) {
        logStatus = 'missed';
      } else if (endStatus == CallStatus.rejected) {
        logStatus = 'declined';
      } else if (endStatus == CallStatus.busy) {
        logStatus = 'busy';
      }

      await _writeCallHistoryMessage(
        call: call,
        finalStatus: logStatus,
        durationSeconds: durationSeconds,
      );
    } catch (e) {
      debugPrint('Error ending call: $e');
    } finally {
      await cleanup();
    }
  }

  /// Inserts a call summary bubble into the 1-on-1 chat history
  Future<void> _writeCallHistoryMessage({
    required CallModel call,
    required String finalStatus,
    required int durationSeconds,
  }) async {
    try {
      final chatId = _getChatId(call.callerHandle, call.receiverHandle);
      final chatRef = _firestore.collection('chats').doc(chatId);
      final messageRef = chatRef.collection('messages').doc();

      final isVideo = call.callType == CallType.video;
      final typeLabel = isVideo ? 'Video call' : 'Voice call';
      final icon = isVideo ? '📹' : '📞';

      String summaryText;
      if (finalStatus == 'missed') {
        summaryText = '$icon Missed $typeLabel';
      } else if (finalStatus == 'declined') {
        summaryText = '$icon Declined $typeLabel';
      } else if (finalStatus == 'busy') {
        summaryText = '$icon Busy';
      } else {
        if (durationSeconds > 0) {
          final minutes = durationSeconds ~/ 60;
          final seconds = durationSeconds % 60;
          final timeStr = minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
          summaryText = '$icon $typeLabel · $timeStr';
        } else {
          summaryText = '$icon $typeLabel ended';
        }
      }

      final now = FieldValue.serverTimestamp();

      await _firestore.runTransaction((transaction) async {
        transaction.set(messageRef, {
          'senderHandle': call.callerHandle,
          'senderUid': call.callerUid,
          'content': summaryText,
          'type': 'call_log',
          'callType': isVideo ? 'video' : 'audio',
          'callStatus': finalStatus,
          'durationSeconds': durationSeconds,
          'timestamp': now,
          'status': 'sent',
          'isRead': false,
        });

        transaction.set(chatRef, {
          'participants': [call.callerHandle, call.receiverHandle],
          'lastMessage': summaryText,
          'lastSenderHandle': call.callerHandle,
          'updatedAt': now,
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('Error logging call in chat: $e');
    }
  }

  /// Clean up all WebRTC streams, peer connection, and subscriptions
  Future<void> cleanup() async {
    _callDocSub?.cancel();
    _callDocSub = null;
    _candidatesSub?.cancel();
    _candidatesSub = null;

    try {
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      await _localStream?.dispose();
      _localStream = null;

      _remoteStream?.getTracks().forEach((track) {
        track.stop();
      });
      await _remoteStream?.dispose();
      _remoteStream = null;

      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;

      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;
    } catch (e) {
      debugPrint('WebRTC cleanup error: $e');
    } finally {
      currentCall = null;
      _isMicMuted = false;
      _isCameraOff = false;
      _isSpeakerOn = false;
      _isFrontCamera = true;
    }
  }
}
