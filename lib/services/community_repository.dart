import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/community_model.dart';
import 'auth_service.dart';
import 'r2_storage_service.dart';

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
  List<CommunityModel> _cachedAllCommunities = [];
  List<CommunityModel> _cachedDiscoverCommunities = [];
  final Map<String, List<CommunityMessage>> _cachedMessages = {};

  // ── Stream Controllers ──
  final _userCommunitiesCtrl = StreamController<List<CommunityModel>>.broadcast();
  final _allCommunitiesCtrl = StreamController<List<CommunityModel>>.broadcast();
  final _discoverCommunitiesCtrl = StreamController<List<CommunityModel>>.broadcast();
  final _joinedIdsCtrl = StreamController<Set<String>>.broadcast();
  final Map<String, StreamController<List<CommunityMessage>>> _messageControllers = {};

  Timer? _pollingTimer;

  void _startPollingIfNeeded() {
    _pollingTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      fetchUserCommunities();
      fetchAllCommunities();
      fetchDiscoverCommunities();
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

  // ── Fetch User Communities (Joined) ──
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

  // ── Fetch All Communities ──
  Future<List<CommunityModel>> fetchAllCommunities() async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities?filter=all');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawList = data['communities'] as List? ?? [];
        _cachedAllCommunities = rawList.map((item) {
          final map = item as Map<String, dynamic>;
          return CommunityModel.fromMap(map, map['id']?.toString() ?? '');
        }).toList();
        _allCommunitiesCtrl.add(List.unmodifiable(_cachedAllCommunities));
        return _cachedAllCommunities;
      }
    } catch (e) {
      debugPrint('[CommunityRepository] fetchAllCommunities error: $e');
    }
    return _cachedAllCommunities;
  }

  // ── Fetch Discover Communities (Not Joined) ──
  Future<List<CommunityModel>> fetchDiscoverCommunities() async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities?filter=discover');
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

  Stream<List<CommunityModel>> getAllCommunities() {
    _startPollingIfNeeded();
    fetchAllCommunities();
    Future.microtask(() {
      if (!_allCommunitiesCtrl.isClosed) {
        _allCommunitiesCtrl.add(List.unmodifiable(_cachedAllCommunities));
      }
    });
    return _allCommunitiesCtrl.stream;
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
    _startPollingIfNeeded();
    fetchDiscoverCommunities();
    Future.microtask(() {
      if (!_discoverCommunitiesCtrl.isClosed) {
        _discoverCommunitiesCtrl.add(List.unmodifiable(_cachedDiscoverCommunities));
      }
    });
    return _discoverCommunitiesCtrl.stream;
  }

  Future<int> getUnreadCount(String communityId) async {
    return 0;
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

        // Sort descending by timestamp (newest first for chat view)
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

    // Set up dedicated polling timer for this community chat room
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
  Future<void> createCommunity({
    required String name,
    required String description,
    required bool isChannel,
    File? imageFile,
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
        'imageUrl': imageUrl,
      }),
    );

    if (res.statusCode == 201) {
      await fetchUserCommunities();
      await fetchAllCommunities();
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to create community');
    }
  }

  Future<void> updateCommunityImage(String communityId, File imageFile) async {
    final imageUrl = await R2StorageService.uploadImage(imageFile);
    if (imageUrl == null) throw Exception('Image upload failed.');

    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId');
    final headers = await _getAuthHeaders();
    final res = await http.put(
      uri,
      headers: headers,
      body: jsonEncode({'imageUrl': imageUrl}),
    );

    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to update community image');
    }
  }

  Future<void> editCommunity({
    required String communityId,
    required String name,
    required String description,
    File? imageFile,
  }) async {
    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await R2StorageService.uploadImage(imageFile);
    }

    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId');
    final headers = await _getAuthHeaders();
    final payload = <String, dynamic>{
      'name': name.trim(),
      'description': description.trim(),
      if (imageUrl != null) 'imageUrl': imageUrl,
    };

    final res = await http.put(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );

    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to edit community');
    }
  }

  Future<void> joinCommunity(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/join');
    final headers = await _getAuthHeaders();
    final res = await http.post(uri, headers: headers);
    if (res.statusCode == 200) {
      await fetchUserCommunities();
      await fetchDiscoverCommunities();
    } else {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to join community');
    }
  }

  Future<void> leaveCommunity(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId/leave');
    final headers = await _getAuthHeaders();
    final res = await http.post(uri, headers: headers);
    if (res.statusCode == 200) {
      await fetchUserCommunities();
      await fetchDiscoverCommunities();
    }
  }

  Future<void> deleteCommunity(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId');
    final headers = await _getAuthHeaders();
    await http.delete(uri, headers: headers);
    await fetchUserCommunities();
    await fetchAllCommunities();
  }

  Future<CommunityModel?> getCommunityById(String communityId) async {
    final uri = Uri.parse('${AuthService.baseUrl}/communities/$communityId');
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(uri, headers: headers);
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

  Future<bool> isMember(String communityId) async {
    final comms = await fetchUserCommunities();
    return comms.any((c) => c.id == communityId);
  }

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

  Future<void> transferAdmin(String communityId, String newAdminHandle) async {
    // Admin transfer logic
  }

  Future<void> removeMember(String communityId, String memberHandle) async {
    // Member removal logic
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

  Future<void> toggleReaction(String messageId, String emoji) async {
    // Handled via REST API
  }
}