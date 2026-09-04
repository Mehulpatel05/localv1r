import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityModel {
  final String id;
  final String name;
  final String description;
  final bool isChannel;
  final String adminHandle;
  final int memberCount;
  final DateTime createdAt;

  CommunityModel({
    required this.id,
    required this.name,
    required this.description,
    required this.isChannel,
    required this.adminHandle,
    required this.memberCount,
    required this.createdAt,
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
    };
  }
}

class CommunityMessage {
  final String id;
  final String communityId;
  final String authorHandle;
  final String content;
  final DateTime timestamp;

  CommunityMessage({
    required this.id,
    required this.communityId,
    required this.authorHandle,
    required this.content,
    required this.timestamp,
  });

  factory CommunityMessage.fromMap(Map<String, dynamic> map, String id) {
    return CommunityMessage(
      id: id,
      communityId: map['communityId'] ?? '',
      authorHandle: map['authorHandle'] ?? 'Unknown',
      content: map['content'] ?? '',
      timestamp: map['timestamp'] != null
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
