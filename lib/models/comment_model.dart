class Comment {
  final String id;
  final String postId;
  final String authorHandle;
  final String? authorName;
  final String? authorBadge;
  final bool isVerified;
  final String content;
  final DateTime createdAt;
  final int likeCount;
  final bool isLiked;

  Comment({
    required this.id,
    required this.postId,
    required this.authorHandle,
    this.authorName,
    this.authorBadge,
    this.isVerified = false,
    required this.content,
    required this.createdAt,
    this.likeCount = 0,
    this.isLiked = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'postId': postId,
      'authorHandle': authorHandle,
      'authorName': authorName,
      'authorBadge': authorBadge,
      'isVerified': isVerified,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'likeCount': likeCount,
      'isLiked': isLiked,
    };
  }

  static DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is DateTime) return val.toLocal();
    if (val is int) {
      if (val < 10000000000) return DateTime.fromMillisecondsSinceEpoch(val * 1000).toLocal();
      return DateTime.fromMillisecondsSinceEpoch(val).toLocal();
    }
    final s = val.toString().trim();
    if (s.isEmpty) return DateTime.now();
    final numVal = int.tryParse(s);
    if (numVal != null) {
      if (numVal < 10000000000) return DateTime.fromMillisecondsSinceEpoch(numVal * 1000).toLocal();
      return DateTime.fromMillisecondsSinceEpoch(numVal).toLocal();
    }
    final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
    final iso = (normalized.endsWith('Z') || normalized.contains('+') || (normalized.length > 10 && normalized.substring(10).contains('-')))
        ? normalized
        : '${normalized}Z';
    return (DateTime.tryParse(iso) ?? DateTime.tryParse(normalized) ?? DateTime.now()).toLocal();
  }

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as String,
      postId: json['postId'] as String,
      authorHandle: (json['authorHandle'] ?? json['author_handle'] ?? '').toString(),
      authorName: (json['displayName'] ?? json['display_name'] ?? json['authorName'] ?? json['author_name']) as String?,
      authorBadge: (json['authorBadge'] ?? json['author_badge'] ?? json['badge']) as String?,
      isVerified: json['isVerified'] == true || json['is_verified'] == 1,
      content: json['content'] as String? ?? '',
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      likeCount: json['likeCount'] as int? ??
          json['like_count'] as int? ??
          json['helpfulVotes'] as int? ??
          json['helpful_votes'] as int? ??
          0,
      isLiked: json['liked_by_me'] == true ||
          json['likedByMe'] == true ||
          json['isLiked'] == true ||
          json['is_liked'] == 1 ||
          json['is_liked'] == true ||
          json['isHelpfulVoted'] == true ||
          json['is_helpful_voted'] == 1 ||
          json['is_helpful_voted'] == true,
    );
  }
}
