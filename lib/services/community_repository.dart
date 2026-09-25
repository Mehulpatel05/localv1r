import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

  CommunityRepository._internal() {
    _initPersistenceAndHandle();
  }

  String _currentUserHandle = '';

  String get currentUserHandle {
    if (_currentUserHandle.isEmpty) {
      _initPersistenceAndHandle();
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

  List<CommunityModel> get cachedUserCommunities => List.unmodifiable(_cachedUserCommunities);
  Set<String> get joinedCommunityIds => _cachedUserCommunities.map((c) => c.id).toSet();

  bool isMemberCached(String communityId) {
    return _cachedUserCommunities.any((c) => c.id == communityId);
  }

  // ── Stream Controllers ──
  final _userCommunitiesCtrl = StreamController<List<CommunityModel>>.broadcast();
  final _discoverCommunitiesCtrl = StreamController<List<CommunityModel>>.broadcast();
  final _joinedIdsCtrl = StreamController<Set<String>>.broadcast();
  final Map<String, StreamController<List<CommunityMessage>>> _messageControllers = {};

  Timer? _pollingTimer;

  static const String _kLocalJoinedListKey = 'community_cached_user_list';

  Future<void> _initPersistenceAndHandle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedHandle = prefs.getString('user_handle');
      if (savedHandle != null && savedHandle.isNotEmpty) {
        _currentUserHandle = savedHandle.replaceAll('@', '').trim();
      }

      final secHandle = await AuthService.instance.getUserHandle();
      if (secHandle != null && secHandle.isNotEmpty) {
        _currentUserHandle = secHandle.replaceAll('@', '').trim();
      }

      // Restore cached communities from disk for 0ms startup (scoped strictly to active user)
      if (_currentUserHandle.isNotEmpty) {
        final cacheKey = '${_kLocalJoinedListKey}_${_currentUserHandle.toLowerCase()}';
        final cachedJson = prefs.getString(cacheKey);
        if (cachedJson != null && cachedJson.isNotEmpty) {
          final List<dynamic> list = jsonDecode(cachedJson);
          final restored = list.map((item) {
            final map = item as Map<String, dynamic>;
            return CommunityModel.fromMap(map, map['id']?.toString() ?? '');
          }).toList();

          if (restored.isNotEmpty && _cachedUserCommunities.isEmpty) {
            _cachedUserCommunities = restored;
            _userCommunitiesCtrl.add(List.unmodifiable(_cachedUserCommunities));
            _joinedIdsCtrl.add(_cachedUserCommunities.map((c) => c.id).toSet());
          }
        }
      }
    } catch (e) {
      debugPrint('[CommunityRepository] _initPersistence error: $e');
    }
  }

  Future<void> _saveUserCommunitiesToPrefs() async {
    try {
      if (_currentUserHandle.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '${_kLocalJoinedListKey}_${_currentUserHandle.toLowerCase()}';
      final listMap = _cachedUserCommunities.map((c) => c.toMap()).toList();
      await prefs.setString(cacheKey, jsonEncode(listMap));
    } catch (_) {}
  }

  void clearLocalCache() {
    _currentUserHandle = '';
    _cachedUserCommunities = [];
    _cachedDiscoverCommunities = [];
    _cachedMessages.clear();
    _userCommunitiesCtrl.add([]);
    _discoverCommunitiesCtrl.add([]);
    _joinedIdsCtrl.add({});
  }

  void _startPollingIfNeeded() {
    _pollingTimer ??= Timer.periodic(const Duration(seconds: 8), (_) {
      fetchUserCommunities();
    });
  }

  Future<Map<String, String>> _getAuthHeaders({bool refresh = false}) async {
    String? token;
    if (refresh) {
      token = await AuthService.instance.refreshToken();
    } else {
      token = await AuthService.instance.getAccessToken();
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ── Unified Authenticated Network Helpers with Auto 401 Token Refresh ──
  Future<http.Response?> _authedGet(Uri uri, {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      var headers = await _getAuthHeaders();
      var res = await http.get(uri, headers: headers).timeout(timeout);
      if (res.statusCode == 401) {
        headers = await _getAuthHeaders(refresh: true);
        res = await http.get(uri, headers: headers).timeout(timeout);
      }
      return res;
    } catch (e) {
      debugPrint('[CommunityRepository] GET $uri error: $e');
      return null;
    }
  }

  Future<http.Response?> _authedPost(Uri uri, {Object? body, Duration timeout = const Duration(seconds: 15)}) async {
    try {
      var headers = await _getAuthHeaders();
      var res = await http.post(uri, headers: headers, body: body).timeout(timeout);
      if (res.statusCode == 401) {
        headers = await _getAuthHeaders(refresh: true);
        res = await http.post(uri, headers: headers, body: body).timeout(timeout);
      }
      return res;
    } catch (e) {
      debugPrint('[CommunityRepository] POST $uri error: $e');
      return null;
    }
  }

  Future<http.Response?> _authedPut(Uri uri, {Object? body, Duration timeout = const Duration(seconds: 15)}) async {
    try {
      var headers = await _getAuthHeaders();
      var res = await http.put(uri, headers: headers, body: body).timeout(timeout);
      if (res.statusCode == 401) {
        headers = await _getAuthHeaders(refresh: true);
        res = await http.put(uri, headers: headers, body: body).timeout(timeout);
      }
      return res;
    } catch (e) {
      debugPrint('[CommunityRepository] PUT $uri error: $e');
      return null;
    }
  }

  Future<http.Response?> _authedDelete(Uri uri, {Object? body, Duration timeout = const Duration(seconds: 15)}) async {
    try {
      var headers = await _getAuthHeaders();
      var res = await http.delete(uri, headers: headers, body: body).timeout(timeout);
      if (res.statusCode == 401) {
        headers = await _getAuthHeaders(refresh: true);
        res = await http.delete(uri, headers: headers, body: body).timeout(timeout);
      }
      return res;
    } catch (e) {
      debugPrint('[CommunityRepository] DELETE $uri error: $e');
      return null;
    }
  }

  String _extractErrorMessage(dynamic body, String defaultMsg) {
    try {
      if (body is String) {
        final data = jsonDecode(body);
        if (data is Map<String, dynamic>) {
          if (data['error'] is Map && data['error']['message'] != null) {
            return data['error']['message'].toString();
          }
          if (data['detail'] != null) {
            return data['detail'].toString();
          }
          if (data['message'] != null) {
            return data['message'].toString();
          }
        }
      }
    } catch (_) {}
    return defaultMsg;
  }

  // ── Username Check ──
  Future<bool> checkUsernameAvailable(String username) async {
    final clean = username.replaceAll('@', '').trim();
    if (clean.length < 3) return false;
    final uri = Uri.parse('${AuthService.baseUrl}/communities/check-username?username=$clean');
    final res = await _authedGet(uri, timeout: const Duration(seconds: 5));
    if (res != null && res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        return data['available'] == true;
      } catch (_) {}
    }
    return false;
  }

  // ── Fetch Joined Communities ──
  Future<List<CommunityModel>> fetchUserCommunities() async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities?filter=joined');
    final res = await _authedGet(uri, timeout: const Duration(seconds: 10));
    if (res != null && res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        final rawList = data['communities'] as List? ?? [];
        _cachedUserCommunities = rawList.map((item) {
          final map = item as Map<String, dynamic>;
          return CommunityModel.fromMap(map, map['id']?.toString() ?? '');
        }).toList();
        _userCommunitiesCtrl.add(List.unmodifiable(_cachedUserCommunities));
        _joinedIdsCtrl.add(_cachedUserCommunities.map((c) => c.id).toSet());
        _saveUserCommunitiesToPrefs();
        return _cachedUserCommunities;
      } catch (e) {
        debugPrint('[CommunityRepository] fetchUserCommunities parse error: $e');
      }
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
    final res = await _authedGet(uri, timeout: const Duration(seconds: 10));
    if (res != null && res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        final rawList = data['communities'] as List? ?? [];
        _cachedDiscoverCommunities = rawList.map((item) {
          final map = item as Map<String, dynamic>;
          return CommunityModel.fromMap(map, map['id']?.toString() ?? '');
        }).toList();
        _discoverCommunitiesCtrl.add(List.unmodifiable(_cachedDiscoverCommunities));
        return _cachedDiscoverCommunities;
      } catch (e) {
        debugPrint('[CommunityRepository] fetchDiscoverCommunities parse error: $e');
      }
    }
    return _cachedDiscoverCommunities;
  }

  // ── Global Search (Joined + Public Directory) ──
  Future<Map<String, List<CommunityModel>>> searchCommunities(String query, {String? typeFilter}) async {
    final clean = query.trim().toLowerCase();
    if (clean.length < 2) {
      return {'joined': _cachedUserCommunities, 'public': []};
    }

    final filteredJoined = _cachedUserCommunities.where((c) {
      if (typeFilter == 'group' && c.isChannel) return false;
      if (typeFilter == 'channel' && !c.isChannel) return false;
      return c.name.toLowerCase().contains(clean) ||
          (c.username != null && c.username!.toLowerCase().contains(clean)) ||
          c.description.toLowerCase().contains(clean);
    }).toList();

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
    final index = _cachedUserCommunities.indexWhere((c) => c.id == communityId);
    if (index != -1) {
      final old = _cachedUserCommunities[index];
      if (old.unreadCount > 0) {
        _cachedUserCommunities[index] = old.copyWith(unreadCount: 0);
        _userCommunitiesCtrl.add(List.unmodifiable(_cachedUserCommunities));
        _saveUserCommunitiesToPrefs();
      }
    }

    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/read');
    await _authedPost(uri, timeout: const Duration(seconds: 5));
  }

  // ── Fetch Community Messages ──
  Future<List<CommunityMessage>> fetchCommunityMessages(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages?limit=100');
    final res = await _authedGet(uri, timeout: const Duration(seconds: 10));
    if (res != null && res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        final rawList = data['messages'] as List? ?? [];
        final messages = rawList.map((item) {
          final map = item as Map<String, dynamic>;
          return CommunityMessage.fromMap(map, map['id']?.toString() ?? '');
        }).toList();

        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _cachedMessages[communityId] = messages;

        final ctrl = _getOrCreateMessageController(communityId);
        ctrl.add(List.unmodifiable(messages));
        return messages;
      } catch (e) {
        debugPrint('[CommunityRepository] fetchCommunityMessages parse error: $e');
      }
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
    final res = await _authedPost(
      uri,
      body: jsonEncode({
        'name': name.trim(),
        'description': description.trim(),
        'isChannel': isChannel,
        'visibility': visibility,
        if (username != null && username.isNotEmpty) 'username': username.trim().replaceAll('@', ''),
        'inviteLink': inviteLink,
        'settings': settings,
        'imageUrl': imageUrl,
        'initialMembers': initialMembers,
      }),
    );

    if (res != null && (res.statusCode == 201 || res.statusCode == 200)) {
      final data = jsonDecode(res.body);
      final newId = data['communityId']?.toString() ?? '';

      final newModel = CommunityModel(
        id: newId,
        name: name.trim(),
        description: description.trim(),
        isChannel: isChannel,
        adminHandle: currentUserHandle,
        ownerHandle: currentUserHandle,
        visibility: visibility,
        username: (username != null && username.isNotEmpty) ? username.trim().replaceAll('@', '') : null,
        inviteLink: inviteLink,
        settings: settings ?? {},
        memberCount: 1 + (initialMembers?.length ?? 0),
        imageUrl: imageUrl,
        myRole: 'owner',
        unreadCount: 0,
        createdAt: DateTime.now(),
      );
      _cachedUserCommunities.removeWhere((c) => c.id == newId);
      _cachedUserCommunities.insert(0, newModel);
      _userCommunitiesCtrl.add(List.unmodifiable(_cachedUserCommunities));
      _joinedIdsCtrl.add(_cachedUserCommunities.map((c) => c.id).toSet());
      _saveUserCommunitiesToPrefs();

      fetchUserCommunities();
      return newId;
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to create community') : 'Network error';
      throw Exception(errMsg);
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
    final payload = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (description != null) 'description': description.trim(),
      'imageUrl': imageUrl,
      'visibility': visibility,
      if (username != null && username.isNotEmpty) 'username': username.trim().replaceAll('@', ''),
      'settings': settings,
    };

    final res = await _authedPut(uri, body: jsonEncode(payload));
    if (res != null && res.statusCode == 200) {
      await fetchUserCommunities();
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to update settings') : 'Network error';
      throw Exception(errMsg);
    }
  }

  // ── Join Community ──
  Future<JoinResult> joinCommunity(String communityId, {String? inviteCode}) async {
    String url = '${AuthService.baseUrl}/communities/$communityId/join';
    if (inviteCode != null) {
      url += '?invite_code=${Uri.encodeComponent(inviteCode)}';
    }
    final uri = Uri.parse(url);
    final res = await _authedPost(uri, timeout: const Duration(seconds: 10));

    if (res != null && (res.statusCode == 200 || res.statusCode == 201)) {
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
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to join community') : 'Network error';
      return JoinResult(status: JoinStatus.error, message: errMsg);
    }
  }

  // ── Leave Community ──
  Future<void> leaveCommunity(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/leave');
    final res = await _authedPost(uri, timeout: const Duration(seconds: 10));
    if (res != null && (res.statusCode == 200 || res.statusCode == 204)) {
      _cachedUserCommunities.removeWhere((c) => c.id == communityId);
      _userCommunitiesCtrl.add(List.unmodifiable(_cachedUserCommunities));
      _joinedIdsCtrl.add(_cachedUserCommunities.map((c) => c.id).toSet());
      _saveUserCommunitiesToPrefs();
      await fetchUserCommunities();
      await fetchDiscoverCommunities();
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to leave community') : 'Network error';
      throw Exception(errMsg);
    }
  }

  // ── Delete Entire Community (Owner Only) ──
  Future<void> deleteCommunity(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId');
    final res = await _authedDelete(uri, timeout: const Duration(seconds: 10));
    if (res != null && (res.statusCode == 200 || res.statusCode == 204)) {
      _cachedUserCommunities.removeWhere((c) => c.id == communityId);
      _cachedDiscoverCommunities.removeWhere((c) => c.id == communityId);
      _userCommunitiesCtrl.add(List.unmodifiable(_cachedUserCommunities));
      _discoverCommunitiesCtrl.add(List.unmodifiable(_cachedDiscoverCommunities));
      _joinedIdsCtrl.add(_cachedUserCommunities.map((c) => c.id).toSet());
      _saveUserCommunitiesToPrefs();
      await fetchUserCommunities();
      await fetchDiscoverCommunities();
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to delete community') : 'Network error';
      throw Exception(errMsg);
    }
  }

  // ── Regenerate / Revoke Invite Link ──
  Future<String> regenerateInviteLink(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/regenerate-invite-link');
    final res = await _authedPost(uri, timeout: const Duration(seconds: 10));
    if (res != null && res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await fetchUserCommunities();
      return data['inviteLink']?.toString() ?? '';
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to regenerate invite link') : 'Network error';
      throw Exception(errMsg);
    }
  }

  // ── Mute & Archive ──
  Future<void> muteCommunity(String communityId, int mutedUntil) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/mute');
    await _authedPost(uri, body: jsonEncode({'mutedUntil': mutedUntil}));
    await fetchUserCommunities();
  }

  Future<void> archiveCommunity(String communityId, bool isArchived) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/archive');
    await _authedPost(uri, body: jsonEncode({'isArchived': isArchived}));
    await fetchUserCommunities();
  }

  // ── Join Requests ──
  Future<List<Map<String, dynamic>>> getJoinRequests(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/requests');
    final res = await _authedGet(uri);
    if (res != null && res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        return (data['requests'] as List? ?? []).cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    return [];
  }

  Future<void> respondJoinRequest(String communityId, String requestId, bool approve) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/requests/$requestId/respond');
    final res = await _authedPost(uri, body: jsonEncode({'approve': approve}));
    if (res == null || res.statusCode != 200) {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to respond to request') : 'Network error';
      throw Exception(errMsg);
    }
  }

  // ── Member Roles & Permissions ──
  Stream<List<Map<String, dynamic>>> getCommunityMembers(String communityId) async* {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/members');
    final res = await _authedGet(uri);
    if (res != null && res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        final members = (data['members'] as List? ?? []).cast<Map<String, dynamic>>();
        yield members;
      } catch (_) {
        yield [];
      }
    } else {
      yield [];
    }
  }

  Future<void> updateMemberRole(String communityId, String targetHandle, String role, Map<String, dynamic>? permissions) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/members/$targetHandle/role');
    final res = await _authedPut(
      uri,
      body: jsonEncode({
        'role': role,
        'permissions': permissions,
      }),
    );
    if (res == null || res.statusCode != 200) {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to update member role') : 'Network error';
      throw Exception(errMsg);
    }
  }

  Future<void> transferOwnership(String communityId, String newOwnerHandle) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/transfer-ownership');
    final res = await _authedPost(
      uri,
      body: jsonEncode({'newOwnerHandle': newOwnerHandle}),
    );
    if (res == null || res.statusCode != 200) {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to transfer ownership') : 'Network error';
      throw Exception(errMsg);
    }
  }

  Future<void> removeMember(String communityId, String memberHandle) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/members/$memberHandle');
    final res = await _authedDelete(uri);
    if (res == null || res.statusCode != 200) {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to remove member') : 'Network error';
      throw Exception(errMsg);
    }
  }

  // ── Send Messages ──
  Future<void> sendMessage(String communityId, String content) async {
    if (content.trim().isEmpty) return;
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages');
    final res = await _authedPost(
      uri,
      body: jsonEncode({
        'content': content.trim(),
        'type': 'text',
      }),
    );

    if (res != null && res.statusCode == 201) {
      fetchCommunityMessages(communityId);
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to send message') : 'Network error';
      throw Exception(errMsg);
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
    final res = await _authedPost(
      uri,
      body: jsonEncode({
        'content': caption.trim(),
        'imageUrl': imageUrl,
        'type': 'image',
      }),
    );

    if (res != null && res.statusCode == 201) {
      fetchCommunityMessages(communityId);
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to send image message') : 'Network error';
      throw Exception(errMsg);
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
    final res = await _authedPost(
      uri,
      body: jsonEncode({
        'content': caption.trim(),
        'imageUrl': validUrls.first,
        'mediaUrls': validUrls,
        'type': isVideo ? 'video' : (validUrls.length > 1 ? 'image_group' : 'image'),
      }),
    );

    if (res != null && res.statusCode == 201) {
      fetchCommunityMessages(communityId);
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to send media group') : 'Network error';
      throw Exception(errMsg);
    }
  }

  Future<void> editMessage(String communityId, String messageId, String newContent) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages/$messageId');
    final res = await _authedPut(uri, body: jsonEncode({'content': newContent.trim()}));
    if (res != null && res.statusCode == 200) {
      fetchCommunityMessages(communityId);
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to edit message') : 'Network error';
      throw Exception(errMsg);
    }
  }

  Future<void> deleteMessage(String communityId, String messageId, {String mode = 'everyone'}) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages/$messageId?mode=$mode');
    final res = await _authedDelete(uri);
    if (res != null && res.statusCode == 200) {
      fetchCommunityMessages(communityId);
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to delete message') : 'Network error';
      throw Exception(errMsg);
    }
  }

  Future<void> pinMessage(String communityId, String messageId, bool pin) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/messages/$messageId/pin');
    final res = await _authedPost(uri, body: jsonEncode({'pin': pin}));
    if (res != null && res.statusCode == 200) {
      fetchCommunityMessages(communityId);
    } else {
      final errMsg = res != null ? _extractErrorMessage(res.body, 'Failed to pin message') : 'Network error';
      throw Exception(errMsg);
    }
  }

  Future<CommunityModel?> getCommunityById(String communityId) async {
    final cached = _cachedUserCommunities.where((c) => c.id == communityId).firstOrNull ??
                   _cachedDiscoverCommunities.where((c) => c.id == communityId).firstOrNull;
    if (cached != null) return cached;

    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId');
    final res = await _authedGet(uri, timeout: const Duration(seconds: 10));
    if (res != null && res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        final comm = data['community'] as Map<String, dynamic>?;
        if (comm != null) {
          return CommunityModel.fromMap(comm, comm['id']?.toString() ?? communityId);
        }
      } catch (e) {
        debugPrint('[CommunityRepository] getCommunityById error: $e');
      }
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
    await _authedPost(uri, body: jsonEncode({'emoji': emoji}));
    if (communityId != null) {
      fetchCommunityMessages(communityId);
    }
  }

  Future<bool> isMember(String communityId) async {
    if (isMemberCached(communityId)) return true;
    final list = await fetchUserCommunities();
    return list.any((c) => c.id == communityId);
  }
}