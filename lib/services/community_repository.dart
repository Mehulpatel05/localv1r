import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/community_model.dart';
import 'auth_service.dart';
import 'r2_storage_service.dart';

enum JoinStatus { joined, pending, error }

class JoinResult {
  final JoinStatus status;
  final String message;
  JoinResult({required this.status, required this.message});
}

class CommunityRepository {
  static final CommunityRepository _instance = CommunityRepository._internal();
  factory CommunityRepository() => _instance;
  CommunityRepository._internal();

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

  // ── Cache ──
  List<CommunityModel> _cachedUserCommunities = [];
  List<CommunityModel> _cachedDiscoverCommunities = [];
  final Map<String, List<CommunityMessage>> _cachedMessages = {};

  Set<String> get joinedCommunityIds => _cachedUserCommunities.map((c) => c.id).toSet();

  // ── Stream Controllers ──
  final _userCommunitiesCtrl = StreamController<List<CommunityModel>>.broadcast();
  final _discoverCommunitiesCtrl = StreamController<List<CommunityModel>>.broadcast();
  final _joinedIdsCtrl = StreamController<Set<String>>.broadcast();
  final Map<String, StreamController<List<CommunityMessage>>> _messageControllers = {};

  Timer? _pollingTimer;

  void _startPollingIfNeeded() {
    _pollingTimer ??= Timer.periodic(const Duration(seconds: 8), (_) {
      fetchUserCommunities();
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

  // ── Username Check ──
  Future<bool> checkUsernameAvailable(String username) async {
    final clean = username.replaceAll('@', '').trim();
    if (clean.length < 3) return false;
    final uri = Uri.parse('${AuthService.baseUrl}/communities/check-username?username=$clean');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['available'] == true;
      }
    } catch (_) {}
    return false;
  }

  // ── Fetch Joined Communities ──
  Future<List<CommunityModel>> fetchUserCommunities() async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities?filter=joined');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawList = data['communities'] as List? ?? [];
        _cachedUserCommunities = rawList.map((item) {
          final map = item as Map<String, dynamic>;
          return CommunityModel.fromMap(map, map['id']?.toString() ?? '');
        }).toList();
        _userCommunitiesCtrl.add(List.unmodifiable(_cachedUserCommunities));
        _joinedIdsCtrl.add(_cachedUserCommunities.map((c) => c.id).toSet());
        return _cachedUserCommunities;
      }
    } catch (e) {
      debugPrint('[CommunityRepository] fetchUserCommunities error: $e');
    }
    return _cachedUserCommunities;
  }

  // ── Fetch Public Directory / Discover ──
  Future<List<CommunityModel>> fetchDiscoverCommunities({String? query, String? type}) async {
    String url = '${AuthService.baseUrl}/communities?filter=discover';
    if (query != null && query.trim().length >= 2) {
      url += '&q=${Uri.encodeComponent(query.trim())}';
    }
    if (type != null) {
      url += '&type=$type';
    }
    final uri = Uri.parse(url);
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawList = data['communities'] as List? ?? [];
        _cachedDiscoverCommunities = rawList.map((item) {
          final map = item as Map<String, dynamic>;
          return CommunityModel.fromMap(map, map['id']?.toString() ?? '');
        }).toList();
        _discoverCommunitiesCtrl.add(List.unmodifiable(_cachedDiscoverCommunities));
        return _cachedDiscoverCommunities;
      }
    } catch (e) {
      debugPrint('[CommunityRepository] fetchDiscoverCommunities error: $e');
    }
    return _cachedDiscoverCommunities;
  }

  // ── Global Search (Joined + Public Directory) ──
  Future<Map<String, List<CommunityModel>>> searchCommunities(String query, {String? typeFilter}) async {
    final clean = query.trim().toLowerCase();
    if (clean.length < 2) {
      return {'joined': _cachedUserCommunities, 'public': []};
    }

    // Filter joined locally
    final filteredJoined = _cachedUserCommunities.where((c) {
      if (typeFilter == 'group' && c.isChannel) return false;
      if (typeFilter == 'channel' && !c.isChannel) return false;
      return c.name.toLowerCase().contains(clean) ||
          (c.username != null && c.username!.toLowerCase().contains(clean)) ||
          c.description.toLowerCase().contains(clean);
    }).toList();

    // Query backend for global public directory
    final publicResults = await fetchDiscoverCommunities(query: clean, type: typeFilter);
    return {
      'joined': filteredJoined,
      'public': publicResults,
    };
  }

  // ── Streams ──
  Stream<List<CommunityModel>> getUserCommunities() {
    _startPollingIfNeeded();
    fetchUserCommunities();
    Future.microtask(() {
      if (!_userCommunitiesCtrl.isClosed) {
        _userCommunitiesCtrl.add(List.unmodifiable(_cachedUserCommunities));
      }
    });
    return _userCommunitiesCtrl.stream;
  }

  Stream<Set<String>> getJoinedCommunityIds() {
    _startPollingIfNeeded();
    fetchUserCommunities();
    Future.microtask(() {
      if (!_joinedIdsCtrl.isClosed) {
        _joinedIdsCtrl.add(_cachedUserCommunities.map((c) => c.id).toSet());
      }
    });
    return _joinedIdsCtrl.stream;
  }

  Stream<List<CommunityModel>> getDiscoverCommunities() {
    fetchDiscoverCommunities();
    Future.microtask(() {
      if (!_discoverCommunitiesCtrl.isClosed) {
        _discoverCommunitiesCtrl.add(List.unmodifiable(_cachedDiscoverCommunities));
      }
    });
    return _discoverCommunitiesCtrl.stream;
  }

  Future<void> markAsRead(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/read');
    try {
      final headers = await _getAuthHeaders();
      await http.post(uri, headers: headers).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  // ── Fetch Community Messages ──
  Future<List<CommunityMessage>> fetchCommunityMessages(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages?limit=100');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawList = data['messages'] as List? ?? [];
        final messages = rawList.map((item) {
          final map = item as Map<String, dynamic>;
          return CommunityMessage.fromMap(map, map['id']?.toString() ?? '');
        }).toList();

        // Sort descending by timestamp (newest first for chat list view)
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _cachedMessages[communityId] = messages;

        final ctrl = _getOrCreateMessageController(communityId);
        ctrl.add(List.unmodifiable(messages));
        return messages;
      }
    } catch (e) {
      debugPrint('[CommunityRepository] fetchCommunityMessages error: $e');
    }
    return _cachedMessages[communityId] ?? [];
  }

  StreamController<List<CommunityMessage>> _getOrCreateMessageController(String communityId) {
    return _messageControllers.putIfAbsent(
      communityId,
      () => StreamController<List<CommunityMessage>>.broadcast(),
    );
  }

  Stream<List<CommunityMessage>> getCommunityMessages(String communityId) {
    final ctrl = _getOrCreateMessageController(communityId);
    fetchCommunityMessages(communityId);

    Timer.periodic(const Duration(seconds: 3), (timer) {
      if (ctrl.isClosed || !ctrl.hasListener) {
        timer.cancel();
      } else {
        fetchCommunityMessages(communityId);
      }
    });

    final cached = _cachedMessages[communityId] ?? [];
    Future.microtask(() {
      if (!ctrl.isClosed) {
        ctrl.add(List.unmodifiable(cached));
      }
    });

    return ctrl.stream;
  }

  // ── Create Community ──
  Future<String> createCommunity({
    required String name,
    required String description,
    required bool isChannel,
    String visibility = 'public',
    String? username,
    String? inviteLink,
    Map<String, dynamic>? settings,
    File? imageFile,
    List<String>? initialMembers,
  }) async {
    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await R2StorageService.uploadImage(imageFile);
    }

    final uri = Uri.parse('${AuthService.baseUrl}/communities');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'name': name.trim(),
        'description': description.trim(),
        'isChannel': isChannel,
        'visibility': visibility,
        if (username != null && username.isNotEmpty) 'username': username.trim().replaceAll('@', ''),
        'inviteLink': ?inviteLink,
        'settings': ?settings,
        'imageUrl': imageUrl,
        'initialMembers': ?initialMembers,
      }),
    );

    if (res.statusCode == 201) {
      final data = jsonDecode(res.body);
      await fetchUserCommunities();
      return data['communityId']?.toString() ?? '';
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to create community');
    }
  }

  // ── Update Community Settings ──
  Future<void> updateCommunitySettings({
    required String communityId,
    String? name,
    String? description,
    String? visibility,
    String? username,
    Map<String, dynamic>? settings,
    File? imageFile,
  }) async {
    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await R2StorageService.uploadImage(imageFile);
    }

    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId');
    final headers = await _getAuthHeaders();
    final payload = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (description != null) 'description': description.trim(),
      'imageUrl': ?imageUrl,
      'visibility': ?visibility,
      if (username != null && username.isNotEmpty) 'username': username.trim().replaceAll('@', ''),
      'settings': ?settings,
    };

    final res = await http.put(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );

    if (res.statusCode == 200) {
      await fetchUserCommunities();
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to update community settings');
    }
  }

  // ── Join Community ──
  Future<JoinResult> joinCommunity(String communityId, {String? inviteCode}) async {
    String url = '${AuthService.baseUrl}/communities/$communityId/join';
    if (inviteCode != null) {
      url += '?invite_code=${Uri.encodeComponent(inviteCode)}';
    }
    final uri = Uri.parse(url);
    final headers = await _getAuthHeaders();
    final res = await http.post(uri, headers: headers).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = jsonDecode(res.body);
      final statusStr = data['joinStatus']?.toString() ?? 'joined';
      final msg = data['message']?.toString() ?? 'Success';

      if (statusStr == 'pending') {
        return JoinResult(status: JoinStatus.pending, message: msg);
      } else {
        await fetchUserCommunities();
        await fetchDiscoverCommunities();
        return JoinResult(status: JoinStatus.joined, message: msg);
      }
    } else {
      String errMsg = 'Failed to join community';
      try {
        final data = jsonDecode(res.body);
        errMsg = data['detail'] ?? errMsg;
      } catch (_) {}
      return JoinResult(status: JoinStatus.error, message: errMsg);
    }
  }

  // ── Leave Community ──
  Future<void> leaveCommunity(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/leave');
    final headers = await _getAuthHeaders();
    final res = await http.post(uri, headers: headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200 || res.statusCode == 204) {
      _cachedUserCommunities.removeWhere((c) => c.id == communityId);
      _userCommunitiesCtrl.add(List.unmodifiable(_cachedUserCommunities));
      _joinedIdsCtrl.add(_cachedUserCommunities.map((c) => c.id).toSet());
      await fetchUserCommunities();
      await fetchDiscoverCommunities();
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to leave community');
    }
  }

  // ── Delete Entire Community (Owner Only) ──
  Future<void> deleteCommunity(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId');
    final headers = await _getAuthHeaders();
    final res = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200 || res.statusCode == 204) {
      _cachedUserCommunities.removeWhere((c) => c.id == communityId);
      _cachedDiscoverCommunities.removeWhere((c) => c.id == communityId);
      _userCommunitiesCtrl.add(List.unmodifiable(_cachedUserCommunities));
      _discoverCommunitiesCtrl.add(List.unmodifiable(_cachedDiscoverCommunities));
      _joinedIdsCtrl.add(_cachedUserCommunities.map((c) => c.id).toSet());
      await fetchUserCommunities();
      await fetchDiscoverCommunities();
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to delete community');
    }
  }

  // ── Regenerate / Revoke Invite Link ──
  Future<String> regenerateInviteLink(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/regenerate-invite-link');
    final headers = await _getAuthHeaders();
    final res = await http.post(uri, headers: headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await fetchUserCommunities();
      return data['inviteLink']?.toString() ?? '';
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to regenerate invite link');
    }
  }

  // ── Mute & Archive ──
  Future<void> muteCommunity(String communityId, int mutedUntil) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/mute');
    final headers = await _getAuthHeaders();
    await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'mutedUntil': mutedUntil}),
    );
    await fetchUserCommunities();
  }

  Future<void> archiveCommunity(String communityId, bool isArchived) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/archive');
    final headers = await _getAuthHeaders();
    await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'isArchived': isArchived}),
    );
    await fetchUserCommunities();
  }

  // ── Join Requests ──
  Future<List<Map<String, dynamic>>> getJoinRequests(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/requests');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['requests'] as List? ?? []).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<void> respondJoinRequest(String communityId, String requestId, bool approve) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/requests/$requestId/respond');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'approve': approve}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to respond to request');
    }
  }

  // ── Member Roles & Permissions ──
  Stream<List<Map<String, dynamic>>> getCommunityMembers(String communityId) async* {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/members');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final members = (data['members'] as List? ?? []).cast<Map<String, dynamic>>();
        yield members;
      }
    } catch (_) {
      yield [];
    }
  }

  Future<void> updateMemberRole(String communityId, String targetHandle, String role, Map<String, dynamic>? permissions) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/members/$targetHandle/role');
    final headers = await _getAuthHeaders();
    final res = await http.put(
      uri,
      headers: headers,
      body: jsonEncode({
        'role': role,
        'permissions': ?permissions,
      }),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to update member role');
    }
  }

  Future<void> transferOwnership(String communityId, String newOwnerHandle) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/transfer-ownership');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'newOwnerHandle': newOwnerHandle}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to transfer ownership');
    }
  }

  Future<void> removeMember(String communityId, String memberHandle) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/members/$memberHandle');
    final headers = await _getAuthHeaders();
    final res = await http.delete(uri, headers: headers);
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to remove member');
    }
  }

  // ── Send Messages ──
  Future<void> sendMessage(String communityId, String content) async {
    if (content.trim().isEmpty) return;
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'content': content.trim(),
        'type': 'text',
      }),
    );

    if (res.statusCode == 201) {
      fetchCommunityMessages(communityId);
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to send message');
    }
  }

  Future<void> sendImageMessage(
    String communityId,
    File imageFile, {
    String caption = '',
  }) async {
    final imageUrl = await R2StorageService.uploadImage(imageFile);
    if (imageUrl == null) throw Exception('Image upload failed.');

    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'content': caption.trim(),
        'imageUrl': imageUrl,
        'type': 'image',
      }),
    );

    if (res.statusCode == 201) {
      fetchCommunityMessages(communityId);
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to send image message');
    }
  }

  Future<void> sendImageGroupMessage(
    String communityId,
    List<File> imageFiles, {
    String caption = '',
  }) async {
    if (imageFiles.isEmpty) return;

    final uploadFutures = imageFiles.map((f) => R2StorageService.uploadMedia(f));
    final uploadedUrls = await Future.wait(uploadFutures);
    final validUrls = uploadedUrls.whereType<String>().toList();

    if (validUrls.isEmpty) throw Exception('Media upload failed.');

    final isVideo = validUrls.length == 1 && R2StorageService.isVideoFile(validUrls.first);

    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'content': caption.trim(),
        'imageUrl': validUrls.first,
        'mediaUrls': validUrls,
        'type': isVideo ? 'video' : (validUrls.length > 1 ? 'image_group' : 'image'),
      }),
    );

    if (res.statusCode == 201) {
      fetchCommunityMessages(communityId);
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to send media group');
    }
  }

  Future<void> editMessage(String communityId, String messageId, String newContent) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages/$messageId');
    final headers = await _getAuthHeaders();
    final res = await http.put(
      uri,
      headers: headers,
      body: jsonEncode({'content': newContent.trim()}),
    );
    if (res.statusCode == 200) {
      fetchCommunityMessages(communityId);
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to edit message');
    }
  }

  Future<void> deleteMessage(String communityId, String messageId, {String mode = 'everyone'}) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages/$messageId?mode=$mode');
    final headers = await _getAuthHeaders();
    final res = await http.delete(uri, headers: headers);
    if (res.statusCode == 200) {
      fetchCommunityMessages(communityId);
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to delete message');
    }
  }

  Future<void> pinMessage(String communityId, String messageId, bool pin) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages/$messageId/pin');
    final headers = await _getAuthHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'pin': pin}),
    );
    if (res.statusCode == 200) {
      fetchCommunityMessages(communityId);
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to pin message');
    }
  }

  Future<CommunityModel?> getCommunityById(String communityId) async {
    final cached = _cachedUserCommunities.where((c) => c.id == communityId).firstOrNull ??
                   _cachedDiscoverCommunities.where((c) => c.id == communityId).firstOrNull;
    if (cached != null) return cached;

    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final comm = data['community'] as Map<String, dynamic>?;
        if (comm != null) {
          return CommunityModel.fromMap(comm, comm['id']?.toString() ?? communityId);
        }
      }
    } catch (e) {
      debugPrint('[CommunityRepository] getCommunityById error: $e');
    }
    return null;
  }

  // ── Compatibility Helpers ──
  Future<List<CommunityModel>> fetchAllCommunities() async {
    return fetchDiscoverCommunities();
  }

  Stream<List<CommunityModel>> getAllCommunities() {
    return getDiscoverCommunities();
  }

  Future<void> transferAdmin(String communityId, String newAdminHandle) async {
    return transferOwnership(communityId, newAdminHandle);
  }

  Future<void> editCommunity({
    required String communityId,
    required String name,
    required String description,
    File? imageFile,
  }) async {
    return updateCommunitySettings(
      communityId: communityId,
      name: name,
      description: description,
      imageFile: imageFile,
    );
  }

  Future<void> toggleReaction(String messageId, String emoji, {String? communityId}) async {
    final cid = communityId ?? 'default';
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$cid/messages/$messageId/react');
    try {
      final headers = await _getAuthHeaders();
      await http.post(uri, headers: headers, body: jsonEncode({'emoji': emoji}));
      if (communityId != null) {
        fetchCommunityMessages(communityId);
      }
    } catch (_) {}
  }

  bool isMemberCached(String communityId) {
    return _cachedUserCommunities.any((c) => c.id == communityId);
  }

  Future<bool> isMember(String communityId) async {
    if (isMemberCached(communityId)) return true;
    final list = await fetchUserCommunities();
    return list.any((c) => c.id == communityId);
  }
}