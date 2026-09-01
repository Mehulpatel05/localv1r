import '../core/constants/areas_and_categories.dart';

class Post {
  final String id;
  final String authorHandle;
  final String content;
  final String? imageUrl;
  final VadodaraArea area;
  final PostCategory category;
  final DateTime createdAt;
  int upvotes;
  int downvotes;
  int commentCount;
  int userVote; // 1 for up, -1 for down, 0 for none
  final bool isEmergency;
  final int reportCount;
  final List<String> reporters;

  Post({
    required this.id,
    required this.authorHandle,
    required this.content,
    this.imageUrl,
    required this.area,
    required this.category,
    required this.createdAt,
    this.upvotes = 0,
    this.downvotes = 0,
    this.commentCount = 0,
    this.userVote = 0,
    this.isEmergency = false,
    this.reportCount = 0,
    required this.reporters,
  });

  int get score => upvotes - downvotes;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorHandle': authorHandle,
      'content': content,
      'imageUrl': imageUrl,
      'area': area.name,
      'category': category.name,
      'createdAt': createdAt.toIso8601String(),
      'upvotes': upvotes,
      'downvotes': downvotes,
      'commentCount': commentCount,
      'userVote': userVote,
      'isEmergency': isEmergency,
      'reportCount': reportCount,
      'reporters': reporters,
    };
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      authorHandle: json['authorHandle'] as String,
      content: json['content'] as String,
      imageUrl: json['imageUrl'] as String?,
      area: VadodaraArea.values.byName(json['area'] as String),
      category: PostCategory.values.byName(json['category'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      upvotes: json['upvotes'] as int? ?? 0,
      downvotes: json['downvotes'] as int? ?? 0,
      commentCount: json['commentCount'] as int? ?? 0,
      userVote: json['userVote'] as int? ?? 0,
      isEmergency: json['isEmergency'] as bool? ?? false,
      reportCount: json['reportCount'] as int? ?? 0,
      reporters: List<String>.from(json['reporters'] ?? []),
    );
  }
}
