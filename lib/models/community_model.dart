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
  final String? imageUrl;           // Feature #11: image messages
  final Map<String, List<String>> reactions; // Feature #9: emoji reactions

  CommunityMessage({
    required this.id,
    required this.communityId,
    required this.authorHandle,
    required this.content,
    required this.timestamp,
    this.imageUrl,
    this.reactions = const {},
  });

  factory CommunityMessage.fromMap(Map<String, dynamic> map, String id) {
    // Parse reactions: { "emoji": ["handle1","handle2"] }
    final rawReactions = map['reactions'] as Map<String, dynamic>? ?? {};
    final reactions = rawReactions.map(
      (emoji, handles) => MapEntry(
        emoji,
        List<String>.from(handles as List),
      ),
    );

    return CommunityMessage(
      id: id,
      communityId: map['communityId'] ?? '',
      authorHandle: map['authorHandle'] ?? 'Unknown',
      content: map['content'] ?? '',
      timestamp: map['timestamp'] != null
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      imageUrl: map['imageUrl'] as String?,
      reactions: reactions,
    );
  }
}