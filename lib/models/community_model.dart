class CommunityModel {
  final String id;
  final String name;
  final String description;
  final bool isChannel;
  final String adminHandle;
  final int memberCount;
  final DateTime createdAt;
  final String? imageUrl;

  CommunityModel({
    required this.id,
    required this.name,
    required this.description,
    required this.isChannel,
    required this.adminHandle,
    required this.memberCount,
    required this.createdAt,
    this.imageUrl,
  });

  factory CommunityModel.fromMap(Map<String, dynamic> map, String id) {
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

    return CommunityModel(
      id: id,
      name: (map['name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      isChannel: map['isChannel'] == true || map['is_channel'] == 1,
      adminHandle: (map['adminHandle'] ?? map['admin_handle'] ?? '').toString().replaceAll('@', '').trim(),
      memberCount: (map['memberCount'] ?? map['member_count'] as num?)?.toInt() ?? 1,
      createdAt: parseDateTime(map['createdAt'] ?? map['created_at']),
      imageUrl: (map['imageUrl'] ?? map['image_url']) as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'isChannel': isChannel,
      'adminHandle': adminHandle,
      'memberCount': memberCount,
      'createdAt': createdAt.toIso8601String(),
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }

  CommunityModel copyWith({
    String? name,
    String? description,
    String? imageUrl,
    int? memberCount,
  }) {
    return CommunityModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      isChannel: isChannel,
      adminHandle: adminHandle,
      memberCount: memberCount ?? this.memberCount,
      createdAt: createdAt,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

class CommunityMessage {
  final String id;
  final String communityId;
  final String authorHandle;
  final String content;
  final DateTime timestamp;
  final String? imageUrl;           // Single image message
  final List<String> mediaUrls;     // Multi-image album grouping
  final String type;                // "text", "image", "image_group"
  final Map<String, List<String>> reactions; // emoji reactions

  CommunityMessage({
    required this.id,
    required this.communityId,
    required this.authorHandle,
    required this.content,
    required this.timestamp,
    this.imageUrl,
    this.mediaUrls = const [],
    this.type = 'text',
    this.reactions = const {},
  });

  factory CommunityMessage.fromMap(Map<String, dynamic> map, String id) {
    // Safely parse reactions: { "emoji": ["handle1","handle2"] }
    final reactions = <String, List<String>>{};
    final rawReactions = map['reactions'];
    if (rawReactions is Map) {
      rawReactions.forEach((emoji, handles) {
        if (handles is List) {
          reactions[emoji.toString()] = handles
              .where((h) => h != null)
              .map((h) => h.toString())
              .toList();
        }
      });
    }

    // Safely parse mediaUrls
    final mediaUrls = <String>[];
    final rawMedia = map['mediaUrls'] ?? map['media_urls'];
    if (rawMedia is List) {
      for (final item in rawMedia) {
        if (item != null && item.toString().isNotEmpty) {
          mediaUrls.add(item.toString());
        }
      }
    } else if (map['imageUrl'] != null && map['imageUrl'].toString().isNotEmpty) {
      mediaUrls.add(map['imageUrl'].toString());
    }

    DateTime parsedTimestamp = DateTime.now();
    final rawTs = map['timestamp'] ?? map['createdAt'] ?? map['created_at'];
    if (rawTs is int) {
      if (rawTs > 10000000000) {
        parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(rawTs);
      } else {
        parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(rawTs * 1000);
      }
    } else if (rawTs is String) {
      parsedTimestamp = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else if (rawTs != null) {
      try {
        parsedTimestamp = (rawTs as dynamic).toDate();
      } catch (_) {}
    }

    final singleImage = (map['imageUrl'] ?? map['image_url']) as String?;
    final determinedType = map['type'] as String? ??
        (mediaUrls.length > 1
            ? 'image_group'
            : (singleImage != null || mediaUrls.isNotEmpty ? 'image' : 'text'));

    return CommunityMessage(
      id: id,
      communityId: (map['communityId'] ?? map['community_id'] ?? '').toString(),
      authorHandle: (map['authorHandle'] ?? map['author_handle'] ?? 'Unknown').toString(),
      content: (map['content'] ?? '').toString(),
      timestamp: parsedTimestamp,
      imageUrl: singleImage ?? (mediaUrls.isNotEmpty ? mediaUrls.first : null),
      mediaUrls: mediaUrls,
      type: determinedType,
      reactions: reactions,
    );
  }
}