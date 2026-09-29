import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';
import 'auth_service.dart';

class UserActionState {
  final bool isLiked;
  final bool isSaved;
  final bool isApplied;
  final bool isReported;
  final bool isBlocked;
  final int voteDirection;
  final int? updatedAt;

  const UserActionState({
    this.isLiked = false,
    this.isSaved = false,
    this.isApplied = false,
    this.isReported = false,
    this.isBlocked = false,
    this.voteDirection = 0,
    this.updatedAt,
  });

  UserActionState copyWith({
    bool? isLiked,
    bool? isSaved,
    bool? isApplied,
    bool? isReported,
    bool? isBlocked,
    int? voteDirection,
    int? updatedAt,
  }) {
    return UserActionState(
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      isApplied: isApplied ?? this.isApplied,
      isReported: isReported ?? this.isReported,
      isBlocked: isBlocked ?? this.isBlocked,
      voteDirection: voteDirection ?? this.voteDirection,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'isLiked': isLiked,
        'isSaved': isSaved,
        'isApplied': isApplied,
        'isReported': isReported,
        'isBlocked': isBlocked,
        'voteDirection': voteDirection,
        'updatedAt': updatedAt,
      };

  factory UserActionState.fromJson(Map<String, dynamic> json) => UserActionState(
        isLiked: json['isLiked'] == true || json['isLiked'] == 1,
        isSaved: json['isSaved'] == true || json['isSaved'] == 1,
        isApplied: json['isApplied'] == true || json['isApplied'] == 1,
        isReported: json['isReported'] == true || json['isReported'] == 1,
        isBlocked: json['isBlocked'] == true || json['isBlocked'] == 1,
        voteDirection: json['voteDirection'] is int ? json['voteDirection'] : 0,
        updatedAt: json['updatedAt'] is int ? json['updatedAt'] : null,
      );
}

/// ⚡ Phase 0 Instagram Architectural Pattern:
/// Precomputed button states (Saved, Applied, Liked, Blocked, Voted) cached in-memory and disk
/// for 0ms instantaneous UI render without querying multiple backend collections.
class UserActionStateService extends ChangeNotifier {
  static final UserActionStateService _instance = UserActionStateService._internal();
  factory UserActionStateService() => _instance;
  static UserActionStateService get instance => _instance;

  UserActionStateService._internal();

  static const String baseUrl = ApiConstants.baseUrl;
  final Map<String, UserActionState> _cache = {};

  // 0ms Synchronous Lookups
  UserActionState getState(String targetId) => _cache[targetId] ?? const UserActionState();
  bool isLiked(String targetId) => _cache[targetId]?.isLiked ?? false;
  bool isSaved(String targetId) => _cache[targetId]?.isSaved ?? false;
  bool isApplied(String targetId) => _cache[targetId]?.isApplied ?? false;
  bool isReported(String targetId) => _cache[targetId]?.isReported ?? false;
  bool isBlocked(String targetId) => _cache[targetId]?.isBlocked ?? false;
  int getVote(String targetId) => _cache[targetId]?.voteDirection ?? 0;

  /// 🚀 Hydrates batch of target IDs in 1 single network call at read-time
  Future<void> fetchBatch(List<String> targetIds) async {
    if (targetIds.isEmpty) return;
    final token = await AuthService.instance.getAccessToken();
    if (token == null || token.isEmpty) return;

    final uri = Uri.parse('$baseUrl/actions/states/batch');
    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'target_ids': targetIds}),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final Map<String, dynamic> states = body['states'] ?? {};
        states.forEach((targetId, stateData) {
          if (stateData is Map<String, dynamic>) {
            _cache[targetId] = UserActionState.fromJson(stateData);
          }
        });
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[UserActionStateService] fetchBatch error: $e');
    }
  }

  /// 🚀 Optimistic Write-Time Action State Mutator (Synced to D1)
  Future<bool> setActionState({
    required String targetId,
    String targetType = 'post',
    bool? isLiked,
    bool? isSaved,
    bool? isApplied,
    bool? isReported,
    bool? isBlocked,
    int? voteDirection,
  }) async {
    // 1. In-memory update for current active session
    final existing = getState(targetId);
    final updated = existing.copyWith(
      isLiked: isLiked,
      isSaved: isSaved,
      isApplied: isApplied,
      isReported: isReported,
      isBlocked: isBlocked,
      voteDirection: voteDirection,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    _cache[targetId] = updated;
    notifyListeners();

    // 2. Direct online synchronization with Cloudflare D1
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
      );
      if (res.statusCode == 200) {
        return true;
      } else {
        _cache[targetId] = existing;
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('[UserActionStateService] sync error: $e');
      _cache[targetId] = existing;
      notifyListeners();
      return false;
    }
  }

  void clear() {
    _cache.clear();
    notifyListeners();
  }
}
