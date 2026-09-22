import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { audio, video }

enum CallStatus {
  calling,
  ringing,
  connected,
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

  const CallModel({
    required this.callId,
    required this.callerHandle,
    required this.callerUid,
    required this.receiverHandle,
    required this.receiverUid,
    required this.callType,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.offer,
    this.answer,
  });

  factory CallModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseTime(dynamic val, [DateTime? fallback]) {
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val) ?? (fallback ?? DateTime.now());
      return fallback ?? DateTime.now();
    }

    final typeStr = (data['callType'] ?? 'audio').toString().toLowerCase();
    final callType = typeStr == 'video' ? CallType.video : CallType.audio;

    final statusStr = (data['status'] ?? 'calling').toString().toLowerCase();
    CallStatus status;
    switch (statusStr) {
      case 'ringing':
        status = CallStatus.ringing;
        break;
      case 'connected':
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

    return CallModel(
      callId: doc.id,
      callerHandle: (data['callerHandle'] ?? '').toString().replaceAll('@', '').trim(),
      callerUid: (data['callerUid'] ?? '').toString(),
      receiverHandle: (data['receiverHandle'] ?? '').toString().replaceAll('@', '').trim(),
      receiverUid: (data['receiverUid'] ?? '').toString(),
      callType: callType,
      status: status,
      createdAt: parseTime(data['createdAt']),
      startedAt: data['startedAt'] != null ? parseTime(data['startedAt']) : null,
      endedAt: data['endedAt'] != null ? parseTime(data['endedAt']) : null,
      durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
      offer: data['offer'] as Map<String, dynamic>?,
      answer: data['answer'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'callerHandle': callerHandle.replaceAll('@', '').trim(),
      'callerUid': callerUid,
      'receiverHandle': receiverHandle.replaceAll('@', '').trim(),
      'receiverUid': receiverUid,
      'callType': callType == CallType.video ? 'video' : 'audio',
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt!),
      if (endedAt != null) 'endedAt': Timestamp.fromDate(endedAt!),
      'durationSeconds': durationSeconds,
      if (offer != null) 'offer': offer,
      if (answer != null) 'answer': answer,
    };
  }

  CallModel copyWith({
    CallStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationSeconds,
    Map<String, dynamic>? offer,
    Map<String, dynamic>? answer,
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
    );
  }
}
