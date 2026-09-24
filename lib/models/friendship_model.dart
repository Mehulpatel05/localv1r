class Friendship {
  final String id;
  final List<String> users;
  final String? otherUser;
  final String? avatarUrl;
  final int reputation;
  final DateTime createdAt;

  Friendship({
    required this.id,
    required this.users,
    this.otherUser,
    this.avatarUrl,
    this.reputation = 0,
    required this.createdAt,
  });

  factory Friendship.fromMap(Map<String, dynamic> map, String id) {
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

    final rawUsers = map['users'];
    List<String> usersList = [];
    if (rawUsers is List) {
      usersList = rawUsers.map((u) => u.toString().replaceAll('@', '').trim()).toList();
    }

    return Friendship(
      id: id,
      users: usersList,
      otherUser: (map['otherUser'] as String?)?.replaceAll('@', '').trim(),
      avatarUrl: map['avatarUrl'] as String?,
      reputation: (map['reputation'] as num?)?.toInt() ?? 0,
      createdAt: parseDateTime(map['createdAt']),
    );
  }

  /// Get the other user's handle given the current user's handle
  String getOtherUser(String currentHandle) {
    if (otherUser != null && otherUser!.isNotEmpty) {
      return otherUser!;
    }
    final cleanCurrent = currentHandle.replaceAll('@', '').trim();
    return users.firstWhere(
      (h) => h.replaceAll('@', '').trim() != cleanCurrent,
      orElse: () => '',
    );
  }
}
