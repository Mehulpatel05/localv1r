import 'dart:async';
import 'package:flutter/foundation.dart';
import 'action_state_repository.dart';

/// ⚡ Phase 3: Global In-Memory Action State Provider (O(1) Button Possibility Lookup Engine)
class ActionStateProvider extends ChangeNotifier {
  static final ActionStateProvider _instance = ActionStateProvider._internal();
  factory ActionStateProvider() => _instance;
  static ActionStateProvider get instance => _instance;

  final ActionStateRepository _repository;

  ActionStateProvider._internal({ActionStateRepository? repository})
      : _repository = repository ?? ActionStateRepository();

  // Hot in-memory Set<String> caches for 0ms O(1) lookups
  final Set<String> _savedListingIds = {};
  final Set<String> _appliedJobIds = {};
  final Set<String> _likedPostIds = {};
  final Set<String> _blockedUserIds = {};
  final Set<String> _followingUserIds = {};
  final Set<String> _reportedIds = {};
  final Map<String, int> _votes = {};
  int _lastUpdated = 0;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  int get lastUpdated => _lastUpdated;

  // Maximum threshold for in-memory hot sets (Hot vs Cold data split)
  static const int kHotSetThreshold = 500;

  void _applyDocument(PrecomputedActionDoc doc, {bool notify = true}) {
    _savedListingIds
      ..clear()
      ..addAll(doc.savedListingIds);

    _appliedJobIds
      ..clear()
      ..addAll(doc.appliedJobIds);

    _likedPostIds
      ..clear()
      ..addAll(doc.likedPostIds);

    _blockedUserIds
      ..clear()
      ..addAll(doc.blockedUserIds);

    _followingUserIds
      ..clear()
      ..addAll(doc.followingUserIds);

    _reportedIds
      ..clear()
      ..addAll(doc.reportedIds);

    _votes
      ..clear()
      ..addAll(doc.votes);

    _lastUpdated = doc.lastUpdated;
    if (notify) notifyListeners();
  }

  PrecomputedActionDoc toDoc() => PrecomputedActionDoc(
        savedListingIds: Set.from(_savedListingIds),
        appliedJobIds: Set.from(_appliedJobIds),
        likedPostIds: Set.from(_likedPostIds),
        blockedUserIds: Set.from(_blockedUserIds),
        followingUserIds: Set.from(_followingUserIds),
        reportedIds: Set.from(_reportedIds),
        votes: Map.from(_votes),
        lastUpdated: _lastUpdated,
      );

  // ── 0ms Synchronous O(1) Read Methods ──

  bool isSaved(String targetId) => _savedListingIds.contains(targetId);
  bool isApplied(String targetId) => _appliedJobIds.contains(targetId);
  bool isLiked(String targetId) => _likedPostIds.contains(targetId);
  bool isBlocked(String targetUidOrHandle) => _blockedUserIds.contains(targetUidOrHandle);
  bool isFollowing(String targetUidOrHandle) => _followingUserIds.contains(targetUidOrHandle);
  bool isReported(String targetId) => _reportedIds.contains(targetId);
  int getVote(String targetId) => _votes[targetId] ?? 0;

  // ── ⚡ Phase 2 Stage B Integration: Single-Read Refresh ──

  Future<void> prefetchActionStateDocument() async {
    final doc = await _repository.fetchCurrentActionDocument();
    if (doc != null) {
      _applyDocument(doc, notify: true);
      _isInitialized = true;
    }
  }

  // ── Optimistic Write Mutators (0ms UI Feedback + Background D1 Sync) ──

  /// Toggle Saved / Bookmark State
  void toggleSaved(String targetId, {String targetType = 'post'}) {
    final currentlySaved = _savedListingIds.contains(targetId);
    if (currentlySaved) {
      _savedListingIds.remove(targetId);
    } else {
      if (_savedListingIds.length >= kHotSetThreshold) {
        _savedListingIds.remove(_savedListingIds.first); // Evict oldest hot item
      }
      _savedListingIds.add(targetId);
    }
    _lastUpdated = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    notifyListeners();

    // Background write with optimistic rollback
    _repository.syncActionMutation(
      targetId: targetId,
      targetType: targetType,
      isSaved: !currentlySaved,
    ).then((success) {
      if (!success) {
        if (currentlySaved) {
          _savedListingIds.add(targetId);
        } else {
          _savedListingIds.remove(targetId);
        }
        notifyListeners();
      }
    });
  }

  /// Toggle Liked State
  void toggleLiked(String targetId, {String targetType = 'post'}) {
    final currentlyLiked = _likedPostIds.contains(targetId);
    if (currentlyLiked) {
      _likedPostIds.remove(targetId);
    } else {
      if (_likedPostIds.length >= kHotSetThreshold) {
        _likedPostIds.remove(_likedPostIds.first);
      }
      _likedPostIds.add(targetId);
    }
    _lastUpdated = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    notifyListeners();

    // Background write with optimistic rollback
    _repository.syncActionMutation(
      targetId: targetId,
      targetType: targetType,
      isLiked: !currentlyLiked,
    ).then((success) {
      if (!success) {
        if (currentlyLiked) {
          _likedPostIds.add(targetId);
        } else {
          _likedPostIds.remove(targetId);
        }
        notifyListeners();
      }
    });
  }

  /// Mark Job as Applied
  void markApplied(String targetId, {String targetType = 'job'}) {
    if (_appliedJobIds.contains(targetId)) return;

    if (_appliedJobIds.length >= kHotSetThreshold) {
      _appliedJobIds.remove(_appliedJobIds.first);
    }
    _appliedJobIds.add(targetId);
    _lastUpdated = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    notifyListeners();

    // Background write with optimistic rollback
    _repository.syncActionMutation(
      targetId: targetId,
      targetType: targetType,
      isApplied: true,
    ).then((success) {
      if (!success) {
        _appliedJobIds.remove(targetId);
        notifyListeners();
      }
    });
  }

  /// Mark Target as Reported
  void markReported(String targetId, {String targetType = 'post'}) {
    _reportedIds.add(targetId);
    _lastUpdated = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    notifyListeners();

    // Background write with optimistic rollback
    _repository.syncActionMutation(
      targetId: targetId,
      targetType: targetType,
      isReported: true,
    ).then((success) {
      if (!success) {
        _reportedIds.remove(targetId);
        notifyListeners();
      }
    });
  }

  /// Toggle Blocked User State
  void toggleBlocked(String targetUidOrHandle) {
    final currentlyBlocked = _blockedUserIds.contains(targetUidOrHandle);
    if (currentlyBlocked) {
      _blockedUserIds.remove(targetUidOrHandle);
    } else {
      _blockedUserIds.add(targetUidOrHandle);
    }
    _lastUpdated = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    notifyListeners();

    // Background write with optimistic rollback
    _repository.syncActionMutation(
      targetId: targetUidOrHandle,
      targetType: 'user',
      isBlocked: !currentlyBlocked,
    ).then((success) {
      if (!success) {
        if (currentlyBlocked) {
          _blockedUserIds.add(targetUidOrHandle);
        } else {
          _blockedUserIds.remove(targetUidOrHandle);
        }
        notifyListeners();
      }
    });
  }

  /// Set Vote Direction (+1, -1, 0)
  void setVote(String targetId, int direction, {String targetType = 'post'}) {
    final oldVote = _votes[targetId] ?? 0;
    if (direction == 0) {
      _votes.remove(targetId);
    } else {
      _votes[targetId] = direction;
    }
    _lastUpdated = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    notifyListeners();

    // Background write with optimistic rollback
    _repository.syncActionMutation(
      targetId: targetId,
      targetType: targetType,
      voteDirection: direction,
    ).then((success) {
      if (!success) {
        if (oldVote == 0) {
          _votes.remove(targetId);
        } else {
          _votes[targetId] = oldVote;
        }
        notifyListeners();
      }
    });
  }

  /// Reset all in-memory and disk caches on logout
  void clear() {
    _savedListingIds.clear();
    _appliedJobIds.clear();
    _likedPostIds.clear();
    _blockedUserIds.clear();
    _followingUserIds.clear();
    _reportedIds.clear();
    _votes.clear();
    _lastUpdated = 0;
    _isInitialized = false;
    _repository.clearDisk();
    notifyListeners();
  }
}
