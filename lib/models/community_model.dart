class CommunityModel {
  final String id;
  final String name;
  final String description;
  final bool isChannel;
  final String adminHandle;
  final String ownerHandle;
  final String visibility; // 'public' | 'private'
  final String? username;
  final String? inviteLink;
  final Map<String, dynamic> settings;
  final int memberCount;
  final String? imageUrl;
  final String myRole; // 'owner' | 'admin' | 'member'
  final Map<String, dynamic> myPermissions;
  final bool isMuted;
  final int mutedUntil;
  final bool isArchived;
  final int unreadCount;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastSenderHandle;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CommunityModel({
    required this.id,
    required this.name,
    required this.description,
    required this.isChannel,
    required this.adminHandle,
    String? ownerHandle,
    this.visibility = 'public',
    this.username,
    this.inviteLink,
    this.settings = const {},
    required this.memberCount,
    this.imageUrl,
    this.myRole = '',
    this.myPermissions = const {},
    this.isMuted = false,
    this.mutedUntil = 0,
    this.isArchived = false,
    this.unreadCount = 0,
    this.lastMessage,
    this.lastMessageAt,
    this.lastSenderHandle,
    required this.createdAt,
    this.updatedAt,
  }) : ownerHandle = ownerHandle ?? adminHandle;

  bool get isMember => myRole == 'owner' || myRole == 'admin' || myRole == 'member';
  bool get isOwner => myRole == 'owner';
  bool get isAdmin => myRole == 'owner' || myRole == 'admin';
  bool get isPrivate => visibility.toLowerCase() == 'private';
  bool get isPublic => !isPrivate;

  String get whoCanSend =>
      (settings['who_can_send'] as String?) ?? (isChannel ? 'admins_only' : 'all');

  bool get canPost {
    if (isChannel) return isAdmin;
    if (whoCanSend == 'admins_only') return isAdmin;
    return true;
  }

  bool get canSendMedia {
    if (!canPost) return false;
    if (isAdmin) return true;
    final media = settings['media_permissions'] as Map<String, dynamic>?;
    if (media == null) return true;
    return media['photo'] == true || media['video'] == true;
  }

  bool get approveNewMembers => settings['approve_new_members'] == true;

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

    DateTime? parseNullableDateTime(dynamic val) {
      if (val == null) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) {
        if (val > 10000000000) {
          return DateTime.fromMillisecondsSinceEpoch(val);
        } else {
          return DateTime.fromMillisecondsSinceEpoch(val * 1000);
        }
      }
      return null;
    }

    final admin = (map['adminHandle'] ?? map['admin_handle'] ?? '').toString().replaceAll('@', '').trim();
    final owner = (map['ownerHandle'] ?? map['owner_handle'] ?? admin).toString().replaceAll('@', '').trim();

    Map<String, dynamic> parsedSettings = {};
    final rawSettings = map['settings'] ?? map['settings_json'];
    if (rawSettings is Map) {
      parsedSettings = Map<String, dynamic>.from(rawSettings);
    }

    Map<String, dynamic> parsedPermissions = {};
    final rawPerms = map['myPermissions'] ?? map['permissions'] ?? map['admin_permissions_json'];
    if (rawPerms is Map) {
      parsedPermissions = Map<String, dynamic>.from(rawPerms);
    }

    return CommunityModel(
      id: id,
      name: (map['name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      isChannel: map['isChannel'] == true || map['is_channel'] == 1,
      adminHandle: admin,
      ownerHandle: owner,
      visibility: (map['visibility'] ?? 'public').toString(),
      username: map['username'] as String?,
      inviteLink: (map['inviteLink'] ?? map['invite_link']) as String?,
      settings: parsedSettings,
      memberCount: (map['memberCount'] ?? map['member_count'] as num?)?.toInt() ?? 1,
      imageUrl: (map['imageUrl'] ?? map['image_url']) as String?,
      myRole: (map['myRole'] ?? map['role'] ?? '').toString(),
      myPermissions: parsedPermissions,
      isMuted: map['isMuted'] == true || map['is_muted'] == true,
      mutedUntil: (map['mutedUntil'] ?? map['muted_until'] as num?)?.toInt() ?? 0,
      isArchived: map['isArchived'] == true || map['is_archived'] == true || map['is_archived'] == 1,
      unreadCount: (map['unreadCount'] ?? map['unread_count'] as num?)?.toInt() ?? 0,
      lastMessage: map['lastMessage'] as String?,
      lastMessageAt: parseNullableDateTime(map['lastMessageAt'] ?? map['last_message_at']),
      lastSenderHandle: map['lastSenderHandle'] as String?,
      createdAt: parseDateTime(map['createdAt'] ?? map['created_at']),
      updatedAt: parseNullableDateTime(map['updatedAt'] ?? map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'isChannel': isChannel,
      'adminHandle': adminHandle,
      'ownerHandle': ownerHandle,
      'visibility': visibility,
      if (username != null) 'username': username,
      if (inviteLink != null) 'inviteLink': inviteLink,
      'settings': settings,
      'memberCount': memberCount,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  CommunityModel copyWith({
    String? name,
    String? description,
    bool? isChannel,
    String? adminHandle,
    String? ownerHandle,
    String? visibility,
    String? username,
    String? inviteLink,
    Map<String, dynamic>? settings,
    int? memberCount,
    String? imageUrl,
    String? myRole,
    Map<String, dynamic>? myPermissions,
    bool? isMuted,
    int? mutedUntil,
    bool? isArchived,
    int? unreadCount,
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastSenderHandle,
  }) {
    return CommunityModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      isChannel: isChannel ?? this.isChannel,
      adminHandle: adminHandle ?? this.adminHandle,
      ownerHandle: ownerHandle ?? this.ownerHandle,
      visibility: visibility ?? this.visibility,
      username: username ?? this.username,
      inviteLink: inviteLink ?? this.inviteLink,
      settings: settings ?? this.settings,
      memberCount: memberCount ?? this.memberCount,
      imageUrl: imageUrl ?? this.imageUrl,
      myRole: myRole ?? this.myRole,
      myPermissions: myPermissions ?? this.myPermissions,
      isMuted: isMuted ?? this.isMuted,
      mutedUntil: mutedUntil ?? this.mutedUntil,
      isArchived: isArchived ?? this.isArchived,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastSenderHandle: lastSenderHandle ?? this.lastSenderHandle,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class CommunityMessage {
  final String id;
  final String communityId;
  final String authorHandle;
  final String content;
  final DateTime timestamp;
  final String? imageUrl;
  final List<String> mediaUrls;
  final String type; // "text", "image", "video", "image_group", "system"
  final Map<String, List<String>> reactions;
  final bool pinned;
  final bool isSystem;
  final DateTime? editedAt;
  final bool deletedForEveryone;
  final String? deletedBy;

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
    this.pinned = false,
    this.isSystem = false,
    this.editedAt,
    this.deletedForEveryone = false,
    this.deletedBy,
  });

  bool get isEdited => editedAt != null;

  bool canEdit(String userHandle) {
    if (isSystem || deletedForEveryone) return false;
    final clean = userHandle.replaceAll('@', '').trim().toLowerCase();
    if (authorHandle.toLowerCase() != clean) return false;
    return DateTime.now().difference(timestamp).inHours < 48;
  }

  factory CommunityMessage.fromMap(Map<String, dynamic> map, String id) {
    final reactions = <String, List<String>>{};
    final rawReactions = map['reactions'] ?? map['reactions_json'];
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

    DateTime? parsedEditedAt;
    final rawEdited = map['editedAt'] ?? map['edited_at'];
    if (rawEdited is String) {
      parsedEditedAt = DateTime.tryParse(rawEdited);
    } else if (rawEdited is int) {
      parsedEditedAt = DateTime.fromMillisecondsSinceEpoch(
          rawEdited > 10000000000 ? rawEdited : rawEdited * 1000);
    }

    final singleImage = (map['imageUrl'] ?? map['image_url']) as String?;
    final determinedType = (map['type'] ?? map['message_type'] ??
        (mediaUrls.length > 1
            ? 'image_group'
            : (singleImage != null || mediaUrls.isNotEmpty ? 'image' : 'text'))).toString();

    final isSys = map['isSystem'] == true || map['is_system'] == 1 || determinedType == 'system';

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
      pinned: map['pinned'] == true || map['pinned'] == 1,
      isSystem: isSys,
      editedAt: parsedEditedAt,
      deletedForEveryone: map['deletedForEveryone'] == true || map['deleted_for_everyone'] == 1,
      deletedBy: map['deletedBy'] as String?,
    );
  }
}