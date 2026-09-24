enum CallType { audio, video }

enum CallStatus {
  calling,
  ringing,
  connected,
  accepted,
  ended,
  rejected,
  missed,
  busy,
}

class CallModel {
  final String callId;
  final String callerHandle;
  final String callerUid;
  final String receiverHandle;
  final String receiverUid;
  final CallType callType;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final List<dynamic> callerIceCandidates;
  final List<dynamic> receiverIceCandidates;

  const CallModel({
    required this.callId,
    required this.callerHandle,
    this.callerUid = '',
    required this.receiverHandle,
    this.receiverUid = '',
    required this.callType,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.offer,
    this.answer,
    this.callerIceCandidates = const [],
    this.receiverIceCandidates = const [],
  });

  factory CallModel.fromJson(Map<String, dynamic> data) {
    DateTime parseTime(dynamic val, [DateTime? fallback]) {
      if (val is int) {
        return val > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(val)
            : DateTime.fromMillisecondsSinceEpoch(val * 1000);
      }
      if (val is String) return DateTime.tryParse(val) ?? (fallback ?? DateTime.now());
      return fallback ?? DateTime.now();
    }

    final typeStr = (data['callType'] ?? data['call_type'] ?? 'audio').toString().toLowerCase();
    final callType = typeStr == 'video' ? CallType.video : CallType.audio;

    final statusStr = (data['status'] ?? 'calling').toString().toLowerCase();
    CallStatus status;
    switch (statusStr) {
      case 'ringing':
        status = CallStatus.ringing;
        break;
      case 'connected':
      case 'accepted':
        status = CallStatus.connected;
        break;
      case 'ended':
        status = CallStatus.ended;
        break;
      case 'rejected':
        status = CallStatus.rejected;
        break;
      case 'missed':
        status = CallStatus.missed;
        break;
      case 'busy':
        status = CallStatus.busy;
        break;
      case 'calling':
      default:
        status = CallStatus.calling;
        break;
    }

    Map<String, dynamic>? offerMap;
    if (data['offer'] is Map) {
      offerMap = Map<String, dynamic>.from(data['offer'] as Map);
    } else if (data['sdpOffer'] is String) {
      offerMap = {'sdp': data['sdpOffer'], 'type': 'offer'};
    } else if (data['sdp_offer'] is String) {
      offerMap = {'sdp': data['sdp_offer'], 'type': 'offer'};
    }

    Map<String, dynamic>? answerMap;
    if (data['answer'] is Map) {
      answerMap = Map<String, dynamic>.from(data['answer'] as Map);
    } else if (data['sdpAnswer'] is String) {
      answerMap = {'sdp': data['sdpAnswer'], 'type': 'answer'};
    } else if (data['sdp_answer'] is String) {
      answerMap = {'sdp': data['sdp_answer'], 'type': 'answer'};
    }

    return CallModel(
      callId: (data['id'] ?? data['callId'] ?? '').toString(),
      callerHandle: (data['callerHandle'] ?? data['caller_handle'] ?? '').toString().replaceAll('@', '').trim(),
      callerUid: (data['callerUid'] ?? '').toString(),
      receiverHandle: (data['receiverHandle'] ?? data['receiver_handle'] ?? '').toString().replaceAll('@', '').trim(),
      receiverUid: (data['receiverUid'] ?? '').toString(),
      callType: callType,
      status: status,
      createdAt: parseTime(data['createdAt'] ?? data['created_at']),
      startedAt: data['startedAt'] != null ? parseTime(data['startedAt']) : null,
      endedAt: data['endedAt'] != null ? parseTime(data['endedAt']) : null,
      durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
      offer: offerMap,
      answer: answerMap,
      callerIceCandidates: (data['callerIceCandidates'] as List<dynamic>?) ?? [],
      receiverIceCandidates: (data['receiverIceCandidates'] as List<dynamic>?) ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': callId,
      'callerHandle': callerHandle.replaceAll('@', '').trim(),
      'callerUid': callerUid,
      'receiverHandle': receiverHandle.replaceAll('@', '').trim(),
      'receiverUid': receiverUid,
      'callType': callType == CallType.video ? 'video' : 'audio',
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
      'durationSeconds': durationSeconds,
      if (offer != null) 'offer': offer,
      if (answer != null) 'answer': answer,
      'callerIceCandidates': callerIceCandidates,
      'receiverIceCandidates': receiverIceCandidates,
    };
  }

  CallModel copyWith({
    CallStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationSeconds,
    Map<String, dynamic>? offer,
    Map<String, dynamic>? answer,
    List<dynamic>? callerIceCandidates,
    List<dynamic>? receiverIceCandidates,
  }) {
    return CallModel(
      callId: callId,
      callerHandle: callerHandle,
      callerUid: callerUid,
      receiverHandle: receiverHandle,
      receiverUid: receiverUid,
      callType: callType,
      status: status ?? this.status,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      offer: offer ?? this.offer,
      answer: answer ?? this.answer,
      callerIceCandidates: callerIceCandidates ?? this.callerIceCandidates,
      receiverIceCandidates: receiverIceCandidates ?? this.receiverIceCandidates,
    );
  }
}
