import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/friend_request_model.dart';
import '../models/friendship_model.dart';
import '../models/block_model.dart';
import 'auth_service.dart';
import 'notification_service.dart';

enum RelationshipStatus {
  none,
  requestSentByMe,
  requestReceivedByMe,
  friends,
  blockedByMe,
  blockedByThem,
}

class FriendRepository {
  static final FriendRepository _singleton = FriendRepository._internal();
  factory FriendRepository() => _singleton;
  FriendRepository._internal();

  String _currentUserHandle = '';

  String get currentUserHandle {
    if (_currentUserHandle.isEmpty) {
      AuthService.instance.getUserHandle().then((h) {
        if (h != null && h.isNotEmpty) {
          _currentUserHandle = h.replaceAll('@', '').trim();
        }
      });
    }
    return _currentUserHandle;
  }

  set currentUserHandle(String handle) {
    _currentUserHandle = handle.replaceAll('@', '').trim();
  }

  // ── In-Memory Cache ──
  List<Friendship> _cachedFriends = [];
  List<FriendRequest> _cachedPendingRequests = [];
  List<FriendRequest> _cachedSentRequests = [];
  List<BlockEntry> _cachedBlocked = [];

  // ── Stream Controllers ──
  final _friendsController = StreamController<List<Friendship>>.broadcast();
  final _pendingRequestsController = StreamController<List<FriendRequest>>.broadcast();
  final _sentRequestsController = StreamController<List<FriendRequest>>.broadcast();
  final _blockedUsersController = StreamController<List<BlockEntry>>.broadcast();
  final _pendingCountController = StreamController<int>.broadcast();

  Timer? _pollingTimer;

  void _startPollingIfNeeded() {
    _pollingTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      refreshAll();
    });
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService.instance.getAccessToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ── Refresh all friend data from backend ──
  Future<void> refreshAll() async {
    try {
      await Future.wait([
        fetchFriends(),
        fetchRequests(),
        fetchBlocked(),
      ]);
    } catch (e) {
      debugPrint('[FriendRepository] Error refreshing data: $e');
    }
  }

  // ── Fetch Friends List ──
  Future<List<Friendship>> fetchFriends({int limit = 200}) async {
    final uri = Uri.parse('${AuthService.baseUrl}/friends?limit=$limit');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawList = data['friends'] as List? ?? [];
        _cachedFriends = rawList.map((item) {
          final map = item as Map<String, dynamic>;
          return Friendship.fromMap(map, map['id']?.toString() ?? '');
        }).toList();
        _friendsController.add(List.unmodifiable(_cachedFriends));
        return _cachedFriends;
      }
    } catch (e) {
      debugPrint('[FriendRepository] fetchFriends error: $e');
    }
    return _cachedFriends;
  }

  // ── Fetch Pending and Sent Requests ──
  Future<void> fetchRequests() async {
    final uri = Uri.parse('${AuthService.baseUrl}/friends/requests?type=all');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawRecv = data['received'] as List? ?? [];
        final rawSent = data['sent'] as List? ?? [];

        _cachedPendingRequests = rawRecv.map((item) {
          final map = item as Map<String, dynamic>;
          return FriendRequest.fromMap(map, map['id']?.toString() ?? '');
        }).toList();

        _cachedSentRequests = rawSent.map((item) {
          final map = item as Map<String, dynamic>;
          return FriendRequest.fromMap(map, map['id']?.toString() ?? '');
        }).toList();

        _pendingRequestsController.add(List.unmodifiable(_cachedPendingRequests));
        _sentRequestsController.add(List.unmodifiable(_cachedSentRequests));
        _pendingCountController.add(_cachedPendingRequests.length);
      }
    } catch (e) {
      debugPrint('[FriendRepository] fetchRequests error: $e');
    }
  }

  // ── Fetch Blocked Users ──
  Future<List<BlockEntry>> fetchBlocked() async {
    final uri = Uri.parse('${AuthService.baseUrl}/friends/blocked');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawList = data['blocked'] as List? ?? [];
        _cachedBlocked = rawList.map((item) {
          final map = item as Map<String, dynamic>;
          return BlockEntry.fromMap(map, map['id']?.toString() ?? '');
        }).toList();
        _blockedUsersController.add(List.unmodifiable(_cachedBlocked));
        return _cachedBlocked;
      }
    } catch (e) {
      debugPrint('[FriendRepository] fetchBlocked error: $e');
    }
    return _cachedBlocked;
  }

  // ── Check Relationship Status ──
  Future<RelationshipStatus> getRelationshipStatus(String otherHandle) async {
    final them = otherHandle.replaceAll('@', '').trim();
    if (them.isEmpty) return RelationshipStatus.none;

    final me = _currentUserHandle.replaceAll('@', '').trim();
    if (me.isNotEmpty && me.toLowerCase() == them.toLowerCase()) {
      return RelationshipStatus.none;
    }

    final uri = Uri.parse('${AuthService.baseUrl}/friends/status/$them');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final relStr = data['relationship']?.toString() ?? 'none';
        switch (relStr) {
          case 'friends':
            return RelationshipStatus.friends;
          case 'requestSentByMe':
            return RelationshipStatus.requestSentByMe;
          case 'requestReceivedByMe':
            return RelationshipStatus.requestReceivedByMe;
          case 'blockedByMe':
            return RelationshipStatus.blockedByMe;
          case 'blockedByThem':
            return RelationshipStatus.blockedByThem;
          default:
            return RelationshipStatus.none;
        }
      }
    } catch (e) {
      debugPrint('[FriendRepository] getRelationshipStatus error: $e');
    }
    return RelationshipStatus.none;
  }

  Future<bool> isBlocked(String otherHandle) async {
    final status = await getRelationshipStatus(otherHandle);
    return status == RelationshipStatus.blockedByMe || status == RelationshipStatus.blockedByThem;
  }

  // ── Send Friend Request ──
  Future<void> sendFriendRequest(String receiverHandle) async {
    final them = receiverHandle.replaceAll('@', '').trim();
    if (them.isEmpty) throw Exception('Target user not specified');

    final uri = Uri.parse('${AuthService.baseUrl}/friends/request');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'receiverHandle': them}),
    );

    if (res.statusCode == 200) {
      final me = _currentUserHandle.replaceAll('@', '').trim();
      _cachedSentRequests.insert(
        0,
        FriendRequest(
          id: '${me.toLowerCase()}_${them.toLowerCase()}',
          senderHandle: me,
          receiverHandle: them,
          status: FriendRequestStatus.pending,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      _sentRequestsController.add(List.unmodifiable(_cachedSentRequests));

      NotificationService().sendNotification(
        targetHandle: them,
        title: 'New Friend Request',
        body: '@$me sent you a friend request',
        data: {
          'type': 'friend_request',
          'senderHandle': me,
        },
      ).catchError((_) {});
    } else {
      final data = jsonDecode(res.body);
      final errorMsg = data['detail'] ?? data['error']?['message'] ?? 'Failed to send friend request';
      throw Exception(errorMsg);
    }
  }

  // ── Accept Friend Request ──
  Future<void> acceptFriendRequest(String senderHandle) async {
    final them = senderHandle.replaceAll('@', '').trim();
    if (them.isEmpty) return;

    final uri = Uri.parse('${AuthService.baseUrl}/friends/accept');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'senderHandle': them}),
    );

    if (res.statusCode == 200) {
      final me = _currentUserHandle.replaceAll('@', '').trim();
      _cachedPendingRequests.removeWhere((r) =>
          r.senderHandle.toLowerCase() == them.toLowerCase() ||
          r.receiverHandle.toLowerCase() == them.toLowerCase());
      _pendingRequestsController.add(List.unmodifiable(_cachedPendingRequests));
      _pendingCountController.add(_cachedPendingRequests.length);

      final newFriendship = Friendship(
        id: '${them.toLowerCase()}_${me.toLowerCase()}',
        users: [them, me],
        otherUser: them,
        createdAt: DateTime.now(),
      );
      _cachedFriends.insert(0, newFriendship);
      _friendsController.add(List.unmodifiable(_cachedFriends));

      NotificationService().sendNotification(
        targetHandle: them,
        title: 'Friend Request Accepted',
        body: '@$me accepted your friend request! Tap to start chatting.',
        data: {
          'type': 'chat',
          'partnerHandle': me,
          'senderHandle': me,
        },
      ).catchError((_) {});
    } else {
      final data = jsonDecode(res.body);
      final errorMsg = data['detail'] ?? data['error']?['message'] ?? 'Failed to accept friend request';
      throw Exception(errorMsg);
    }
  }

  // ── Reject Friend Request ──
  Future<void> rejectFriendRequest(String senderHandle) async {
    final them = senderHandle.replaceAll('@', '').trim();
    if (them.isEmpty) return;

    final uri = Uri.parse('${AuthService.baseUrl}/friends/reject');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'senderHandle': them}),
    );

    if (res.statusCode == 200) {
      _cachedPendingRequests.removeWhere((r) =>
          r.senderHandle.toLowerCase() == them.toLowerCase() ||
          r.receiverHandle.toLowerCase() == them.toLowerCase());
      _pendingRequestsController.add(List.unmodifiable(_cachedPendingRequests));
      _pendingCountController.add(_cachedPendingRequests.length);
    }
  }

  // ── Cancel Sent Request ──
  Future<void> cancelFriendRequest(String receiverHandle) async {
    final them = receiverHandle.replaceAll('@', '').trim();
    if (them.isEmpty) return;

    final uri = Uri.parse('${AuthService.baseUrl}/friends/cancel');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'receiverHandle': them}),
    );

    if (res.statusCode == 200) {
      _cachedSentRequests.removeWhere((r) =>
          r.receiverHandle.toLowerCase() == them.toLowerCase());
      _sentRequestsController.add(List.unmodifiable(_cachedSentRequests));
    }
  }

  // ── Unfriend ──
  Future<void> unfriend(String otherHandle) async {
    final them = otherHandle.replaceAll('@', '').trim();
    if (them.isEmpty) return;

    final uri = Uri.parse('${AuthService.baseUrl}/friends/unfriend');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'otherHandle': them}),
    );

    if (res.statusCode == 200) {
      _cachedFriends.removeWhere((f) =>
          (f.otherUser?.toLowerCase() == them.toLowerCase()) ||
          f.users.any((u) => u.toLowerCase() == them.toLowerCase()));
      _friendsController.add(List.unmodifiable(_cachedFriends));
    }
  }

  // ── Block User ──
  Future<void> blockUser(String otherHandle) async {
    final them = otherHandle.replaceAll('@', '').trim();
    if (them.isEmpty) return;

    final uri = Uri.parse('${AuthService.baseUrl}/friends/block');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'blockedHandle': them}),
    );

    if (res.statusCode == 200) {
      final me = _currentUserHandle.replaceAll('@', '').trim();
      _cachedFriends.removeWhere((f) =>
          (f.otherUser?.toLowerCase() == them.toLowerCase()) ||
          f.users.any((u) => u.toLowerCase() == them.toLowerCase()));
      _friendsController.add(List.unmodifiable(_cachedFriends));

      _cachedPendingRequests.removeWhere((r) =>
          r.senderHandle.toLowerCase() == them.toLowerCase() ||
          r.receiverHandle.toLowerCase() == them.toLowerCase());
      _pendingRequestsController.add(List.unmodifiable(_cachedPendingRequests));
      _pendingCountController.add(_cachedPendingRequests.length);

      _cachedSentRequests.removeWhere((r) =>
          r.receiverHandle.toLowerCase() == them.toLowerCase());
      _sentRequestsController.add(List.unmodifiable(_cachedSentRequests));

      _cachedBlocked.insert(
        0,
        BlockEntry(
          id: '${me.toLowerCase()}_${them.toLowerCase()}',
          blockerHandle: me,
          blockedHandle: them,
          createdAt: DateTime.now(),
        ),
      );
      _blockedUsersController.add(List.unmodifiable(_cachedBlocked));
    }
  }

  // ── Unblock User ──
  Future<void> unblockUser(String otherHandle) async {
    final them = otherHandle.replaceAll('@', '').trim();
    if (them.isEmpty) return;

    final uri = Uri.parse('${AuthService.baseUrl}/friends/unblock');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'blockedHandle': them}),
    );

    if (res.statusCode == 200) {
      _cachedBlocked.removeWhere((b) =>
          b.blockedHandle.toLowerCase() == them.toLowerCase());
      _blockedUsersController.add(List.unmodifiable(_cachedBlocked));
    }
  }

  // ── Get Incoming Pending Requests (Stream) ──
  Stream<List<FriendRequest>> getPendingRequests({int limit = 100}) {
    _startPollingIfNeeded();
    fetchRequests();
    Future.microtask(() {
      if (!_pendingRequestsController.isClosed) {
        _pendingRequestsController.add(List.unmodifiable(_cachedPendingRequests));
      }
    });
    return _pendingRequestsController.stream;
  }

  // ── Get Sent Pending Requests (Stream) ──
  Stream<List<FriendRequest>> getSentRequests({int limit = 100}) {
    _startPollingIfNeeded();
    fetchRequests();
    Future.microtask(() {
      if (!_sentRequestsController.isClosed) {
        _sentRequestsController.add(List.unmodifiable(_cachedSentRequests));
      }
    });
    return _sentRequestsController.stream;
  }

  // ── Get Friends List (Stream) ──
  Stream<List<Friendship>> getFriendsList({int limit = 200}) {
    _startPollingIfNeeded();
    fetchFriends(limit: limit);
    Future.microtask(() {
      if (!_friendsController.isClosed) {
        _friendsController.add(List.unmodifiable(_cachedFriends));
      }
    });
    return _friendsController.stream;
  }

  // ── Get Blocked Users List (Stream) ──
  Stream<List<BlockEntry>> getBlockedUsers({int limit = 100}) {
    _startPollingIfNeeded();
    fetchBlocked();
    Future.microtask(() {
      if (!_blockedUsersController.isClosed) {
        _blockedUsersController.add(List.unmodifiable(_cachedBlocked));
      }
    });
    return _blockedUsersController.stream;
  }

  // ── Get Pending Request Count (for badge) ──
  Stream<int> getPendingRequestCount() {
    _startPollingIfNeeded();
    fetchRequests();
    Future.microtask(() {
      if (!_pendingCountController.isClosed) {
        _pendingCountController.add(_cachedPendingRequests.length);
      }
    });
    return _pendingCountController.stream;
  }

  // ── Check if two users are friends ──
  Future<bool> areFriends(String otherHandle) async {
    final status = await getRelationshipStatus(otherHandle);
    return status == RelationshipStatus.friends;
  }

  // ── Helper: lookup user public profile by handle ──
  Future<Map<String, dynamic>?> getUserByHandle(String handle) async {
    final clean = handle.replaceAll('@', '').trim();
    if (clean.isEmpty) return null;

    final uri = Uri.parse('${AuthService.baseUrl}/auth/profile/$clean');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['user'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('[FriendRepository] getUserByHandle error: $e');
    }
    return null;
  }
}
