import '../core/constants/areas_and_categories.dart';
import '../services/user_action_state_service.dart';
import '../core/action_state/action_state_provider.dart';

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
  final double? lat;
  final double? lng;

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
  final bool isRecommended;

  // 🛍️ Phase 2 Shop Enhancements
  final bool isSold;
  final String? itemCondition; // New, Like New, Used, Free

  // 🏠 Phase 2 Rooms Enhancements
  final String? roomFurnishing; // Furnished, Semi-Furnished, Unfurnished
  final String? roomTenantPreference; // Bachelors, Family, Any

  // 💼 Phase 2 Jobs Enhancements
  final String? jobWorkMode; // On-site, Remote, Hybrid

  // 🎉 Phase 2 Events Enhancements
  final int eventRsvpCount;
  final bool isUserRsvped;

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
    this.lat,
    this.lng,
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
    this.isRecommended = false,
    this.isSold = false,
    this.itemCondition,
    this.roomFurnishing,
    this.roomTenantPreference,
    this.jobWorkMode,
    this.eventRsvpCount = 0,
    this.isUserRsvped = false,
  });

  int get score => upvotes - downvotes;
  int get likes => upvotes > 0 ? upvotes : 0;
  bool get isLiked => userVote == 1;

  bool get isSaved =>
      UserActionStateService.instance.isSaved(id) ||
      ActionStateProvider.instance.isSaved(id);

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }

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
      'lat': lat,
      'lng': lng,
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
      'isRecommended': isRecommended,
      'isSold': isSold,
      'itemCondition': itemCondition,
      'roomFurnishing': roomFurnishing,
      'roomTenantPreference': roomTenantPreference,
      'jobWorkMode': jobWorkMode,
      'eventRsvpCount': eventRsvpCount,
      'isUserRsvped': isUserRsvped,
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
      isRecommended: json['isRecommended'] as bool? ?? false,
      isSold: json['isSold'] as bool? ?? false,
      itemCondition: json['itemCondition'] as String?,
      roomFurnishing: json['roomFurnishing'] as String?,
      roomTenantPreference: json['roomTenantPreference'] as String?,
      jobWorkMode: json['jobWorkMode'] as String?,
      eventRsvpCount: json['eventRsvpCount'] as int? ?? 0,
      isUserRsvped: json['isUserRsvped'] as bool? ?? false,
    );
  }


  factory Post.fromMap(Map<String, dynamic> json, String id) {
    DateTime parsedDate = DateTime.now();
    if (json['createdAt'] != null) {
      final c = json['createdAt'];
      if (c is DateTime) {
        parsedDate = c;
      } else if (c is String) {
        parsedDate = DateTime.tryParse(c) ?? DateTime.now();
      } else if (c is int) {
        parsedDate = c > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(c)
            : DateTime.fromMillisecondsSinceEpoch(c * 1000);
      } else if (c.runtimeType.toString().contains('Timestamp')) {
        try {
          parsedDate = (c as dynamic).toDate();
        } catch (_) {}
      }
    }

    PostCategory cat = PostCategory.general;
    if (json['category'] != null) {
      try {
        cat = PostCategory.values.byName(json['category'].toString().toLowerCase());
      } catch (_) {
        cat = PostCategory.general;
      }
    }

    return Post(
      id: id,
      authorHandle: (json['authorHandle'] as String?) ?? 'Anon',
      content: (json['content'] as String?) ?? '',
      imageUrl: json['imageUrl'] as String?,
      category: cat,
      createdAt: parsedDate,
      upvotes: json['upvotes'] as int? ?? 0,
      downvotes: json['downvotes'] as int? ?? 0,
      commentCount: json['commentCount'] as int? ?? 0,
      userVote: json['userVote'] as int? ?? 0,
      isEmergency: json['isEmergency'] as bool? ?? false,
      reportCount: json['reportCount'] as int? ?? 0,
      reporters: List<String>.from(json['reporters'] ?? []),
      stateId: json['stateId'] as String?,
      cityId: json['cityId'] as String?,
      areaId: json['areaId'] as String?,
      areaName: json['areaName'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
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
      isRecommended: json['isRecommended'] as bool? ?? false,
      isSold: json['isSold'] as bool? ?? false,
      itemCondition: json['itemCondition'] as String?,
      roomFurnishing: json['roomFurnishing'] as String?,
      roomTenantPreference: json['roomTenantPreference'] as String?,
      jobWorkMode: json['jobWorkMode'] as String?,
      eventRsvpCount: json['eventRsvpCount'] as int? ?? 0,
      isUserRsvped: json['isUserRsvped'] as bool? ?? false,
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
    bool? isRecommended,
    bool? isSold,
    String? itemCondition,
    String? roomFurnishing,
    String? roomTenantPreference,
    String? jobWorkMode,
    int? eventRsvpCount,
    bool? isUserRsvped,
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
      isRecommended: isRecommended ?? this.isRecommended,
      isSold: isSold ?? this.isSold,
      itemCondition: itemCondition ?? this.itemCondition,
      roomFurnishing: roomFurnishing ?? this.roomFurnishing,
      roomTenantPreference: roomTenantPreference ?? this.roomTenantPreference,
      jobWorkMode: jobWorkMode ?? this.jobWorkMode,
      eventRsvpCount: eventRsvpCount ?? this.eventRsvpCount,
      isUserRsvped: isUserRsvped ?? this.isUserRsvped,
    );
  }
}
