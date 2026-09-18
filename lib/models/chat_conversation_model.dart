import 'package:cloud_firestore/cloud_firestore.dart';

class ChatConversation {
  final String id;
  final List<String> participants;
  final List<String> participantsUids;
  final String lastMessage;
  final String lastSenderHandle;
  final DateTime? updatedAt;
  final Map<String, int> unreadCounts;

  const ChatConversation({
    required this.id,
    required this.participants,
    this.participantsUids = const [],
    this.lastMessage = '',
    this.lastSenderHandle = '',
    this.updatedAt,
    this.unreadCounts = const {},
  });

  factory ChatConversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime? updated;
    final rawTime = data['updatedAt'];
    if (rawTime is Timestamp) {
      updated = rawTime.toDate();
    } else if (rawTime is String) {
      updated = DateTime.tryParse(rawTime);
    }

    final rawParticipants = data['participants'] as List<dynamic>? ?? [];
    final participants = rawParticipants.map((e) => e.toString()).toList();

    final rawUids = data['participantsUids'] as List<dynamic>? ?? [];
    final participantsUids = rawUids.map((e) => e.toString()).toList();

    final rawUnread = data['unreadCounts'] as Map<String, dynamic>? ?? {};
    final unreadCounts = rawUnread.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));

    return ChatConversation(
      id: doc.id,
      participants: participants,
      participantsUids: participantsUids,
      lastMessage: data['lastMessage'] as String? ?? '',
      lastSenderHandle: data['lastSenderHandle'] as String? ?? '',
      updatedAt: updated,
      unreadCounts: unreadCounts,
    );
  }

  String getPartnerHandle(String currentUserHandle) {
    final cleanCurrent = currentUserHandle.replaceAll('@', '').trim().toLowerCase();
    return participants.firstWhere(
      (p) => p.replaceAll('@', '').trim().toLowerCase() != cleanCurrent,
      orElse: () => 'Neighbor',
    );
  }

  int getUnreadCount(String currentUserHandle) {
    final cleanCurrent = currentUserHandle.replaceAll('@', '').trim();
    return unreadCounts[currentUserHandle] ??
        unreadCounts[cleanCurrent] ??
        unreadCounts['@$cleanCurrent'] ??
        0;
  }
}
