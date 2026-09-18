import 'package:cloud_firestore/cloud_firestore.dart';

class Friendship {
  final String id;
  final List<String> users;
  final DateTime createdAt;

  Friendship({
    required this.id,
    required this.users,
    required this.createdAt,
  });

  factory Friendship.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseDateTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
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
      createdAt: parseDateTime(map['createdAt']),
    );
  }

  /// Get the other user's handle given the current user's handle
  String getOtherUser(String currentHandle) {
    final cleanCurrent = currentHandle.replaceAll('@', '').trim();
    return users.firstWhere(
      (h) => h.replaceAll('@', '').trim() != cleanCurrent,
      orElse: () => '',
    );
  }
}
