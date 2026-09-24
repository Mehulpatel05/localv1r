enum FriendRequestStatus { pending, accepted, rejected }

class FriendRequest {
  final String id;
  final String senderHandle;
  final String receiverHandle;
  final FriendRequestStatus status;
  final String? senderAvatarUrl;
  final String? receiverAvatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  FriendRequest({
    required this.id,
    required this.senderHandle,
    required this.receiverHandle,
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

    return FriendRequest(
      id: id,
      senderHandle: (map['senderHandle'] as String?)?.replaceAll('@', '').trim() ?? '',
      receiverHandle: (map['receiverHandle'] as String?)?.replaceAll('@', '').trim() ?? '',
      status: FriendRequestStatus.values.firstWhere(
        (e) => e.name == (map['status'] ?? 'pending'),
        orElse: () => FriendRequestStatus.pending,
      ),
      senderAvatarUrl: (map['senderAvatarUrl'] ?? map['senderAvatar']) as String?,
      receiverAvatarUrl: (map['receiverAvatarUrl'] ?? map['receiverAvatar']) as String?,
      createdAt: parseDateTime(map['createdAt']),
      updatedAt: parseDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderHandle': senderHandle,
      'receiverHandle': receiverHandle,
      'status': status.name,
      'senderAvatarUrl': senderAvatarUrl,
      'receiverAvatarUrl': receiverAvatarUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
