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
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
