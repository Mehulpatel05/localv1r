import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityModel {
  final String id;
  final String name;
  final String description;
  final bool isChannel;
  final String adminHandle;
  final int memberCount;
  final DateTime createdAt;
  final String? imageUrl; // Feature #7: community avatar

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
    return CommunityModel(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      isChannel: map['isChannel'] ?? false,
      adminHandle: map['adminHandle'] ?? '',
      memberCount: map['memberCount'] ?? 1,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      imageUrl: map['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'isChannel': isChannel,
      'adminHandle': adminHandle,
      'memberCount': memberCount,
      'createdAt': FieldValue.serverTimestamp(),
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }

  // B5: copyWith to allow local state update after edit without Firestore re-fetch
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
  final Map<String, List<String>> reactions; // Feature #9: emoji reactions

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
    final rawMedia = map['mediaUrls'];
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
    final rawTs = map['timestamp'];
    if (rawTs is Timestamp) {
      parsedTimestamp = rawTs.toDate();
    } else if (rawTs is int) {
      parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else if (rawTs is String) {
      parsedTimestamp = DateTime.tryParse(rawTs) ?? DateTime.now();
    }

    final singleImage = map['imageUrl'] as String?;
    final determinedType = map['type'] as String? ??
        (mediaUrls.length > 1
            ? 'image_group'
            : (singleImage != null || mediaUrls.isNotEmpty ? 'image' : 'text'));

    return CommunityMessage(
      id: id,
      communityId: (map['communityId'] ?? '').toString(),
      authorHandle: (map['authorHandle'] ?? 'Unknown').toString(),
      content: (map['content'] ?? '').toString(),
      timestamp: parsedTimestamp,
      imageUrl: singleImage ?? (mediaUrls.isNotEmpty ? mediaUrls.first : null),
      mediaUrls: mediaUrls,
      type: determinedType,
      reactions: reactions,
    );
  }
}