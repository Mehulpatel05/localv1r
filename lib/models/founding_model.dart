enum FoundingUserState {
  locked,
  available,
  pending,
  approved,
  rejected,
}

class FoundingMyStatus {
  final FoundingUserState state;
  final int? seq;
  final String? cityId;
  final String? cityName;
  final String? areaId;
  final String? areaName;
  final String? reason;
  final bool canReapply;
  final int daysRemaining;
  final int postCount;
  final int approvedCount;
  final int spotsLeft;
  final DateTime? createdAt;

  const FoundingMyStatus({
    required this.state,
    this.seq,
    this.cityId,
    this.cityName,
    this.areaId,
    this.areaName,
    this.reason,
    this.canReapply = false,
    this.daysRemaining = 0,
    this.postCount = 0,
    this.approvedCount = 0,
    this.spotsLeft = 100,
    this.createdAt,
  });

  factory FoundingMyStatus.fromJson(Map<String, dynamic> json) {
    final rawState = json['state'] as String? ?? 'locked';
    FoundingUserState state = FoundingUserState.locked;
    if (rawState == 'available') {
      state = FoundingUserState.available;
    } else if (rawState == 'pending') {
      state = FoundingUserState.pending;
    } else if (rawState == 'approved') {
      state = FoundingUserState.approved;
    } else if (rawState == 'rejected') {
      state = FoundingUserState.rejected;
    }

    DateTime? created;
    if (json['createdAt'] != null) {
      created = DateTime.tryParse(json['createdAt'].toString());
    }

    return FoundingMyStatus(
      state: state,
      seq: (json['seq'] as num?)?.toInt(),
      cityId: json['cityId'] as String?,
      cityName: json['cityName'] as String?,
      areaId: json['areaId'] as String?,
      areaName: json['areaName'] as String?,
      reason: json['reason'] as String?,
      canReapply: json['canReapply'] == true,
      daysRemaining: (json['daysRemaining'] as num?)?.toInt() ?? 0,
      postCount: (json['postCount'] as num?)?.toInt() ?? 0,
      approvedCount: (json['approvedCount'] as num?)?.toInt() ?? 0,
      spotsLeft: (json['spotsLeft'] as num?)?.toInt() ?? 100,
      createdAt: created,
    );
  }
}

class AdminFoundingCity {
  final String cityId;
  final String name;
  final int pendingCount;
  final int approvedCount;

  const AdminFoundingCity({
    required this.cityId,
    required this.name,
    required this.pendingCount,
    required this.approvedCount,
  });

  factory AdminFoundingCity.fromJson(Map<String, dynamic> json) {
    return AdminFoundingCity(
      cityId: json['cityId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      approvedCount: (json['approvedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminFoundingArea {
  final String areaId;
  final String name;
  final int pendingCount;
  final int approvedCount;
  final int spotsLeft;

  const AdminFoundingArea({
    required this.areaId,
    required this.name,
    required this.pendingCount,
    required this.approvedCount,
    required this.spotsLeft,
  });

  factory AdminFoundingArea.fromJson(Map<String, dynamic> json) {
    return AdminFoundingArea(
      areaId: json['areaId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      approvedCount: (json['approvedCount'] as num?)?.toInt() ?? 0,
      spotsLeft: (json['spotsLeft'] as num?)?.toInt() ?? 100,
    );
  }
}

class AdminFoundingRequestItem {
  final String id;
  final int queueNumber;
  final String userId;
  final String displayName;
  final String avatarUrl;
  final String status;
  final String reason;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String firstPostPreview;
  final String firstPostDate;
  final String? areaName;
  final String? cityName;

  const AdminFoundingRequestItem({
    required this.id,
    required this.queueNumber,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.status,
    required this.reason,
    required this.createdAt,
    this.reviewedAt,
    required this.firstPostPreview,
    required this.firstPostDate,
    this.areaName,
    this.cityName,
  });

  factory AdminFoundingRequestItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedCreated = DateTime.now();
    if (json['createdAt'] != null) {
      parsedCreated = DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now();
    }
    DateTime? parsedReviewed;
    if (json['reviewedAt'] != null) {
      parsedReviewed = DateTime.tryParse(json['reviewedAt'].toString());
    }

    return AdminFoundingRequestItem(
      id: json['id'] as String? ?? '',
      queueNumber: (json['queueNumber'] as num?)?.toInt() ?? 1,
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? (json['userId'] as String? ?? ''),
      avatarUrl: json['avatarUrl'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      reason: json['reason'] as String? ?? '',
      createdAt: parsedCreated,
      reviewedAt: parsedReviewed,
      firstPostPreview: json['firstPostPreview'] as String? ?? '',
      firstPostDate: json['firstPostDate'] as String? ?? '',
      areaName: json['areaName'] as String?,
      cityName: json['cityName'] as String?,
    );
  }
}

class AdminFounderItem {
  final int seq;
  final String userId;
  final String displayName;
  final String avatarUrl;
  final DateTime createdAt;
  final String? areaName;

  const AdminFounderItem({
    required this.seq,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.createdAt,
    this.areaName,
  });

  factory AdminFounderItem.fromJson(Map<String, dynamic> json) {
    DateTime parsed = DateTime.now();
    if (json['createdAt'] != null) {
      parsed = DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now();
    }
    return AdminFounderItem(
      seq: (json['seq'] as num?)?.toInt() ?? 1,
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? (json['userId'] as String? ?? ''),
      avatarUrl: json['avatarUrl'] as String? ?? '',
      createdAt: parsed,
      areaName: json['areaName'] as String?,
    );
  }
}
