import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import '../models/call_model.dart';
import '../screens/chat/incoming_call_screen.dart';
import 'auth_service.dart';
import 'notification_service.dart';

class WebRtcCallService {
  static final WebRtcCallService instance = WebRtcCallService._internal();
  factory WebRtcCallService() => instance;
  WebRtcCallService._internal();

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
  Timer? _pollingTimer;

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

  WebSocket? _signalingWs;
  Timer? _iceCheckingTimeoutTimer;

  // ⚡ Section 4.2: STUN + TURN Relay Servers configuration
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun.cloudflare.com:3478'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turns:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'iceCandidatePoolSize': 10,
    'continualGatheringPolicy': 'gather_continually',
  };

  // ⚡ Section 4.1: Realtime WebSocket Signaling Relay (Durable Object Channel)
  Future<void> _connectSignalingWs(String callId, String myHandle) async {
    try {
      _signalingWs?.close();
      final base = AuthService.baseUrl;
      final wsBase = base.startsWith('https://')
          ? base.replaceFirst('https://', 'wss://')
          : base.replaceFirst('http://', 'ws://');
      final uri = Uri.parse('$wsBase/calls/$callId/ws');

      _signalingWs = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 4));
      _signalingWs?.listen((data) {
        _handleIncomingWsMessage(data.toString());
      }, onError: (err) {
        debugPrint('[WebRTC WS] Signaling error: $err');
      }, onDone: () {
        debugPrint('[WebRTC WS] Signaling closed');
      });
    } catch (e) {
      debugPrint('[WebRTC WS] Connect error (falling back to REST polling): $e');
    }
  }

  void _sendWsMessage(Map<String, dynamic> payload) {
    if (_signalingWs != null && _signalingWs!.readyState == WebSocket.open) {
      try {
        _signalingWs!.add(jsonEncode(payload));
      } catch (e) {
        debugPrint('[WebRTC WS] Send error: $e');
      }
    }
  }

  void _handleIncomingWsMessage(String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final type = msg['type']?.toString();

      if (type == 'answer' && !_isRemoteDescriptionSet && msg['sdp'] != null) {
        final sdp = msg['sdp'] as String;
        final desc = RTCSessionDescription(sdp, 'answer');
        _peerConnection?.setRemoteDescription(desc).then((_) {
          _isRemoteDescriptionSet = true;
          _drainPendingCandidates();
          callStatusNotifier.value = CallStatus.connected;
          if (currentCall?.callType == CallType.video) {
            _boostVideoSenderBitrate();
          }
        });
      } else if (type == 'candidate' && msg['candidate'] != null) {
        final c = msg['candidate'] as Map<String, dynamic>;
        final candidate = RTCIceCandidate(
          c['candidate'],
          c['sdpMid'],
          (c['sdpMLineIndex'] as num?)?.toInt() ?? 0,
        );
        _addOrQueueCandidate(candidate);
      } else if (type == 'status') {
        final statusStr = (msg['status'] ?? '').toString().toLowerCase();
        if (statusStr == 'ended' || statusStr == 'rejected' || statusStr == 'busy' || statusStr == 'missed') {
          callStatusNotifier.value = CallStatus.ended;
          cleanup();
        } else if (statusStr == 'ringing') {
          callStatusNotifier.value = CallStatus.ringing;
        } else if (statusStr == 'accepted' || statusStr == 'connected') {
          callStatusNotifier.value = CallStatus.connected;
        }
      }
    } catch (e) {
      debugPrint('[WebRTC WS] Parse message error: $e');
    }
  }

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
    final permissions = <Permission>[
      Permission.microphone,
      if (callType == CallType.video) Permission.camera,
    ];

    final statuses = await permissions.request();
    for (final p in permissions) {
      final status = statuses[p];
      if (status == PermissionStatus.permanentlyDenied || status == PermissionStatus.denied) {
        return false;
      }
    }
    return true;
  }

  /// Safe getUserMedia capture with fallback to basic constraints on device camera mismatch
  Future<MediaStream> _getUserMediaWithFallback(bool isVideo) async {
    final Map<String, dynamic> preferredConstraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': isVideo
          ? {
              'facingMode': 'user',
              'optional': [],
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '24',
              },
            }
          : false,
    };

    try {
      return await navigator.mediaDevices.getUserMedia(preferredConstraints);
    } catch (e) {
      debugPrint('Preferred media constraints failed ($e). Falling back to basic constraints...');
      final Map<String, dynamic> fallbackConstraints = {
        'audio': true,
        'video': isVideo ? {'facingMode': 'user'} : false,
      };
      return await navigator.mediaDevices.getUserMedia(fallbackConstraints);
    }
  }

  /// Optimizes SDP for ultra-low latency audio
  String _optimizeSdpForLowLatency(String sdp, {required bool isVideo}) {
    final lines = sdp.split('\r\n');
    final modifiedLines = <String>[];
    String? opusPayloadType;

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

      if (opusPayloadType != null && line.startsWith('a=fmtp:$opusPayloadType')) {
        opusFmtpFound = true;
        modifiedLines.add(
          'a=fmtp:$opusPayloadType minptime=10;ptime=20;useinbandfec=1;maxaveragebitrate=32000;stereo=0;sprop-stereo=0;usedtx=1;cbr=0',
        );
        continue;
      }

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

      modifiedLines.add(line);
    }

    return modifiedLines.join('\r\n');
  }

  /// Boost video encoder bitrate
  Future<void> _boostVideoSenderBitrate() async {
    try {
      final senders = await _peerConnection?.getSenders();
      if (senders != null) {
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            try {
              final params = sender.parameters;
              if (params.encodings != null && params.encodings!.isNotEmpty) {
                for (final encoding in params.encodings!) {
                  encoding.maxBitrate = 1500000;
                  encoding.minBitrate = 300000;
                  encoding.maxFramerate = 30;
                }
                await sender.setParameters(params);
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Bitrate boost parameter error: $e');
    }
  }

  /// Start an outgoing call (Audio or Video) via D1 REST API
  Future<CallModel> makeCall({
    required String callerHandle,
    required String receiverHandle,
    required CallType callType,
    String? existingCallId,
  }) async {
    final cleanCaller = callerHandle.replaceAll('@', '').trim();
    final cleanReceiver = receiverHandle.replaceAll('@', '').trim();

    final permissionsFuture = requestPermissions(callType);
    final renderersFuture = initRenderers();

    final results = await Future.wait([permissionsFuture, renderersFuture]);
    final hasPermissions = results[0] as bool;

    if (!hasPermissions) {
      throw Exception('Camera or Microphone permissions not granted.');
    }

    _pendingIceCandidates.clear();
    _isRemoteDescriptionSet = false;

    // 1. Get user media with robust fallback
    _localStream = await _getUserMediaWithFallback(callType == CallType.video);
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
        setSpeakerphone(callType == CallType.video);
      }
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // 3. Create WebRTC Offer
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

    // 4. Send call offer to D1 REST API
    final payload = {
      'caller': cleanCaller,
      'receiver': cleanReceiver,
      'callType': callType.name,
      'sdpOffer': optimizedSdp,
    };

    final res = await http.post(
      Uri.parse('${AuthService.baseUrl}/calls/initiate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 8));

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to initiate call. Server returned ${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    final callId = data['callId'] as String;

    final initialCall = CallModel(
      callId: callId,
      callerHandle: cleanCaller,
      receiverHandle: cleanReceiver,
      callType: callType,
      status: CallStatus.calling,
      createdAt: DateTime.now(),
    );

    currentCall = initialCall;
    _isCallActive = true;
    callStatusNotifier.value = CallStatus.calling;

    // Connect to WebSocket signaling relay (instant trickle-ICE)
    _connectSignalingWs(callId, cleanCaller);

    // 5. Setup ICE candidate callback to send over WebSocket (instant trickle-ICE) + D1 fallback
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        _sendWsMessage({
          'type': 'candidate',
          'handle': cleanCaller,
          'candidate': candidate.toMap(),
        });
        http.post(
          Uri.parse('${AuthService.baseUrl}/calls/$callId/ice'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'handle': cleanCaller,
            'candidate': candidate.toMap(),
          }),
        ).catchError((_) => http.Response('', 500));
      }
    };

    // Send push notification
    NotificationService().sendNotification(
      targetHandle: cleanReceiver,
      title: '@$cleanCaller is calling...',
      body: callType == CallType.video ? 'Incoming Video Call 📹' : 'Incoming Voice Call 📞',
      data: {
        'type': 'call',
        'callId': callId,
        'callType': callType.name,
        'callerHandle': cleanCaller,
      },
    );

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

  /// Answer an incoming call via D1 REST API
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

    // 1. Get user media with robust fallback
    _localStream = await _getUserMediaWithFallback(call.callType == CallType.video);
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

    // Connect to WebSocket signaling relay
    _connectSignalingWs(call.callId, call.receiverHandle);

    // 3. ICE candidate sending for receiver via WebSocket (instant trickle-ICE) + D1 fallback
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        _sendWsMessage({
          'type': 'candidate',
          'handle': call.receiverHandle,
          'candidate': candidate.toMap(),
        });
        http.post(
          Uri.parse('${AuthService.baseUrl}/calls/${call.callId}/ice'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'handle': call.receiverHandle,
            'candidate': candidate.toMap(),
          }),
        ).catchError((_) => http.Response('', 500));
      }
    };

    // 4. Retrieve call details for offer
    String? sdpOffer = call.offer?['sdp'];
    if (sdpOffer == null) {
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/calls/${call.callId}'),
        headers: {'Content-Type': 'application/json'},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        sdpOffer = body['call']?['sdpOffer'] ?? body['call']?['sdp_offer'];
      }
    }

    if (sdpOffer != null) {
      final optimizedRemoteSdp = _optimizeSdpForLowLatency(
        sdpOffer,
        isVideo: call.callType == CallType.video,
      );
      final rtcSessionDesc = RTCSessionDescription(optimizedRemoteSdp, 'offer');
      await _peerConnection!.setRemoteDescription(rtcSessionDesc);
      _isRemoteDescriptionSet = true;
      _drainPendingCandidates();
    } else {
      throw Exception('Call offer is missing or invalid.');
    }

    // 5. Create WebRTC Answer
    final answer = await _peerConnection!.createAnswer();
    final optimizedAnswerSdp = _optimizeSdpForLowLatency(
      answer.sdp ?? '',
      isVideo: call.callType == CallType.video,
    );
    final optimizedAnswer = RTCSessionDescription(optimizedAnswerSdp, answer.type);
    await _peerConnection!.setLocalDescription(optimizedAnswer);

    if (call.callType == CallType.video) {
      _boostVideoSenderBitrate();
    }

    // Send answer via WebSocket (instant) + D1 fallback
    _sendWsMessage({
      'type': 'answer',
      'receiver': call.receiverHandle,
      'sdp': optimizedAnswerSdp,
    });

    await http.post(
      Uri.parse('${AuthService.baseUrl}/calls/${call.callId}/answer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'receiver': call.receiverHandle,
        'sdpAnswer': optimizedAnswerSdp,
      }),
    ).timeout(const Duration(seconds: 8));

    // 6. Start polling fallback for caller's ICE candidates and status
    _startIcePolling(call.callId, isCaller: false);

    if (call.callType == CallType.video) {
      await setSpeakerphone(true);
    } else {
      await setSpeakerphone(false);
    }

    _isMicMuted = false;
    _isCameraOff = false;
    _isFrontCamera = true;
  }

  /// Listen for remote answer & candidates via polling
  void listenForAnswerAndCandidates(String callId) {
    _startIcePolling(callId, isCaller: true);
  }

  final Set<String> _receivedIceHashes = {};

  void _startIcePolling(String callId, {required bool isCaller}) {
    _pollingTimer?.cancel();
    _receivedIceHashes.clear();

    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/calls/$callId'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 2));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final callData = body['call'] as Map<String, dynamic>?;
          if (callData == null) return;

          final status = (callData['status'] ?? '').toString();
          if (status == 'ended' || status == 'rejected' || status == 'busy' || status == 'missed') {
            callStatusNotifier.value = CallStatus.ended;
            cleanup();
            return;
          }

          // If caller, check for sdpAnswer
          if (isCaller && !_isRemoteDescriptionSet && (callData['sdpAnswer'] != null || callData['sdp_answer'] != null)) {
            final sdp = (callData['sdpAnswer'] ?? callData['sdp_answer']) as String;
            final desc = RTCSessionDescription(sdp, 'answer');
            await _peerConnection!.setRemoteDescription(desc);
            _isRemoteDescriptionSet = true;
            _drainPendingCandidates();
            callStatusNotifier.value = CallStatus.connected;
            if (currentCall?.callType == CallType.video) {
              _boostVideoSenderBitrate();
            }
          }

          // Process other party's ICE candidates
          final candidatesKey = isCaller ? 'receiverIceCandidates' : 'callerIceCandidates';
          final cands = (callData[candidatesKey] as List<dynamic>?) ?? [];
          for (final c in cands) {
            if (c is Map<String, dynamic>) {
              final candStr = c['candidate']?.toString() ?? '';
              if (candStr.isEmpty || _receivedIceHashes.contains(candStr)) continue;
              _receivedIceHashes.add(candStr);

              final candidate = RTCIceCandidate(
                c['candidate'],
                c['sdpMid'],
                (c['sdpMLineIndex'] as num?)?.toInt() ?? 0,
              );
              _addOrQueueCandidate(candidate);
            }
          }
        }
      } catch (_) {}
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

      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMicMuted;
      }
      return true;
    }
    return false;
  }

  /// Toggle Camera On / Off
  bool toggleCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      _isCameraOff = !_isCameraOff;

      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = !_isCameraOff;
      }
      return true;
    }
    return false;
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
      _remoteStream?.getAudioTracks().forEach((track) {
        track.enableSpeakerphone(enable);
      });
    } catch (_) {}
  }

  /// Reject an incoming call
  Future<void> rejectCall(CallModel call) async {
    IncomingCallScreen.dismissCall(call.callId);
    NotificationService.instance.cancelCallNotification(call.callId);

    _sendWsMessage({
      'type': 'status',
      'status': 'rejected',
      'endedBy': call.receiverHandle,
      'durationSeconds': 0,
    });
    try {
      await http.post(
        Uri.parse('${AuthService.baseUrl}/calls/${call.callId}/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': 'rejected',
          'endedBy': call.receiverHandle,
          'durationSeconds': 0,
        }),
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
    String? endedBy,
  }) async {
    IncomingCallScreen.dismissCall(call.callId);
    NotificationService.instance.cancelCallNotification(call.callId);

    final cleanEndedBy = (endedBy ?? call.callerHandle).replaceAll('@', '').trim();
    _sendWsMessage({
      'type': 'status',
      'status': endStatus.name,
      'endedBy': cleanEndedBy,
      'durationSeconds': durationSeconds,
    });

    // If caller ends before answer, notify receiver device to cancel incoming call screen
    final cleanReceiver = call.receiverHandle.replaceAll('@', '').trim();
    if (cleanReceiver.isNotEmpty && (endStatus == CallStatus.missed || endStatus == CallStatus.ended || durationSeconds == 0)) {
      NotificationService().sendNotification(
        targetHandle: cleanReceiver,
        title: 'Call Ended',
        body: 'Call ended',
        data: {
          'type': 'call_cancelled',
          'callId': call.callId,
        },
      ).catchError((_) {});
    }

    try {
      await http.post(
        Uri.parse('${AuthService.baseUrl}/calls/${call.callId}/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': endStatus.name,
          'endedBy': cleanEndedBy,
          'durationSeconds': durationSeconds,
        }),
      );
    } catch (e) {
      debugPrint('Error ending call: $e');
    } finally {
      await cleanup();
    }
  }

  /// Clean up all WebRTC streams, peer connection, and subscriptions
  Future<void> cleanup() async {
    _isCallActive = false;

    _iceCheckingTimeoutTimer?.cancel();
    _iceCheckingTimeoutTimer = null;
    try {
      _signalingWs?.close();
    } catch (_) {}
    _signalingWs = null;

    _pollingTimer?.cancel();
    _pollingTimer = null;
    _pendingIceCandidates.clear();
    _isRemoteDescriptionSet = false;

    try {
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
      _iceCheckingTimeoutTimer?.cancel();

      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        isReconnectingNotifier.value = true;
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
