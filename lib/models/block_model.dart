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
    DateTime parseDateTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now();
    }

    return BlockEntry(
      id: id,
      blockerHandle: (map['blockerHandle'] as String?)?.replaceAll('@', '').trim() ?? '',
      blockedHandle: (map['blockedHandle'] as String?)?.replaceAll('@', '').trim() ?? '',
      createdAt: parseDateTime(map['createdAt']),
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
