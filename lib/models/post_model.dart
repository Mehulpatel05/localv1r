import '../core/constants/areas_and_categories.dart';

class Post {
  final String id;
  final String authorHandle;
  final String content;
  final String? imageUrl;
  final PostCategory category;
  final DateTime createdAt;
  int upvotes;
  int downvotes;
  int commentCount;
  int userVote; // 1 for up, -1 for down, 0 for none
  final bool isEmergency;
  final int reportCount;
  final List<String> reporters;

  final String? stateId;
  final String? cityId;
  final String? areaId;
  final String? areaName;

  // 🏠 Room-specific fields (only for PostCategory.rooms)
  final String? roomTitle;
  final String? roomArea;
  final String? roomRent;
  final List<String> mediaUrls; // multiple images + video

  // 🛍️ Shop-specific fields (only for PostCategory.shop)
  final String? shopTitle;
  final String? shopPrice;
  final String? shopCategory;

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
    required this.category,
    required this.createdAt,
    this.stateId,
    this.cityId,
    this.areaId,
    this.areaName,
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
    this.shopCategory,
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
      'category': category.name,
      'createdAt': createdAt.toIso8601String(),
      'stateId': stateId,
      'cityId': cityId,
      'areaId': areaId,
      'areaName': areaName,
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
      'shopCategory': shopCategory,
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
      shopCategory: json['shopCategory'] as String?,
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

  Post copyWith({
    String? id,
    String? authorHandle,
    String? content,
    String? imageUrl,
    PostCategory? category,
    DateTime? createdAt,
    String? stateId,
    String? cityId,
    String? areaId,
    String? areaName,
    int? upvotes,
    int? downvotes,
    int? commentCount,
    int? userVote,
    bool? isEmergency,
    int? reportCount,
    List<String>? reporters,
    String? roomTitle,
    String? roomArea,
    String? roomRent,
    List<String>? mediaUrls,
    String? shopTitle,
    String? shopPrice,
    String? shopCategory,
    String? foodTitle,
    double? foodRating,
    String? foodPrice,
    String? eventTitle,
    String? eventDate,
    String? eventLocationText,
    String? eventPrice,
    String? jobTitle,
    String? jobCompany,
    String? jobLocation,
    String? jobType,
    String? serviceTitle,
    String? serviceCategoryText,
    String? servicePrice,
  }) {
    return Post(
      id: id ?? this.id,
      authorHandle: authorHandle ?? this.authorHandle,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      stateId: stateId ?? this.stateId,
      cityId: cityId ?? this.cityId,
      areaId: areaId ?? this.areaId,
      areaName: areaName ?? this.areaName,
      upvotes: upvotes ?? this.upvotes,
      downvotes: downvotes ?? this.downvotes,
      commentCount: commentCount ?? this.commentCount,
      userVote: userVote ?? this.userVote,
      isEmergency: isEmergency ?? this.isEmergency,
      reportCount: reportCount ?? this.reportCount,
      reporters: reporters ?? this.reporters,
      roomTitle: roomTitle ?? this.roomTitle,
      roomArea: roomArea ?? this.roomArea,
      roomRent: roomRent ?? this.roomRent,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      shopTitle: shopTitle ?? this.shopTitle,
      shopPrice: shopPrice ?? this.shopPrice,
      shopCategory: shopCategory ?? this.shopCategory,
      foodTitle: foodTitle ?? this.foodTitle,
      foodRating: foodRating ?? this.foodRating,
      foodPrice: foodPrice ?? this.foodPrice,
      eventTitle: eventTitle ?? this.eventTitle,
      eventDate: eventDate ?? this.eventDate,
      eventLocationText: eventLocationText ?? this.eventLocationText,
      eventPrice: eventPrice ?? this.eventPrice,
      jobTitle: jobTitle ?? this.jobTitle,
      jobCompany: jobCompany ?? this.jobCompany,
      jobLocation: jobLocation ?? this.jobLocation,
      jobType: jobType ?? this.jobType,
      serviceTitle: serviceTitle ?? this.serviceTitle,
      serviceCategoryText: serviceCategoryText ?? this.serviceCategoryText,
      servicePrice: servicePrice ?? this.servicePrice,
    );
  }
}
