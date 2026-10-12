enum FriendRequestStatus { pending, accepted, rejected }

class FriendRequest {
  final String id;
  final String senderHandle;
  final String? senderName;
  final String receiverHandle;
  final String? receiverName;
  final FriendRequestStatus status;
  final String? senderAvatarUrl;
  final String? receiverAvatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  FriendRequest({
    required this.id,
    required this.senderHandle,
    this.senderName,
    required this.receiverHandle,
    this.receiverName,
    required this.status,
    this.senderAvatarUrl,
    this.receiverAvatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FriendRequest.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseDateTime(dynamic val) {
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val is int) {
        if (val > 10000000000) {
          return DateTime.fromMillisecondsSinceEpoch(val);
        } else {
          return DateTime.fromMillisecondsSinceEpoch(val * 1000);
        }
      }
      if (val != null) {
        try {
          return (val as dynamic).toDate();
        } catch (_) {}
      }
      return DateTime.now();
    }

    final rawSenderName = (map['senderName'] ?? map['senderDisplayName'] ?? map['name'] ?? map['displayName']) as String?;
    final rawReceiverName = (map['receiverName'] ?? map['receiverDisplayName'] ?? map['displayName']) as String?;

    return FriendRequest(
      id: id,
      senderHandle: (map['senderHandle'] as String?)?.replaceAll('@', '').trim() ?? '',
      senderName: (rawSenderName != null && rawSenderName.trim().isNotEmpty) ? rawSenderName.trim() : null,
      receiverHandle: (map['receiverHandle'] as String?)?.replaceAll('@', '').trim() ?? '',
      receiverName: (rawReceiverName != null && rawReceiverName.trim().isNotEmpty) ? rawReceiverName.trim() : null,
      status: FriendRequestStatus.values.firstWhere(
        (e) => e.name == (map['status'] ?? 'pending'),
        orElse: () => FriendRequestStatus.pending,
      ),
      senderAvatarUrl: (map['senderAvatarUrl'] ?? map['senderAvatar'] ?? map['avatarUrl']) as String?,
      receiverAvatarUrl: (map['receiverAvatarUrl'] ?? map['receiverAvatar'] ?? map['avatarUrl']) as String?,
      createdAt: parseDateTime(map['createdAt']),
      updatedAt: parseDateTime(map['updatedAt']),
    );
  }

  String get displaySenderName => (senderName != null && senderName!.trim().isNotEmpty) ? senderName!.trim() : senderHandle;

  Map<String, dynamic> toMap() {
    return {
      'senderHandle': senderHandle,
      'senderName': senderName,
      'receiverHandle': receiverHandle,
      'receiverName': receiverName,
      'status': status.name,
      'senderAvatarUrl': senderAvatarUrl,
      'receiverAvatarUrl': receiverAvatarUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
