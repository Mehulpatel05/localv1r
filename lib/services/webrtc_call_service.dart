import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/call_model.dart';
import 'notification_service.dart';

class WebRtcCallService {
  static final WebRtcCallService instance = WebRtcCallService._internal();
  factory WebRtcCallService() => instance;
  WebRtcCallService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  final ValueNotifier<MediaStream?> localStreamNotifier = ValueNotifier<MediaStream?>(null);
  final ValueNotifier<MediaStream?> remoteStreamNotifier = ValueNotifier<MediaStream?>(null);
  final ValueNotifier<CallStatus> callStatusNotifier = ValueNotifier<CallStatus>(CallStatus.calling);
  final ValueNotifier<bool> isReconnectingNotifier = ValueNotifier<bool>(false);

  CallModel? currentCall;
  StreamSubscription<DocumentSnapshot>? _callDocSub;
  StreamSubscription<QuerySnapshot>? _candidatesSub;

  final List<RTCIceCandidate> _pendingIceCandidates = [];
  bool _isRemoteDescriptionSet = false;

  bool _isCallActive = false;
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = false;
  bool _isFrontCamera = true;
  bool _renderersInitialized = false;

  bool get isCallActive => _isCallActive;
  bool get isMicMuted => _isMicMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isFrontCamera => _isFrontCamera;
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun.cloudflare.com:3478'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
    ],
    'sdpSemantics': 'unified-plan',
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'iceCandidatePoolSize': 10,
    'continualGatheringPolicy': 'gather_continually',
  };

  /// Fast check if device has an active internet connection
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> initRenderers() async {
    if (!_renderersInitialized) {
      try {
        await localRenderer.initialize();
        await remoteRenderer.initialize();
        _renderersInitialized = true;
      } catch (e) {
        debugPrint('WebRTC renderers initialize warning: $e');
        _renderersInitialized = true;
      }
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

  String _getChatId(String user1, String user2) {
    final u1 = user1.replaceAll('@', '').trim().toLowerCase();
    final u2 = user2.replaceAll('@', '').trim().toLowerCase();
    final users = [u1, u2]..sort();
    return users.join('_');
  }

  /// Optimizes SDP for ultra-low latency audio (Opus speech flags)
  /// and crisp real-camera HD video with immediate packet recovery.
  String _optimizeSdpForLowLatency(String sdp, {required bool isVideo}) {
    final lines = sdp.split('\r\n');
    final modifiedLines = <String>[];
    String? opusPayloadType;

    // 1. Identify Opus payload type
    for (final line in lines) {
      if (line.startsWith('a=rtpmap:') && line.toLowerCase().contains('opus/48000')) {
        final match = RegExp(r'a=rtpmap:(\d+)\s+opus', caseSensitive: false).firstMatch(line);
        if (match != null) {
          opusPayloadType = match.group(1);
        }
      }
    }

    bool opusFmtpFound = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Replace Opus fmtp line with ultra low-latency flags:
      // minptime=10 (10ms packet time eliminates audio buffering delay)
      // useinbandfec=1 (Forward Error Correction prevents retransmission delay)
      // usedtx=1 (Discontinuous transmission prevents jitter buildup during silence)
      // maxaveragebitrate=32000 (studio speech clarity with zero bufferbloat)
      if (opusPayloadType != null && line.startsWith('a=fmtp:$opusPayloadType')) {
        opusFmtpFound = true;
        modifiedLines.add(
          'a=fmtp:$opusPayloadType minptime=10;ptime=20;useinbandfec=1;maxaveragebitrate=32000;stereo=0;sprop-stereo=0;usedtx=1;cbr=0',
        );
        continue;
      }

      // Audio stream header
      if (line.startsWith('m=audio')) {
        modifiedLines.add(line);
        if (opusPayloadType != null && !opusFmtpFound) {
          modifiedLines.add(
            'a=fmtp:$opusPayloadType minptime=10;ptime=20;useinbandfec=1;maxaveragebitrate=32000;stereo=0;sprop-stereo=0;usedtx=1;cbr=0',
          );
          opusFmtpFound = true;
        }
        continue;
      }

      // Video stream header: allocate 1.8 Mbps high clarity bitrate bandwidth
      if (line.startsWith('m=video')) {
        modifiedLines.add(line);
        modifiedLines.add('b=AS:1800');
        modifiedLines.add('b=TIAS:1800000');
        continue;
      }

      modifiedLines.add(line);
    }

    return modifiedLines.join('\r\n');
  }

  /// Boost video encoder bitrate on active senders with real-time framerate preservation
  Future<void> _boostVideoSenderBitrate() async {
    try {
      final senders = await _peerConnection?.getSenders();
      if (senders != null) {
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            final params = sender.parameters;
            if (params.encodings != null && params.encodings!.isNotEmpty) {
              for (final encoding in params.encodings!) {
                encoding.maxBitrate = 1800000; // 1.8 Mbps crisp 720p HD
                encoding.minBitrate = 400000;  // 400 kbps min
                encoding.maxFramerate = 30;
                encoding.scaleResolutionDownBy = 1.0;
              }
              params.degradationPreference = RTCDegradationPreference.MAINTAIN_FRAMERATE;
              await sender.setParameters(params);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Bitrate boost parameter error: $e');
    }
  }

  /// Start an outgoing call (Audio or Video)
  Future<CallModel> makeCall({
    required String callerHandle,
    required String receiverHandle,
    required CallType callType,
    String? existingCallId,
  }) async {
    final cleanCaller = callerHandle.replaceAll('@', '').trim();
    final cleanReceiver = receiverHandle.replaceAll('@', '').trim();
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final callDoc = existingCallId != null && existingCallId.isNotEmpty
        ? _firestore.collection('calls').doc(existingCallId)
        : _firestore.collection('calls').doc();
    final callId = callDoc.id;

    // Parallel validation, permissions & renderer initialization
    final profileFuture = _firestore.collection('profiles').doc(cleanReceiver).get().catchError((_) => null as dynamic);
    final block1Future = _firestore.collection('blocks').doc('${cleanCaller}_$cleanReceiver').get().catchError((_) => null as dynamic);
    final block2Future = _firestore.collection('blocks').doc('${cleanReceiver}_$cleanCaller').get().catchError((_) => null as dynamic);
    final permissionsFuture = requestPermissions(callType);
    final renderersFuture = initRenderers();

    final results = await Future.wait([
      profileFuture,
      block1Future,
      block2Future,
      permissionsFuture,
      renderersFuture,
    ]);

    final profileDoc = results[0] as DocumentSnapshot?;
    final block1Doc = results[1] as DocumentSnapshot?;
    final block2Doc = results[2] as DocumentSnapshot?;
    final hasPermissions = results[3] as bool;

    if (!hasPermissions) {
      throw Exception('Camera or Microphone permissions not granted.');
    }

    if ((block1Doc != null && block1Doc.exists) || (block2Doc != null && block2Doc.exists)) {
      throw Exception('You cannot call this user.');
    }

    String receiverUid = '';
    String callPrivacy = 'everyone';
    if (profileDoc != null && profileDoc.exists && profileDoc.data() != null) {
      final data = profileDoc.data() as Map<String, dynamic>;
      receiverUid = (data['ownerUid'] ?? '').toString();
      callPrivacy = (data['callPrivacy'] as String?)?.toLowerCase().trim() ?? 'everyone';
    }

    if (callPrivacy == 'nobody') {
      throw Exception('@$cleanReceiver is not accepting calls.');
    } else if (callPrivacy == 'friends') {
      final sortedHandles = [cleanCaller, cleanReceiver]..sort();
      final friendshipId = sortedHandles.join('_');
      final friendshipDoc = await _firestore.collection('friendships').doc(friendshipId).get();
      if (!friendshipDoc.exists) {
        throw Exception('@$cleanReceiver only accepts calls from friends.');
      }
    }

    _pendingIceCandidates.clear();
    _isRemoteDescriptionSet = false;

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
    _isCallActive = true;
    callStatusNotifier.value = CallStatus.calling;

    // 1. Get user media with 48kHz Studio Audio & Real HD Camera DSP
    final mediaConstraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'sampleRate': 48000,
        'channelCount': 1,
        'googEchoCancellation': true,
        'googEchoCancellation2': true,
        'googDAEchoCancellation': true,
        'googAutoGainControl': true,
        'googAutoGainControl2': true,
        'googNoiseSuppression': true,
        'googNoiseSuppression2': true,
        'googHighpassFilter': true,
        'googTypingNoiseDetection': true,
        'googAudioMirroring': false,
        'latency': 0,
      },
      'video': callType == CallType.video
          ? {
              'mandatory': {
                'minWidth': '1280',
                'minHeight': '720',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [
                {'minWidth': '1280'},
                {'minHeight': '720'},
                {'minFrameRate': '30'},
                {'googCpuOveruseDetection': true},
                {'googCpuUnderuseThreshold': 55},
                {'googCpuOveruseThreshold': 85},
              ],
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    for (final track in _localStream!.getTracks()) {
      track.enabled = true;
    }
    localRenderer.srcObject = _localStream;
    localStreamNotifier.value = _localStream;

    // 2. Create peer connection with unified-plan and STUN servers
    _peerConnection = await createPeerConnection(_iceServers);
    _setupConnectionStateListeners();

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
        remoteStreamNotifier.value = _remoteStream;
        setSpeakerphone(callType == CallType.video);
      }
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // 3. ICE candidate handling for caller (queued until call doc is created)
    final callerCandidatesCol = callDoc.collection('callerCandidates');
    bool isCallDocCreated = false;
    final List<Map<String, dynamic>> queuedCandidates = [];

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        if (isCallDocCreated) {
          callerCandidatesCol.add(candidate.toMap());
        } else {
          queuedCandidates.add(candidate.toMap());
        }
      }
    };

    // 4. Create WebRTC Offer with Low-Latency SDP
    final offerConstraints = <String, dynamic>{
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': callType == CallType.video ? 1 : 0,
    };
    final offer = await _peerConnection!.createOffer(offerConstraints);
    final optimizedSdp = _optimizeSdpForLowLatency(
      offer.sdp ?? '',
      isVideo: callType == CallType.video,
    );
    final optimizedOffer = RTCSessionDescription(optimizedSdp, offer.type);
    await _peerConnection!.setLocalDescription(optimizedOffer);

    final callPayload = initialCall.toFirestore();
    callPayload['offer'] = {
      'type': optimizedOffer.type,
      'sdp': optimizedOffer.sdp,
    };

    await callDoc.set(callPayload).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        throw Exception('Network timeout. Please check your internet connection.');
      },
    );

    // Flush queued candidates safely now that callDoc exists
    isCallDocCreated = true;
    for (final cand in queuedCandidates) {
      callerCandidatesCol.add(cand);
    }
    queuedCandidates.clear();

    // Send push notification with high priority call channel
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

    // Audio routing
    if (callType == CallType.video) {
      await setSpeakerphone(true);
    } else {
      await setSpeakerphone(false);
    }

    _isMicMuted = false;
    _isCameraOff = false;
    _isFrontCamera = true;

    return initialCall;
  }

  /// Answer an incoming call with HD video and clear studio audio DSP
  Future<void> answerCall(CallModel call) async {
    final isOnline = await hasInternetConnection();
    if (!isOnline) {
      throw Exception('No internet connection. Please check your network and try again.');
    }

    final hasPermissions = await requestPermissions(call.callType);
    if (!hasPermissions) {
      await rejectCall(call);
      throw Exception('Camera or Microphone permissions not granted.');
    }

    await initRenderers();
    _pendingIceCandidates.clear();
    _isRemoteDescriptionSet = false;
    currentCall = call;
    _isCallActive = true;
    callStatusNotifier.value = CallStatus.connected;

    final callDoc = _firestore.collection('calls').doc(call.callId);

    // 1. Get user media with 48kHz Studio Audio & Real HD Camera DSP
    final mediaConstraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'sampleRate': 48000,
        'channelCount': 1,
        'googEchoCancellation': true,
        'googEchoCancellation2': true,
        'googDAEchoCancellation': true,
        'googAutoGainControl': true,
        'googAutoGainControl2': true,
        'googNoiseSuppression': true,
        'googNoiseSuppression2': true,
        'googHighpassFilter': true,
        'googTypingNoiseDetection': true,
        'googAudioMirroring': false,
        'latency': 0,
      },
      'video': call.callType == CallType.video
          ? {
              'mandatory': {
                'minWidth': '1280',
                'minHeight': '720',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [
                {'minWidth': '1280'},
                {'minHeight': '720'},
                {'minFrameRate': '30'},
                {'googCpuOveruseDetection': true},
                {'googCpuUnderuseThreshold': 55},
                {'googCpuOveruseThreshold': 85},
              ],
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    for (final track in _localStream!.getTracks()) {
      track.enabled = true;
    }
    localRenderer.srcObject = _localStream;
    localStreamNotifier.value = _localStream;

    // 2. Create peer connection
    _peerConnection = await createPeerConnection(_iceServers);
    _setupConnectionStateListeners();

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
        remoteStreamNotifier.value = _remoteStream;
        setSpeakerphone(call.callType == CallType.video);
      }
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // 3. ICE candidate handling for receiver
    final receiverCandidatesCol = callDoc.collection('receiverCandidates');
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        receiverCandidatesCol.add(candidate.toMap());
      }
    };

    // 4. Retrieve fresh offer and set remote description
    Map<String, dynamic>? offerMap = call.offer;
    if (offerMap == null || offerMap['sdp'] == null) {
      final freshSnapshot = await callDoc.get();
      offerMap = freshSnapshot.data()?['offer'] as Map<String, dynamic>?;
    }

    if (offerMap != null && offerMap['sdp'] != null) {
      final sdp = offerMap['sdp'] as String;
      final type = (offerMap['type'] as String?) ?? 'offer';
      final optimizedRemoteSdp = _optimizeSdpForLowLatency(
        sdp,
        isVideo: call.callType == CallType.video,
      );
      final rtcSessionDesc = RTCSessionDescription(optimizedRemoteSdp, type);
      await _peerConnection!.setRemoteDescription(rtcSessionDesc);
      _isRemoteDescriptionSet = true;
      _drainPendingCandidates();
    } else {
      throw Exception('Call offer is missing or invalid.');
    }

    // 5. Create WebRTC Answer with Low-Latency SDP
    final answer = await _peerConnection!.createAnswer();
    final optimizedAnswerSdp = _optimizeSdpForLowLatency(
      answer.sdp ?? '',
      isVideo: call.callType == CallType.video,
    );
    final optimizedAnswer = RTCSessionDescription(optimizedAnswerSdp, answer.type);
    await _peerConnection!.setLocalDescription(optimizedAnswer);

    // Boost video bitrate
    if (call.callType == CallType.video) {
      _boostVideoSenderBitrate();
    }

    // Update call doc in Firestore to connected
    await callDoc.update({
      'status': 'connected',
      'startedAt': FieldValue.serverTimestamp(),
      'answer': {
        'type': optimizedAnswer.type,
        'sdp': optimizedAnswer.sdp,
      },
    }).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        throw Exception('Network timeout. Unable to establish connection.');
      },
    );

    // 6. Listen for caller's ICE candidates with queue protection
    final callerCandidatesCol = callDoc.collection('callerCandidates');
    _candidatesSub?.cancel();
    _candidatesSub = callerCandidatesCol.snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            final candidate = RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            );
            _addOrQueueCandidate(candidate);
          }
        }
      }
    });

    if (call.callType == CallType.video) {
      await setSpeakerphone(true);
    } else {
      await setSpeakerphone(false);
    }

    _isMicMuted = false;
    _isCameraOff = false;
    _isFrontCamera = true;
  }

  /// Listen for remote answer (used by caller) with safe ICE candidate queuing
  void listenForAnswerAndCandidates(String callId) {
    final callDoc = _firestore.collection('calls').doc(callId);

    _callDocSub?.cancel();
    _callDocSub = callDoc.snapshots().listen((snapshot) async {
      if (!snapshot.exists || snapshot.data() == null) return;
      final data = snapshot.data()!;
      final status = data['status'] as String?;

      if (status == 'connected' && _peerConnection != null && !_isRemoteDescriptionSet) {
        final answerMap = data['answer'] as Map<String, dynamic>?;
        if (answerMap != null) {
          final sdp = answerMap['sdp'] as String?;
          final type = answerMap['type'] as String?;
          if (sdp != null && type != null) {
            final optimizedRemoteSdp = _optimizeSdpForLowLatency(
              sdp,
              isVideo: currentCall?.callType == CallType.video,
            );
            final desc = RTCSessionDescription(optimizedRemoteSdp, type);
            await _peerConnection!.setRemoteDescription(desc);
            _isRemoteDescriptionSet = true;
            _drainPendingCandidates();
            callStatusNotifier.value = CallStatus.connected;

            // Boost video bitrate once connected
            if (currentCall?.callType == CallType.video) {
              _boostVideoSenderBitrate();
            }
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
            final candidate = RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            );
            _addOrQueueCandidate(candidate);
          }
        }
      }
    });
  }

  void _addOrQueueCandidate(RTCIceCandidate candidate) {
    if (_isRemoteDescriptionSet && _peerConnection != null) {
      _peerConnection?.addCandidate(candidate).catchError((e) {
        debugPrint('Error adding ICE candidate: $e');
      });
    } else {
      _pendingIceCandidates.add(candidate);
    }
  }

  void _drainPendingCandidates() {
    if (_peerConnection == null || !_isRemoteDescriptionSet) return;
    for (final candidate in _pendingIceCandidates) {
      _peerConnection?.addCandidate(candidate).catchError((e) {
        debugPrint('Error draining ICE candidate: $e');
      });
    }
    _pendingIceCandidates.clear();
  }

  /// Toggle Microphone Mute
  bool toggleMicrophone() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      _isMicMuted = !_isMicMuted;

      // 1. Mute/Unmute tracks on local stream
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMicMuted;
      }

      // 2. Mute/Unmute tracks on PeerConnection senders & local streams
      if (_peerConnection != null) {
        try {
          final streams = _peerConnection!.getLocalStreams();
          for (final stream in streams) {
            if (stream != null) {
              for (final track in stream.getAudioTracks()) {
                track.enabled = !_isMicMuted;
              }
            }
          }

          _peerConnection!.getSenders().then((senders) {
            for (final sender in senders) {
              if (sender.track?.kind == 'audio') {
                sender.track?.enabled = !_isMicMuted;
              }
            }
          }).catchError((_) {});
        } catch (_) {}
      }
      return true;
    } else {
      debugPrint('Mute skipped: stream not ready yet');
      return false;
    }
  }

  /// Toggle Camera On / Off
  bool toggleCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      _isCameraOff = !_isCameraOff;

      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = !_isCameraOff;
      }

      if (_peerConnection != null) {
        try {
          final streams = _peerConnection!.getLocalStreams();
          for (final stream in streams) {
            if (stream != null) {
              for (final track in stream.getVideoTracks()) {
                track.enabled = !_isCameraOff;
              }
            }
          }

          _peerConnection!.getSenders().then((senders) {
            for (final sender in senders) {
              if (sender.track?.kind == 'video') {
                sender.track?.enabled = !_isCameraOff;
              }
            }
          }).catchError((_) {});
        } catch (_) {}
      }
      return true;
    } else {
      debugPrint('Camera toggle skipped: stream not ready yet');
      return false;
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
    await setSpeakerphone(_isSpeakerOn);
  }

  /// Set Speakerphone explicitly
  Future<void> setSpeakerphone(bool enable) async {
    _isSpeakerOn = enable;
    try {
      await Helper.setSpeakerphoneOn(enable);
    } catch (_) {}
    try {
      // Only route REMOTE incoming stream to speakerphone.
      // NEVER route _localStream to speakerphone as it plays back your own mic and causes echo!
      _remoteStream?.getAudioTracks().forEach((track) {
        track.enableSpeakerphone(enable);
      });
    } catch (_) {}
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
      _cleanCallCandidates(call.callId);
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

      _cleanCallCandidates(call.callId);
    } catch (e) {
      debugPrint('Error ending call: $e');
    } finally {
      await cleanup();
    }
  }

  void _cleanCallCandidates(String callId) {
    try {
      final callRef = _firestore.collection('calls').doc(callId);
      callRef.collection('callerCandidates').get().then((snap) {
        for (final doc in snap.docs) {
          doc.reference.delete().catchError((_) {});
        }
      }).catchError((_) {});
      callRef.collection('receiverCandidates').get().then((snap) {
        for (final doc in snap.docs) {
          doc.reference.delete().catchError((_) {});
        }
      }).catchError((_) {});
    } catch (_) {}
  }

  Future<void> _writeCallHistoryMessage({
    required CallModel call,
    required String finalStatus,
    required int durationSeconds,
  }) async {
    try {
      final chatId = _getChatId(call.callerHandle, call.receiverHandle);
      final chatRef = _firestore.collection('chats').doc(chatId);
      final messageRef = chatRef.collection('messages').doc('call_${call.callId}');

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
        final existingSnap = await transaction.get(messageRef);
        if (existingSnap.exists) {
          final existingStatus = existingSnap.data()?['callStatus'] as String?;
          // Don't overwrite an established 'ended' or 'declined' status with a late 'missed' status
          if ((existingStatus == 'declined' || existingStatus == 'ended') &&
              finalStatus == 'missed') {
            return;
          }
        }

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
        }, SetOptions(merge: true));

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
    // a. Set isCallActive flag to false FIRST
    _isCallActive = false;

    _callDocSub?.cancel();
    _callDocSub = null;
    _candidatesSub?.cancel();
    _candidatesSub = null;
    _pendingIceCandidates.clear();
    _isRemoteDescriptionSet = false;

    try {
      // b. Stop all tracks on local & remote streams
      _localStream?.getTracks().forEach((track) {
        try {
          track.stop();
        } catch (_) {}
      });

      _remoteStream?.getTracks().forEach((track) {
        try {
          track.stop();
        } catch (_) {}
      });

      // c. Detach renderers & dispose peer connection
      if (_renderersInitialized) {
        try {
          localRenderer.srcObject = null;
        } catch (_) {}
        try {
          remoteRenderer.srcObject = null;
        } catch (_) {}
      }

      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;

      // d. Dispose streams and set localStream = null LAST
      await _localStream?.dispose();
      await _remoteStream?.dispose();

      _localStream = null;
      localStreamNotifier.value = null;
      _remoteStream = null;
      remoteStreamNotifier.value = null;
    } catch (e) {
      debugPrint('WebRTC cleanup error: $e');
    } finally {
      currentCall = null;
      isReconnectingNotifier.value = false;
      _isMicMuted = false;
      _isCameraOff = false;
      _isSpeakerOn = false;
      _isFrontCamera = true;
      _renderersInitialized = false;
    }
  }

  void _setupConnectionStateListeners() {
    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('[WebRTC] ICE Connection State: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        isReconnectingNotifier.value = true;
        try {
          _peerConnection?.restartIce();
        } catch (e) {
          debugPrint('[WebRTC] restartIce error: $e');
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        isReconnectingNotifier.value = false;
      }
    };

    _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[WebRTC] Peer Connection State: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        isReconnectingNotifier.value = true;
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        isReconnectingNotifier.value = false;
      }
    };
  }
}

