class ChatConversation {
  final String id;
  final List<String> participants;
  final List<String> participantsUids;
  final String lastMessage;
  final String lastSenderHandle;
  final DateTime? updatedAt;
  final Map<String, int> unreadCounts;
  final Map<String, bool> typing;
  final Map<String, int> typingTimestamps;
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
    this.typingTimestamps = const {},
    this.partnerAvatarUrl,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    DateTime? updated;
    final rawTime = json['updatedAt'] ?? json['lastMessageAt'] ?? json['last_message_at'] ?? json['created_at'];
    if (rawTime is int) {
      updated = rawTime > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(rawTime, isUtc: true).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(rawTime * 1000, isUtc: true).toLocal();
    } else if (rawTime is String) {
      final numVal = int.tryParse(rawTime);
      if (numVal != null) {
        updated = numVal > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(numVal, isUtc: true).toLocal()
            : DateTime.fromMillisecondsSinceEpoch(numVal * 1000, isUtc: true).toLocal();
      } else {
        final parsed = DateTime.tryParse(rawTime);
        updated = parsed != null ? (parsed.isUtc ? parsed.toLocal() : parsed) : null;
      }
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

    final rawTypingTs = json['typingTimestamps'] as Map<String, dynamic>? ?? {};
    final typingTimestamps = rawTypingTs.map((k, v) => MapEntry(k, (v as num).toInt()));

    return ChatConversation(
      id: (json['id'] ?? '').toString(),
      participants: participants,
      participantsUids: participantsUids,
      lastMessage: (json['lastMessage'] ?? '').toString(),
      lastSenderHandle: (json['lastSenderHandle'] ?? '').toString(),
      updatedAt: updated,
      unreadCounts: unreadCounts.isNotEmpty ? unreadCounts : {'unread': unreadCount},
      typing: typing,
      typingTimestamps: typingTimestamps,
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
      'typingTimestamps': typingTimestamps,
      'partnerAvatarUrl': partnerAvatarUrl,
    };
  }

  /// Returns true only if partner is currently typing AND typing status was updated within 5s
  bool isPartnerTyping(String currentUserHandle) {
    final partner = getPartnerHandle(currentUserHandle).replaceAll('@', '').trim();
    final isTyping = typing[partner] == true || typing[partner.toLowerCase()] == true;
    if (!isTyping) return false;

    // ⚡ Fix 8: 5-sec auto-timeout reset for typing indicator
    final ts = typingTimestamps[partner] ?? typingTimestamps[partner.toLowerCase()];
    if (ts != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - ts > 5000) {
        return false;
      }
    }
    return true;
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
