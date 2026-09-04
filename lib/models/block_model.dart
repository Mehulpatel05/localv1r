import 'package:cloud_firestore/cloud_firestore.dart';

class BlockEntry {
  final String id;
  final String blockerHandle;
  final String blockedHandle;
  final DateTime createdAt;

  BlockEntry({
    required this.id,
    required this.blockerHandle,
    required this.blockedHandle,
    required this.createdAt,
  });

  factory BlockEntry.fromMap(Map<String, dynamic> map, String id) {
    return BlockEntry(
      id: id,
      blockerHandle: map['blockerHandle'] ?? '',
      blockedHandle: map['blockedHandle'] ?? '',
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'blockerHandle': blockerHandle,
      'blockedHandle': blockedHandle,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
