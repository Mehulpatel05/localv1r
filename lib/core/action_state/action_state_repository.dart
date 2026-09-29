import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../services/auth_service.dart';

/// ⚡ Phase 3: Precomputed State Document Representation
class PrecomputedActionDoc {
  final Set<String> savedListingIds;
  final Set<String> appliedJobIds;
  final Set<String> likedPostIds;
  final Set<String> blockedUserIds;
  final Set<String> followingUserIds;
  final Set<String> reportedIds;
  final Map<String, int> votes;
  final int lastUpdated;

  const PrecomputedActionDoc({
    this.savedListingIds = const {},
    this.appliedJobIds = const {},
    this.likedPostIds = const {},
    this.blockedUserIds = const {},
    this.followingUserIds = const {},
    this.reportedIds = const {},
    this.votes = const {},
    this.lastUpdated = 0,
  });

  Map<String, dynamic> toJson() => {
        'savedListingIds': savedListingIds.toList(),
        'appliedJobIds': appliedJobIds.toList(),
        'likedPostIds': likedPostIds.toList(),
        'blockedUserIds': blockedUserIds.toList(),
        'followingUserIds': followingUserIds.toList(),
        'reportedIds': reportedIds.toList(),
        'votes': votes,
        'lastUpdated': lastUpdated,
      };

  factory PrecomputedActionDoc.fromJson(Map<String, dynamic> json) {
    Set<String> parseSet(String key) {
      final list = json[key] as List<dynamic>?;
      if (list == null) return <String>{};
      return list.map((e) => e.toString()).toSet();
    }

    final rawVotes = json['votes'] as Map<String, dynamic>? ?? {};
    final parsedVotes = <String, int>{};
    rawVotes.forEach((k, v) {
      if (v is int) {
        parsedVotes[k] = v;
      } else if (v is num) {
        parsedVotes[k] = v.toInt();
      }
    });

    return PrecomputedActionDoc(
      savedListingIds: parseSet('savedListingIds'),
      appliedJobIds: parseSet('appliedJobIds'),
      likedPostIds: parseSet('likedPostIds'),
      blockedUserIds: parseSet('blockedUserIds'),
      followingUserIds: parseSet('followingUserIds'),
      reportedIds: parseSet('reportedIds'),
      votes: parsedVotes,
      lastUpdated: (json['lastUpdated'] as num?)?.toInt() ?? 0,
    );
  }
}

/// ⚡ Phase 3: Action State Network & Disk Repository
class ActionStateRepository {
  static const String baseUrl = ApiConstants.baseUrl;

  /// No-op in 100% Online D1 Architecture (Disk caching removed)
  Future<PrecomputedActionDoc?> loadFromDisk() async => null;

  /// No-op in 100% Online D1 Architecture (Disk caching removed)
  Future<void> saveToDisk(PrecomputedActionDoc doc) async {}

  /// ⚡ Single-read fetch of current user precomputed action document from backend
  Future<PrecomputedActionDoc?> fetchCurrentActionDocument() async {
    final token = await AuthService.instance.getAccessToken();
    if (token == null || token.isEmpty) return null;

    final uri = Uri.parse('$baseUrl/actions/state/current?limit=500');
    try {
      final res = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final doc = PrecomputedActionDoc.fromJson(data);
        await saveToDisk(doc);
        return doc;
      }
    } catch (e) {
      debugPrint('[ActionStateRepository] fetchCurrentActionDocument error: $e');
    }
    return null;
  }

  /// Background write to synchronize button state change to backend
  Future<bool> syncActionMutation({
    required String targetId,
    String targetType = 'post',
    bool? isLiked,
    bool? isSaved,
    bool? isApplied,
    bool? isReported,
    bool? isBlocked,
    int? voteDirection,
  }) async {
    final token = await AuthService.instance.getAccessToken();
    if (token == null || token.isEmpty) return true;

    final uri = Uri.parse('$baseUrl/actions/states');
    try {
      final payload = <String, dynamic>{
        'target_id': targetId,
        'target_type': targetType,
      };
      if (isLiked != null) payload['is_liked'] = isLiked;
      if (isSaved != null) payload['is_saved'] = isSaved;
      if (isApplied != null) payload['is_applied'] = isApplied;
      if (isReported != null) payload['is_reported'] = isReported;
      if (isBlocked != null) payload['is_blocked'] = isBlocked;
      if (voteDirection != null) payload['vote_direction'] = voteDirection;

      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[ActionStateRepository] syncActionMutation error: $e');
      return false;
    }
  }

  /// Clears disk cache on logout (No-op in 100% online D1 architecture)
  Future<void> clearDisk() async {}
}
