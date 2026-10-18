class DailyActionProgress {
  final int current;
  final int max;
  final int points;
  final bool isLimitReached;

  const DailyActionProgress({
    this.current = 0,
    this.max = 0,
    this.points = 0,
    this.isLimitReached = false,
  });

  factory DailyActionProgress.fromJson(Map<String, dynamic> json) {
    return DailyActionProgress(
      current: (json['current'] as num?)?.toInt() ?? 0,
      max: (json['max'] as num?)?.toInt() ?? 0,
      points: (json['points'] as num?)?.toInt() ?? 0,
      isLimitReached: json['isLimitReached'] == true,
    );
  }
}

class RewardsSummary {
  final int balance;
  final int lifetimePoints;
  final int weeklyPoints;
  final int streakCount;
  final bool streakAwarded;
  final int dailyPointsToday;
  final int dailyCap;
  final bool isCapReached;
  final DailyActionProgress postsProgress;
  final DailyActionProgress repliesProgress;
  final DailyActionProgress votesProgress;
  final DailyActionProgress listingsProgress;
  final String referralCode;
  final String? highestHelpfulBadge;
  final int helpfulVotes;
  final int soldCount;
  final int nextGoalPoints;
  final int pointsToNextGoal;

  int get dailyPostsCount => postsProgress.current;
  int get dailyPostsMax => postsProgress.max;
  int get dailyRepliesCount => repliesProgress.current;
  int get dailyRepliesMax => repliesProgress.max;
  int get dailyVotesCount => votesProgress.current;
  int get dailyVotesMax => votesProgress.max;
  int get dailyLikesCount => votesProgress.current;
  int get dailyLikesMax => votesProgress.max;
  DailyActionProgress get likesProgress => votesProgress;
  int get likesReceived => helpfulVotes;
  String? get highestLikeBadge => highestHelpfulBadge;
  int get dailyListingsCount => listingsProgress.current;
  int get dailyListingsMax => listingsProgress.max;

  const RewardsSummary({
    this.balance = 0,
    this.lifetimePoints = 0,
    this.weeklyPoints = 0,
    this.streakCount = 0,
    this.streakAwarded = false,
    this.dailyPointsToday = 0,
    this.dailyCap = 50,
    this.isCapReached = false,
    this.postsProgress = const DailyActionProgress(max: 3, points: 5),
    this.repliesProgress = const DailyActionProgress(max: 5, points: 3),
    this.votesProgress = const DailyActionProgress(max: 5, points: 5),
    this.listingsProgress = const DailyActionProgress(max: 3, points: 10),
    this.referralCode = '',
    this.highestHelpfulBadge,
    this.helpfulVotes = 0,
    this.soldCount = 0,
    this.nextGoalPoints = 300,
    this.pointsToNextGoal = 300,
  });

  factory RewardsSummary.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'] as Map<String, dynamic>? ?? {};
    final dailyProgress = json['dailyProgress'] as Map<String, dynamic>? ?? {};
    final postsMap = dailyProgress['posts'] as Map<String, dynamic>? ?? {};
    final repliesMap = dailyProgress['replies'] as Map<String, dynamic>? ?? {};
    final votesMap = (dailyProgress['likes'] as Map<String, dynamic>?) ?? (dailyProgress['votes'] as Map<String, dynamic>?) ?? {};
    final listingsMap = dailyProgress['listings'] as Map<String, dynamic>? ?? {};

    return RewardsSummary(
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      lifetimePoints: (json['lifetimePoints'] as num?)?.toInt() ?? 0,
      weeklyPoints: (json['weeklyPoints'] as num?)?.toInt() ?? 0,
      streakCount: (json['streakCount'] as num?)?.toInt() ?? 0,
      streakAwarded: json['streakAwarded'] == true,
      dailyPointsToday: (json['dailyPointsToday'] as num?)?.toInt() ?? (dailyProgress['dailyPointsUsed'] as num?)?.toInt() ?? 0,
      dailyCap: (json['dailyCap'] as num?)?.toInt() ?? (dailyProgress['dailyCap'] as num?)?.toInt() ?? 50,
      isCapReached: json['isCapReached'] == true || dailyProgress['isCapReached'] == true,
      postsProgress: DailyActionProgress.fromJson(postsMap),
      repliesProgress: DailyActionProgress.fromJson(repliesMap),
      votesProgress: DailyActionProgress.fromJson(votesMap),
      listingsProgress: DailyActionProgress.fromJson(listingsMap),
      referralCode: json['referralCode'] as String? ?? '',
      highestHelpfulBadge: (json['highestLikeBadge'] ?? json['highestHelpfulBadge']) as String?,
      helpfulVotes: (progress['likeCount'] as num?)?.toInt() ?? (progress['likesReceived'] as num?)?.toInt() ?? (progress['helpfulVotes'] as num?)?.toInt() ?? 0,
      soldCount: (progress['soldCount'] as num?)?.toInt() ?? 0,
      nextGoalPoints: (progress['nextGoalPoints'] as num?)?.toInt() ?? 300,
      pointsToNextGoal: (progress['pointsToNextGoal'] as num?)?.toInt() ?? 300,
    );
  }

  RewardsSummary copyWith({
    int? balance,
    int? lifetimePoints,
    int? weeklyPoints,
    int? streakCount,
    bool? streakAwarded,
    int? dailyPointsToday,
    int? dailyCap,
    bool? isCapReached,
    DailyActionProgress? postsProgress,
    DailyActionProgress? repliesProgress,
    DailyActionProgress? votesProgress,
    DailyActionProgress? listingsProgress,
    String? referralCode,
    String? highestHelpfulBadge,
    int? helpfulVotes,
    int? soldCount,
    int? nextGoalPoints,
    int? pointsToNextGoal,
  }) {
    return RewardsSummary(
      balance: balance ?? this.balance,
      lifetimePoints: lifetimePoints ?? this.lifetimePoints,
      weeklyPoints: weeklyPoints ?? this.weeklyPoints,
      streakCount: streakCount ?? this.streakCount,
      streakAwarded: streakAwarded ?? this.streakAwarded,
      dailyPointsToday: dailyPointsToday ?? this.dailyPointsToday,
      dailyCap: dailyCap ?? this.dailyCap,
      isCapReached: isCapReached ?? this.isCapReached,
      postsProgress: postsProgress ?? this.postsProgress,
      repliesProgress: repliesProgress ?? this.repliesProgress,
      votesProgress: votesProgress ?? this.votesProgress,
      listingsProgress: listingsProgress ?? this.listingsProgress,
      referralCode: referralCode ?? this.referralCode,
      highestHelpfulBadge: highestHelpfulBadge ?? this.highestHelpfulBadge,
      helpfulVotes: helpfulVotes ?? this.helpfulVotes,
      soldCount: soldCount ?? this.soldCount,
      nextGoalPoints: nextGoalPoints ?? this.nextGoalPoints,
      pointsToNextGoal: pointsToNextGoal ?? this.pointsToNextGoal,
    );
  }
}

class PointsLedgerEntry {
  final String id;
  final int delta;
  final String reason;
  final String refType;
  final String refId;
  final DateTime createdAt;

  const PointsLedgerEntry({
    required this.id,
    required this.delta,
    required this.reason,
    required this.refType,
    required this.refId,
    required this.createdAt,
  });

  factory PointsLedgerEntry.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    final rawDate = json['created_at'] ?? json['createdAt'];
    if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return PointsLedgerEntry(
      id: json['id'] as String? ?? '',
      delta: (json['delta'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? '',
      refType: (json['ref_type'] ?? json['refType']) as String? ?? '',
      refId: (json['ref_id'] ?? json['refId']) as String? ?? '',
      createdAt: parsedDate,
    );
  }
}

class UserBadgeItem {
  final String key;
  final String name;
  final String description;
  final int required;
  final int current;
  final bool earned;
  final DateTime? earnedAt;

  const UserBadgeItem({
    required this.key,
    required this.name,
    required this.description,
    required this.required,
    required this.current,
    required this.earned,
    this.earnedAt,
  });

  factory UserBadgeItem.fromJson(Map<String, dynamic> json) {
    DateTime? parsedEarnedAt;
    final raw = json['earnedAt'] ?? json['earned_at'];
    if (raw is String) {
      parsedEarnedAt = DateTime.tryParse(raw);
    }

    return UserBadgeItem(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      required: (json['required'] as num?)?.toInt() ?? 1,
      current: (json['current'] as num?)?.toInt() ?? 0,
      earned: json['earned'] == true,
      earnedAt: parsedEarnedAt,
    );
  }
}

class LeaderboardItem {
  final int rank;
  final String handle;
  final String displayName;
  final String avatarUrl;
  final int points;
  final String? topBadge;

  const LeaderboardItem({
    required this.rank,
    required this.handle,
    required this.displayName,
    required this.avatarUrl,
    required this.points,
    this.topBadge,
  });

  factory LeaderboardItem.fromJson(Map<String, dynamic> json) {
    return LeaderboardItem(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      handle: json['handle'] as String? ?? '',
      displayName: json['displayName'] as String? ?? json['handle'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      points: (json['points'] as num?)?.toInt() ?? 0,
      topBadge: json['topBadge'] as String?,
    );
  }
}

class ReferralInviteItem {
  final String id;
  final String inviteeHandle;
  final String status;
  final DateTime createdAt;
  final DateTime? rewardedAt;

  const ReferralInviteItem({
    required this.id,
    required this.inviteeHandle,
    required this.status,
    required this.createdAt,
    this.rewardedAt,
  });

  factory ReferralInviteItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedCreated;
    final rawCreated = json['created_at'] ?? json['createdAt'];
    if (rawCreated is String) {
      parsedCreated = DateTime.tryParse(rawCreated) ?? DateTime.now();
    } else {
      parsedCreated = DateTime.now();
    }

    DateTime? parsedRewarded;
    final rawRewarded = json['rewarded_at'] ?? json['rewardedAt'];
    if (rawRewarded is String) {
      parsedRewarded = DateTime.tryParse(rawRewarded);
    }

    return ReferralInviteItem(
      id: json['id'] as String? ?? '',
      inviteeHandle: (json['invitee_handle'] ?? json['inviteeHandle']) as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: parsedCreated,
      rewardedAt: parsedRewarded,
    );
  }
}

class ReferralInfo {
  final String referralCode;
  final String shareUrl;
  final List<ReferralInviteItem> invites;

  const ReferralInfo({
    required this.referralCode,
    required this.shareUrl,
    required this.invites,
  });

  factory ReferralInfo.fromJson(Map<String, dynamic> json) {
    final rawList = json['invites'] as List<dynamic>? ?? [];
    return ReferralInfo(
      referralCode: json['referralCode'] as String? ?? '',
      shareUrl: json['shareUrl'] as String? ?? '',
      invites: rawList
          .whereType<Map<String, dynamic>>()
          .map((m) => ReferralInviteItem.fromJson(m))
          .toList(),
    );
  }
}

class ShopPerkItem {
  final String id;
  final String shopId;
  final String shopName;
  final String category;
  final String logoUrl;
  final String title;
  final String description;
  final int costPoints;
  final int dailyLimit;
  final DateTime? expiresAt;
  final String codePrefix;

  const ShopPerkItem({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.category,
    required this.logoUrl,
    required this.title,
    this.description = '',
    required this.costPoints,
    required this.dailyLimit,
    this.expiresAt,
    this.codePrefix = 'PERK',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_id': shopId,
      'shop_name': shopName,
      'category': category,
      'logo_r2_path': logoUrl,
      'title': title,
      'description': description,
      'cost_points': costPoints,
      'daily_limit': dailyLimit,
      'expires_at': expiresAt?.toIso8601String(),
      'code_prefix': codePrefix,
    };
  }

  factory ShopPerkItem.fromJson(Map<String, dynamic> json) {
    DateTime? parsedExp;
    final rawExp = json['expires_at'] ?? json['expiresAt'];
    if (rawExp is String) {
      parsedExp = DateTime.tryParse(rawExp);
    }

    return ShopPerkItem(
      id: json['id'] as String? ?? '',
      shopId: (json['shop_id'] ?? json['shopId']) as String? ?? '',
      shopName: (json['shop_name'] ?? json['shopName']) as String? ?? '',
      category: json['category'] as String? ?? 'General',
      logoUrl: (json['logo_r2_path'] ?? json['logoUrl']) as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      costPoints: (json['cost_points'] as num?)?.toInt() ?? (json['costPoints'] as num?)?.toInt() ?? 100,
      dailyLimit: (json['daily_limit'] as num?)?.toInt() ?? (json['dailyLimit'] as num?)?.toInt() ?? 10,
      expiresAt: parsedExp,
      codePrefix: (json['code_prefix'] ?? json['codePrefix']) as String? ?? 'PERK',
    );
  }
}

class UnlockedCouponItem {
  final String id;
  final String code;
  final String title;
  final DateTime expiresAt;

  const UnlockedCouponItem({
    required this.id,
    required this.code,
    required this.title,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'title': title,
      'expires_at': expiresAt.toIso8601String(),
    };
  }

  factory UnlockedCouponItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedExp;
    final rawExp = json['expires_at'] ?? json['expiresAt'];
    if (rawExp is String) {
      parsedExp = DateTime.tryParse(rawExp) ?? DateTime.now().add(const Duration(days: 7));
    } else {
      parsedExp = DateTime.now().add(const Duration(days: 7));
    }

    return UnlockedCouponItem(
      id: json['id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      expiresAt: parsedExp,
    );
  }
}
