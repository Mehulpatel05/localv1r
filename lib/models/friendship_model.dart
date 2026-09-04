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
    return Friendship(
      id: id,
      users: List<String>.from(map['users'] ?? []),
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /// Get the other user's handle given the current user's handle
  String getOtherUser(String currentHandle) {
    return users.firstWhere((h) => h != currentHandle, orElse: () => '');
  }
}
