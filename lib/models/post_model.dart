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

  // 🏠 Room-specific fields (only for PostCategory.rooms)
  final String? roomTitle;
  final String? roomArea;
  final String? roomRent;
  final List<String> mediaUrls; // multiple images + video

  // 🛍️ Shop-specific fields (only for PostCategory.shop)
  final String? shopTitle;
  final String? shopPrice;

  // 🍲 Food-specific fields (only for PostCategory.food)
  final String? foodTitle;
  final double? foodRating;
  final String? foodPrice;

  // 🎉 Events-specific fields (only for PostCategory.events)
  final String? eventTitle;
  final String? eventDate;
  final String? eventLocationText;
  final String? eventPrice;

  // 💼 Jobs-specific fields (only for PostCategory.jobs)
  final String? jobTitle;
  final String? jobCompany;
  final String? jobLocation;
  final String? jobType;

  // 🔧 Services-specific fields (only for PostCategory.services)
  final String? serviceTitle;
  final String? serviceCategoryText;
  final String? servicePrice;

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
    this.roomTitle,
    this.roomArea,
    this.roomRent,
    this.mediaUrls = const [],
    this.shopTitle,
    this.shopPrice,
    this.foodTitle,
    this.foodRating,
    this.foodPrice,
    this.eventTitle,
    this.eventDate,
    this.eventLocationText,
    this.eventPrice,
    this.jobTitle,
    this.jobCompany,
    this.jobLocation,
    this.jobType,
    this.serviceTitle,
    this.serviceCategoryText,
    this.servicePrice,
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
      'roomTitle': roomTitle,
      'roomArea': roomArea,
      'roomRent': roomRent,
      'mediaUrls': mediaUrls,
      'shopTitle': shopTitle,
      'shopPrice': shopPrice,
      'foodTitle': foodTitle,
      'foodRating': foodRating,
      'foodPrice': foodPrice,
      'eventTitle': eventTitle,
      'eventDate': eventDate,
      'eventLocationText': eventLocationText,
      'eventPrice': eventPrice,
      'jobTitle': jobTitle,
      'jobCompany': jobCompany,
      'jobLocation': jobLocation,
      'jobType': jobType,
      'serviceTitle': serviceTitle,
      'serviceCategoryText': serviceCategoryText,
      'servicePrice': servicePrice,
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
      roomTitle: json['roomTitle'] as String?,
      roomArea: json['roomArea'] as String?,
      roomRent: json['roomRent'] as String?,
      mediaUrls: List<String>.from(json['mediaUrls'] ?? []),
      shopTitle: json['shopTitle'] as String?,
      shopPrice: json['shopPrice'] as String?,
      foodTitle: json['foodTitle'] as String?,
      foodRating: (json['foodRating'] as num?)?.toDouble(),
      foodPrice: json['foodPrice'] as String?,
      eventTitle: json['eventTitle'] as String?,
      eventDate: json['eventDate'] as String?,
      eventLocationText: json['eventLocationText'] as String?,
      eventPrice: json['eventPrice'] as String?,
      jobTitle: json['jobTitle'] as String?,
      jobCompany: json['jobCompany'] as String?,
      jobLocation: json['jobLocation'] as String?,
      jobType: json['jobType'] as String?,
      serviceTitle: json['serviceTitle'] as String?,
      serviceCategoryText: json['serviceCategoryText'] as String?,
      servicePrice: json['servicePrice'] as String?,
    );
  }
}
