class ChatConversation {
  final String id;
  final List<String> participants;
  final List<String> participantsUids;
  final String lastMessage;
  final String lastSenderHandle;
  final DateTime? updatedAt;
  final Map<String, int> unreadCounts;
  final Map<String, bool> typing;
  final String? partnerAvatarUrl;

  const ChatConversation({
    required this.id,
    required this.participants,
    this.participantsUids = const [],
    this.lastMessage = '',
    this.lastSenderHandle = '',
    this.updatedAt,
    this.unreadCounts = const {},
    this.typing = const {},
    this.partnerAvatarUrl,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    DateTime? updated;
    final rawTime = json['updatedAt'] ?? json['lastMessageAt'] ?? json['created_at'];
    if (rawTime is int) {
      updated = rawTime > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(rawTime)
          : DateTime.fromMillisecondsSinceEpoch(rawTime * 1000);
    } else if (rawTime is String) {
      updated = DateTime.tryParse(rawTime);
    }

    final rawParticipants = json['participants'] as List<dynamic>? ?? [];
    List<String> participants = rawParticipants.map((e) => e.toString()).toList();

    // If partnerHandle is directly supplied
    if (participants.isEmpty && json['partnerHandle'] != null) {
      participants = [json['partnerHandle'].toString()];
    }

    final rawUids = json['participantsUids'] as List<dynamic>? ?? [];
    final participantsUids = rawUids.map((e) => e.toString()).toList();

    final unreadCount = (json['unreadCount'] as num?)?.toInt() ?? 0;
    final rawUnread = json['unreadCounts'] as Map<String, dynamic>? ?? {};
    final unreadCounts = rawUnread.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));

    final rawTyping = json['typing'] as Map<String, dynamic>? ?? {};
    final typing = rawTyping.map((k, v) => MapEntry(k, v == true));

    return ChatConversation(
      id: (json['id'] ?? '').toString(),
      participants: participants,
      participantsUids: participantsUids,
      lastMessage: (json['lastMessage'] ?? '').toString(),
      lastSenderHandle: (json['lastSenderHandle'] ?? '').toString(),
      updatedAt: updated,
      unreadCounts: unreadCounts.isNotEmpty ? unreadCounts : {'unread': unreadCount},
      typing: typing,
      partnerAvatarUrl: json['partnerAvatarUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participants': participants,
      'participantsUids': participantsUids,
      'lastMessage': lastMessage,
      'lastSenderHandle': lastSenderHandle,
      'updatedAt': updatedAt?.toIso8601String(),
      'unreadCounts': unreadCounts,
      'typing': typing,
      'partnerAvatarUrl': partnerAvatarUrl,
    };
  }

  bool isPartnerTyping(String currentUserHandle) {
    final partner = getPartnerHandle(currentUserHandle).replaceAll('@', '').trim();
    return typing[partner] == true || typing[partner.toLowerCase()] == true;
  }

  String getPartnerHandle(String currentUserHandle) {
    final cleanCurrent = currentUserHandle.replaceAll('@', '').trim().toLowerCase();
    return participants.firstWhere(
      (p) => p.replaceAll('@', '').trim().toLowerCase() != cleanCurrent,
      orElse: () => participants.isNotEmpty ? participants.first : 'Neighbor',
    );
  }

  int getUnreadCount(String currentUserHandle) {
    final cleanCurrent = currentUserHandle.replaceAll('@', '').trim();
    return unreadCounts[currentUserHandle] ??
        unreadCounts[cleanCurrent] ??
        unreadCounts['@$cleanCurrent'] ??
        unreadCounts['unread'] ??
        0;
  }
}
