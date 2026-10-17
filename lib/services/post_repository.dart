import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/areas_and_categories.dart';
import '../models/post_model.dart';
import '../models/comment_model.dart';
import '../core/location/location_service.dart';
import '../core/location/location_engine.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'rewards_service.dart';
import 'r2_storage_service.dart';
import 'user_action_state_service.dart';
import '../core/action_state/action_state_provider.dart';
import '../core/widgets/user_avatar.dart';
import '../core/services/name_cache_service.dart';
import '../core/services/badge_cache_service.dart';
import '../core/services/app_image_cache_service.dart';
import 'founding_service.dart';

enum FeedTab { latest, trending }

class PostRepository extends ChangeNotifier {
  static PostRepository? _instance;
  static PostRepository get instance => _instance ??= PostRepository(LocationService());

  // ⚠️ CONFIGURATION: Sourced from centralized ApiConstants.baseUrl
  static const String backendBaseUrl = ApiConstants.baseUrl;

  // 🚀 PERSISTENT HTTP CONNECTION POOL (re-uses TCP/TLS sockets to save 300ms per request)
  static final http.Client _httpClient = http.Client();

  static final Map<String, List<Post>> _categoryPostsCache = {};

  List<Post> _posts = [];
  static final Map<String, Post> _postsRegistry = {};
  String _currentUserHandle = '';
  final Map<String, int> _localVotes = {};
  final Set<String> _pendingVotePostIds = {};
  static const String _kLocalVotesPrefix = 'cache_local_votes_v2_';
  PostCategory? _selectedCategory;
  FeedTab _currentTab = FeedTab.latest;
  bool _isLoading = true;
  bool _hasLoadedOnce = false;

  bool get hasLoadedOnce => _hasLoadedOnce;

  Post? getPostById(String postId) => _postsRegistry[postId];

  Future<Post?> fetchPostById(String postId) async {
    final cached = _postsRegistry[postId];
    if (cached != null) return cached;

    try {
      final uri = Uri.parse('$backendBaseUrl/posts/$postId');
      final response = await _httpClient.get(uri, headers: await _getAuthHeaders()).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final postData = data['post'] ?? data;
        if (postData is Map<String, dynamic>) {
          final post = _parsePost(postData);
          registerPosts([post]);
          return post;
        }
      }
    } catch (e) {
      debugPrint('Error fetching single post $postId: $e');
    }
    return null;
  }

  Future<void> _loadLocalVotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kLocalVotesPrefix${_currentUserHandle.replaceAll('@', '').trim()}';
      final jsonStr = prefs.getString(key) ?? prefs.getString('cache_local_votes_global');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        decoded.forEach((k, v) {
          if (v is int) _localVotes[k] = v;
        });
        for (final p in _posts) {
          if (_localVotes.containsKey(p.id)) {
            p.userVote = _localVotes[p.id]!;
          }
        }
        for (final p in _postsRegistry.values) {
          if (_localVotes.containsKey(p.id)) {
            p.userVote = _localVotes[p.id]!;
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[PostRepository] _loadLocalVotes error: $e');
    }
  }

  Future<void> _saveLocalVotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final handle = _currentUserHandle.replaceAll('@', '').trim();
      final key = '$_kLocalVotesPrefix$handle';
      final encoded = jsonEncode(_localVotes);
      await prefs.setString(key, encoded);
      await prefs.setString('cache_local_votes_global', encoded);
    } catch (e) {
      debugPrint('[PostRepository] _saveLocalVotes error: $e');
    }
  }

  void registerPost(Post post) {
    if (_localVotes.containsKey(post.id)) {
      post.userVote = _localVotes[post.id]!;
    }
    if (_postsRegistry.containsKey(post.id)) {
      final existing = _postsRegistry[post.id]!;
      existing.upvotes = post.upvotes;
      existing.downvotes = post.downvotes;
      existing.commentCount = post.commentCount;
      existing.userVote = post.userVote;
    } else {
      _postsRegistry[post.id] = post;
    }
  }

  void registerPosts(Iterable<Post> posts) {
    for (final p in posts) {
      registerPost(p);
    }
  }

  bool _isLoadingMore = false;
  bool _hasMore = true;

  final LocationService locationService;

  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;

  static const String _kOfflinePostsCachePrefix = 'cache_offline_posts_';

  Future<void> _loadOfflineCategoryPosts(String catKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('$_kOfflinePostsCachePrefix$catKey');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        final loaded = list.map((item) => Post.fromJson(item as Map<String, dynamic>)).toList();
        if (loaded.isNotEmpty) {
          for (final p in loaded) {
            if (_localVotes.containsKey(p.id)) {
              p.userVote = _localVotes[p.id]!;
            }
          }
          _categoryPostsCache[catKey] = loaded;
          if (_selectedCategory?.name == catKey || (catKey == 'ALL' && _selectedCategory == null)) {
            _posts = List.from(loaded);
            registerPosts(loaded);
            _isLoading = false;
            _hasLoadedOnce = true;
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('[PostRepository] _loadOfflineCategoryPosts error: $e');
    }
  }

  Future<void> _saveOfflineCategoryPosts(String catKey, List<Post> posts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = posts.take(30).map((p) => p.toJson()).toList();
      await prefs.setString('$_kOfflinePostsCachePrefix$catKey', jsonEncode(toSave));
    } catch (e) {
      debugPrint('[PostRepository] _saveOfflineCategoryPosts error: $e');
    }
  }

  PostRepository(this.locationService) {
    _instance = this;
    _loadLocalVotes();
    locationService.addListener(_listenToPosts);
    final catKey = _selectedCategory?.name ?? 'ALL';
    if (_categoryPostsCache.containsKey(catKey) && _categoryPostsCache[catKey]!.isNotEmpty) {
      _posts = List.from(_categoryPostsCache[catKey]!);
      registerPosts(_posts);
      _isLoading = false;
      _hasLoadedOnce = true;
    } else {
      _loadOfflineCategoryPosts(catKey);
    }
    _initOnlineFeed();
  }

  Future<void> _initOnlineFeed() async {
    try {
      // Fetch fresh real-time data directly from Cloudflare D1 backend
      _fetchPosts(refresh: true);
    } catch (e) {
      debugPrint('Error during PostRepository init: $e');
      _listenToPosts();
    }
  }

  /// ⚡ Phase 2: Stage B Pre-fetch City Feed (Jobs/Rooms/Shops/Food/Events/General)
  Future<void> prefetchCityFeed(String cityId, {String? category}) async {
    try {
      final effCat = category ?? (_selectedCategory?.name ?? 'ALL');
      final catQuery = effCat != 'ALL' ? '&category=$effCat' : '';
      final uri = Uri.parse('$backendBaseUrl/posts?cityId=$cityId$catQuery&limit=20');
      final response = await _httpClient.get(
        uri,
        headers: {'Accept-Encoding': 'gzip'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> data = (decoded is Map ? decoded['posts'] : decoded) as List<dynamic>? ?? [];
        if (data.isNotEmpty) {
          final fetched = data.map((d) => _parsePost(d)).toList();
          registerPosts(fetched);
          if (_posts.isEmpty || locationService.cityId == cityId) {
            _posts = fetched;
            _isLoading = false;
            notifyListeners();
          }
          // Pre-warm button action states in 1 batch query
          final postIds = fetched.map((p) => p.id).toList();
          UserActionStateService.instance.fetchBatch(postIds);

          // ⚡ Phase 5: Pre-warm Cloudflare CDN Edge Cache for feed images
          final mediaUrls = fetched
              .map((p) => p.imageUrl)
              .where((u) => u != null && u.isNotEmpty)
              .cast<String>()
              .toList();
          if (mediaUrls.isNotEmpty) {
            unawaited(R2StorageService.prewarmCdn(mediaUrls));
            unawaited(AppImageCacheService.instance.prefetchImages(mediaUrls));
          }
        }
      }
    } catch (e) {
      debugPrint('[PostRepository] prefetchCityFeed warning: $e');
    }
  }

  bool get isLoading => _isLoading;
  PostCategory? get selectedCategory => _selectedCategory;
  FeedTab get currentTab => _currentTab;

  set currentUserHandle(String handle) {
    _currentUserHandle = handle;
    _loadLocalVotes();
    _listenToPosts();
  }

  String get currentUserHandle => _currentUserHandle;

  List<Post> get allPosts {
    final originLat = locationService.area?.lat ?? locationService.city.lat ?? 22.3072;
    final originLng = locationService.area?.lng ?? locationService.city.lng ?? 73.1812;
    final currentCityId = locationService.cityId.trim().toLowerCase();
    final currentAreaId = locationService.areaId?.trim().toLowerCase();

    var list = _posts.where((p) {
      if (_currentUserHandle.isNotEmpty && p.reporters.contains(_currentUserHandle)) return false;

      final postCityId = (p.cityId ?? '').trim().toLowerCase();
      final postAreaId = (p.areaId ?? '').trim().toLowerCase();

      final matchesSelectedCity = postCityId.isNotEmpty && (postCityId == currentCityId || currentCityId.isEmpty);
      final matchesSelectedArea = currentAreaId != null && currentAreaId.isNotEmpty && postAreaId == currentAreaId;

      if (!matchesSelectedCity && !matchesSelectedArea) {
        final postLat = p.lat ??
            (p.areaId != null ? LocationEngine.lookupArea(p.areaId!)?.lat : null) ??
            LocationEngine.lookupCity(p.cityId ?? '')?.lat ??
            (p.cityId != null ? LocationEngine.lookupCity(p.cityId!.toUpperCase())?.lat : null) ??
            originLat;
        final postLng = p.lng ??
            (p.areaId != null ? LocationEngine.lookupArea(p.areaId!)?.lng : null) ??
            LocationEngine.lookupCity(p.cityId ?? '')?.lng ??
            (p.cityId != null ? LocationEngine.lookupCity(p.cityId!.toUpperCase())?.lng : null) ??
            originLng;

        final distKm = LocationService.calculateDistanceKm(originLat, originLng, postLat, postLng);
        if (distKm > 50.0) return false;
      }

      return true;
    }).toList();

    if (_selectedCategory != null) {
      list = list.where((p) => p.category == _selectedCategory).toList();
    }

    if (_currentTab == FeedTab.trending) {
      list.sort((a, b) => b.score.compareTo(a.score));
    } else {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return list;
  }

  List<Post> get posts {
    var list = allPosts;

    if (_selectedCategory != null) {
      list = list.where((p) => p.category == _selectedCategory).toList();
    }

    return list;
  }

  String? _nextCursor;

  Post _parsePost(dynamic d) {
    final authorHandle = (d['authorHandle'] ?? d['author_handle'] ?? 'Anon').toString();
    final authorAvatar = (d['avatarUrl'] ?? d['avatar_url'] ?? d['avatar_r2_path']) as String?;
    final authorName = (d['authorName'] ?? d['author_name'] ?? d['displayName'] ?? d['display_name']) as String?;
    final isVerified = d['isVerified'] == true || d['is_verified'] == 1;
    final authorBadge = (d['authorBadge'] ?? d['author_badge'] ?? d['badge']) as String?;
    final founderSeq = d['founderSeq'] as int?;

    if (authorHandle.isNotEmpty && authorHandle != 'Anon') {
      if (authorAvatar != null) {
        AvatarCacheService.instance.setCachedUrl(authorHandle, authorAvatar);
      }
      if (authorName != null && authorName.isNotEmpty) {
        NameCacheService.instance.setCachedName(authorHandle, authorName);
      }
      BadgeCacheService.instance.setBadge(
        authorHandle,
        isVerified: isVerified,
        badgeText: authorBadge,
        founderSeq: founderSeq,
      );
    }

    return Post(
      id: d['id'],
      authorHandle: authorHandle,
      authorName: authorName,
      authorBadge: authorBadge,
      isVerified: isVerified,
      content: d['content'] ?? '',
      category: _parseCategory(d['category']),
      imageUrl: d['imageUrl'],
      upvotes: d['upvotes'] ?? 0,
      downvotes: d['downvotes'] ?? 0,
      commentCount: d['commentCount'] ?? 0,
      userVote: _localVotes[d['id']] ?? (d['userVote'] ?? 0),
      reportCount: d['reportCount'] ?? 0,
      reporters: List<String>.from(d['reporters'] ?? []),
      createdAt: (() {
        final raw = d['createdAt'] as String?;
        if (raw == null || raw.isEmpty) return DateTime.now();
        final s = (raw.endsWith('Z') || raw.contains('+')) ? raw : '${raw}Z';
        return (DateTime.tryParse(s) ?? DateTime.now()).toLocal();
      })(),
      stateId: d['stateId'],
      cityId: d['cityId'] ?? 'GJ-VAD',
      areaId: d['areaId'],
      areaName: (d['areaName'] != null && d['areaName'].toString().trim().isNotEmpty)
          ? d['areaName'].toString()
          : (d['areaId'] != null ? LocationEngine.lookupArea(d['areaId'].toString())?.name : null) ?? 'Vadodara',
      lat: d['lat'] != null ? (d['lat'] as num).toDouble() : null,
      lng: d['lng'] != null ? (d['lng'] as num).toDouble() : null,
      roomTitle: d['roomTitle'],
      roomArea: d['roomArea'],
      roomRent: d['roomRent'],
      mediaUrls: d['mediaUrls'] != null ? List<String>.from(d['mediaUrls']) : [],
      shopTitle: d['shopTitle'],
      shopPrice: d['shopPrice'],
      shopCategory: d['shopCategory'],
      foodTitle: d['foodTitle'],
      foodRating: d['foodRating'] != null ? (d['foodRating'] as num).toDouble() : null,
      foodPrice: d['foodPrice'],
      eventTitle: d['eventTitle'],
      eventDate: d['eventDate'],
      eventLocationText: d['eventLocationText'],
      eventPrice: d['eventPrice'],
      jobTitle: d['jobTitle'],
      jobCompany: d['jobCompany'],
      jobLocation: d['jobLocation'],
      jobType: d['jobType'],
      serviceTitle: d['serviceTitle'],
      serviceCategoryText: d['serviceCategoryText'],
      servicePrice: d['servicePrice'],
    );
  }

  Future<void>? _inFlightFetch;

  Future<void> _fetchPosts({bool refresh = false}) async {
    if (_inFlightFetch != null && !refresh) {
      return _inFlightFetch;
    }

    final completer = Completer<void>();
    _inFlightFetch = completer.future;

    if (refresh) {
      _nextCursor = null;
      if (_posts.isEmpty) {
        _isLoading = true;
        notifyListeners();
      }
    } else {
      _isLoadingMore = true;
      notifyListeners();
    }
    
    try {
      final cityId = locationService.cityId;
      final categoryStr = _selectedCategory?.name;
      
      var uri = Uri.parse('$backendBaseUrl/posts');
      final queryParams = <String, String>{
        'limit': refresh ? '20' : '30',
        'cityId': cityId,
        'cursor': ?_nextCursor,
        'category': ?categoryStr,
      };
      
      uri = uri.replace(queryParameters: queryParams);
        
      final response = await _httpClient.get(uri, headers: await _getAuthHeaders()).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> postsData = data['posts'] ?? [];
        _nextCursor = data['nextCursor'];
        
        final newPosts = postsData.map((d) => _parsePost(d)).toList();
        
        if (refresh) {
          final recentLocalPosts = _posts.where((p) {
            final isRecent = DateTime.now().difference(p.createdAt).inSeconds < 60;
            final isMine = _currentUserHandle.isNotEmpty &&
                p.authorHandle.toLowerCase().replaceAll('@', '') ==
                    _currentUserHandle.toLowerCase().replaceAll('@', '');
            final alreadyInFetched = newPosts.any((np) => np.id == p.id);
            return isRecent && isMine && !alreadyInFetched;
          }).toList();
          _posts = [...recentLocalPosts, ...newPosts];
        } else {
          _posts.addAll(newPosts);
        }
        registerPosts(newPosts);

        final mediaUrls = newPosts
            .expand((p) => [if (p.imageUrl != null) p.imageUrl!, ...p.mediaUrls])
            .where((u) => u.trim().isNotEmpty && (u.startsWith('http://') || u.startsWith('https://')))
            .take(15)
            .toList();
        if (mediaUrls.isNotEmpty) {
          unawaited(AppImageCacheService.instance.prefetchImages(mediaUrls));
        }

        _hasMore = postsData.isNotEmpty;

        final catKey = _selectedCategory?.name ?? 'ALL';
        _categoryPostsCache[catKey] = List.from(_posts);
        _saveOfflineCategoryPosts(catKey, _posts);
      }
    } catch (e) {
      debugPrint('Error fetching posts over REST: $e');
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      _hasLoadedOnce = true;
      _inFlightFetch = null;
      completer.complete();
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await _fetchPosts(refresh: true);
  }

  Timer? _fetchDebounceTimer;

  @override
  void dispose() {
    _fetchDebounceTimer?.cancel();
    locationService.removeListener(_listenToPosts);
    super.dispose();
  }

  void _listenToPosts() {
    _fetchDebounceTimer?.cancel();
    _fetchDebounceTimer = Timer(const Duration(milliseconds: 60), () {
      _fetchPosts(refresh: true);
    });
  }


  Stream<List<Comment>> listenToComments(String postId, {String? userHandle}) async* {
    int backoffSeconds = 2;
    while (true) {
      try {
        final activeHandle = (userHandle != null && userHandle.isNotEmpty)
            ? userHandle
            : _currentUserHandle;
        final uri = Uri.parse('$backendBaseUrl/posts/$postId/comments').replace(
          queryParameters: activeHandle.isNotEmpty ? {'userHandle': activeHandle} : null,
        );
        final response = await _httpClient.get(uri, headers: await _getHeaders());
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> commentsData = data['comments'] ?? [];
          final list = commentsData.map((d) {
            final map = Map<String, dynamic>.from(d as Map);
            map['postId'] ??= postId;
            return Comment.fromJson(map);
          }).toList();
          final postIdx = _posts.indexWhere((p) => p.id == postId);
          if (postIdx != -1 && _posts[postIdx].commentCount != list.length) {
            _posts[postIdx].commentCount = list.length;
            notifyListeners();
          }
          yield list;
          backoffSeconds = 2;
        } else {
          if (backoffSeconds < 60) backoffSeconds *= 2;
        }
      } catch (e) {
        debugPrint('Error fetching comments: $e');
        if (backoffSeconds < 60) backoffSeconds *= 2;
      }
      await Future.delayed(Duration(seconds: backoffSeconds));
    }
  }



  Future<Map<String, dynamic>> addComment(String postId, String authorHandle, String content) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await _httpClient.post(
        Uri.parse('$backendBaseUrl/posts/$postId/comments'),
        headers: headers,
        body: jsonEncode({'content': content}),
      );
      if (response.statusCode != 201 && response.statusCode != 200) {
        final body = jsonDecode(response.body);
        throw Exception(body['error'] ?? body['detail'] ?? 'Failed to write comment.');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      final pointsAwarded = (body['pointsAwarded'] as num?)?.toInt() ?? 0;
      final newBalance = (body['newBalance'] as num?)?.toInt();
      final commentId = body['commentId'] as String? ?? 'comm_${DateTime.now().millisecondsSinceEpoch}';

      final registeredPost = _postsRegistry[postId];
      if (registeredPost != null) {
        registeredPost.commentCount++;
      }
      for (final p in _posts) {
        if (p.id == postId) {
          p.commentCount++;
        }
      }
      notifyListeners();

      if (pointsAwarded > 0 || newBalance != null) {
        RewardsService.instance.addPoints(pointsAwarded, newBalance: newBalance);
      }

      final limitReason = body['limitReason'] as String?;

      return {
        'success': true,
        'commentId': commentId,
        'pointsAwarded': pointsAwarded,
        'newBalance': newBalance,
        'limitReason': limitReason,
      };
    } catch (e) {
      debugPrint('Error commenting via backend: $e');
      rethrow;
    }
  }

  /// REST call to Backend for reports
  Future<void> reportPost(String postId, String reporterHandle, {String reason = 'spam'}) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await _httpClient.post(
        Uri.parse('$backendBaseUrl/posts/$postId/report'),
        headers: headers,
        body: jsonEncode({'reason': reason}),
      );
      if (response.statusCode != 200) {
        debugPrint('Report post failed via backend: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error reporting post via backend: $e');
    }
  }


  List<Post> get reportedPosts {
    return _posts.where((p) => p.reportCount > 0).toList();
  }


  /// REST call to Backend for permanent deletion with instant UI response
  Future<void> deletePostPermanently(String postId) async {
    // 1. Optimistically remove from memory immediately
    final removedIndex = _posts.indexWhere((p) => p.id == postId);
    if (removedIndex != -1) {
      _posts.removeAt(removedIndex);
      notifyListeners();
    }

    try {
      final headers = await _getAuthHeaders();
      final response = await _httpClient.delete(
        Uri.parse('$backendBaseUrl/posts/$postId'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw Exception('Delete post warning from server: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error deleting post via backend: $e');
      // Revert optimistic removal
      if (removedIndex != -1) {
        _listenToPosts(); // Re-fetch to restore the correct state
      }
    }
  }

  // --- Missing UI State Methods ---

  /// Restore a moderated/hidden post back to the community feed
  Future<void> restorePost(String postId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await _httpClient.post(
        Uri.parse('$backendBaseUrl/posts/$postId/restore'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        _listenToPosts(); // Re-fetch to show restored post
      } else {
        debugPrint('Restore post failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error restoring post: $e');
    }
  }

  void setCategory(PostCategory? cat) {
    if (_selectedCategory == cat && _hasLoadedOnce) return;
    _selectedCategory = cat;
    final catKey = cat?.name ?? 'ALL';
    if (_categoryPostsCache.containsKey(catKey) && _categoryPostsCache[catKey]!.isNotEmpty) {
      _posts = List.from(_categoryPostsCache[catKey]!);
      registerPosts(_posts);
      _isLoading = false;
      _hasLoadedOnce = true;
      notifyListeners();
    } else {
      _posts = [];
      _isLoading = true;
      _hasLoadedOnce = false;
      notifyListeners();
      _loadOfflineCategoryPosts(catKey);
    }
    _listenToPosts();
  }

  void setTab(FeedTab tab) {
    _currentTab = tab;
    _listenToPosts();
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await AuthService.instance.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService.instance.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }


  PostCategory _parseCategory(dynamic value) {
    if (value == null) return PostCategory.general;
    final str = value.toString();
    return PostCategory.values.firstWhere((e) => e.name == str, orElse: () => PostCategory.general);
  }

  String _cleanInput(String input, {int maxLen = 2000}) {
    final sanitized = input.replaceAll('\u0000', '').trim();
    if (sanitized.length > maxLen) return sanitized.substring(0, maxLen);
    return sanitized;
  }

  String? _cleanOptional(String? input, {int maxLen = 200}) {
    if (input == null) return null;
    final sanitized = input.replaceAll('\u0000', '').trim();
    if (sanitized.isEmpty) return null;
    if (sanitized.length > maxLen) return sanitized.substring(0, maxLen);
    return sanitized;
  }

  Future<Map<String, dynamic>> addPost({
    required String authorHandle,
    required String content,
    required PostCategory category,
    String? imageUrl,
    required String cityId,
    String? areaId,
    String? areaName,
    double? lat,
    double? lng,
    // 🏠 Room-specific optional fields
    String? roomTitle,
    String? roomArea,
    String? roomRent,
    List<String> mediaUrls = const [],
    // 🛍️ Shop-specific optional fields
    String? shopTitle,
    String? shopPrice,
    String? shopCategory,
    // 🍲 Food-specific optional fields
    String? foodTitle,
    double? foodRating,
    String? foodPrice,
    // 🎉 Events-specific optional fields
    String? eventTitle,
    String? eventDate,
    String? eventLocationText,
    String? eventPrice,
    // 💼 Jobs-specific optional fields
    String? jobTitle,
    String? jobCompany,
    String? jobLocation,
    String? jobType,
    // 🔧 Services-specific optional fields
    String? serviceTitle,
    String? serviceCategoryText,
    String? servicePrice,
    // 🛍️ Phase 2 fields
    String? itemCondition,
    String? roomFurnishing,
    String? roomTenantPreference,
    String? jobWorkMode,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final sanitizedContent = _cleanInput(content);
      final response = await http.post(
        Uri.parse('$backendBaseUrl/posts/create'),
        headers: headers,
        body: jsonEncode({
          'authorHandle': authorHandle,
          'content': sanitizedContent,
          'category': category.name,
          'imageUrl': imageUrl,
          'cityId': cityId,
          'areaId': areaId ?? cityId,
          'areaName': ?areaName,
          'lat': ?lat,
          'lng': ?lng,
          if (roomTitle != null) 'roomTitle': _cleanOptional(roomTitle),
          if (roomArea != null) 'roomArea': _cleanOptional(roomArea),
          if (roomRent != null) 'roomRent': _cleanOptional(roomRent, maxLen: 30),
          if (mediaUrls.isNotEmpty) 'mediaUrls': mediaUrls,
          if (shopTitle != null) 'shopTitle': _cleanOptional(shopTitle),
          if (shopPrice != null) 'shopPrice': _cleanOptional(shopPrice, maxLen: 30),
          if (shopCategory != null) 'shopCategory': _cleanOptional(shopCategory, maxLen: 50),
          if (foodTitle != null) 'foodTitle': _cleanOptional(foodTitle),
          'foodRating': ?foodRating,
          if (foodPrice != null) 'foodPrice': _cleanOptional(foodPrice, maxLen: 30),
          if (eventTitle != null) 'eventTitle': _cleanOptional(eventTitle),
          if (eventDate != null) 'eventDate': _cleanOptional(eventDate, maxLen: 50),
          if (eventLocationText != null) 'eventLocationText': _cleanOptional(eventLocationText),
          if (eventPrice != null) 'eventPrice': _cleanOptional(eventPrice, maxLen: 30),
          if (jobTitle != null) 'jobTitle': _cleanOptional(jobTitle),
          if (jobCompany != null) 'jobCompany': _cleanOptional(jobCompany),
          if (jobLocation != null) 'jobLocation': _cleanOptional(jobLocation),
          if (jobType != null) 'jobType': _cleanOptional(jobType, maxLen: 50),
          if (serviceTitle != null) 'serviceTitle': _cleanOptional(serviceTitle),
          if (serviceCategoryText != null) 'serviceCategoryText': _cleanOptional(serviceCategoryText),
          if (servicePrice != null) 'servicePrice': _cleanOptional(servicePrice, maxLen: 30),
          if (itemCondition != null) 'itemCondition': _cleanOptional(itemCondition, maxLen: 30),
          if (roomFurnishing != null) 'roomFurnishing': _cleanOptional(roomFurnishing, maxLen: 30),
          if (roomTenantPreference != null) 'roomTenantPreference': _cleanOptional(roomTenantPreference, maxLen: 30),
          if (jobWorkMode != null) 'jobWorkMode': _cleanOptional(jobWorkMode, maxLen: 30),
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final resData = jsonDecode(response.body) as Map<String, dynamic>?;
          final createdPostId = resData?['id'] as String? ?? resData?['post']?['id'] as String? ?? 'post_${DateTime.now().millisecondsSinceEpoch}';
          final cleanAuthor = authorHandle.replaceAll('@', '').trim();
          final pointsAwarded = (resData?['pointsAwarded'] as num?)?.toInt() ?? 5;
          final newBalance = (resData?['newBalance'] as num?)?.toInt();

          final newPost = Post(
            id: createdPostId,
            authorHandle: cleanAuthor,
            authorName: NameCacheService.instance.getCachedName(cleanAuthor) ?? cleanAuthor,
            content: sanitizedContent,
            category: category,
            imageUrl: imageUrl,
            mediaUrls: mediaUrls,
            upvotes: 0,
            downvotes: 0,
            commentCount: 0,
            userVote: 0,
            reportCount: 0,
            reporters: const [],
            createdAt: DateTime.now(),
            stateId: null,
            cityId: cityId,
            areaId: areaId ?? cityId,
            areaName: areaName ?? (areaId != null ? LocationEngine.lookupArea(areaId)?.name : null) ?? 'Vadodara',
            lat: lat,
            lng: lng,
            roomTitle: roomTitle,
            roomArea: roomArea,
            roomRent: roomRent,
            shopTitle: shopTitle,
            shopPrice: shopPrice,
            shopCategory: shopCategory,
            foodTitle: foodTitle,
            foodRating: foodRating,
            foodPrice: foodPrice,
            eventTitle: eventTitle,
            eventDate: eventDate,
            eventLocationText: eventLocationText,
            eventPrice: eventPrice,
            jobTitle: jobTitle,
            jobCompany: jobCompany,
            jobLocation: jobLocation,
            jobType: jobType,
            serviceTitle: serviceTitle,
            serviceCategoryText: serviceCategoryText,
            servicePrice: servicePrice,
          );

          _posts.removeWhere((p) => p.id == createdPostId);
          _posts.insert(0, newPost);
          registerPost(newPost);
          notifyListeners();

          RewardsService.instance.addPoints(pointsAwarded, newBalance: newBalance);
          unawaited(FoundingService.instance.fetchMyStatus(cityId: cityId, areaId: areaId ?? cityId));
          unawaited(FoundingService.instance.fetchCounts());

          if (cleanAuthor.isNotEmpty) {
            NotificationService().sendNotification(
              targetHandle: cleanAuthor,
              title: 'Post Published',
              body: 'Your post is now live in Nearhood!',
              data: {
                'type': 'post_upload',
                'postId': createdPostId,
                'senderHandle': cleanAuthor,
              },
            );
          }
          final limitReason = resData?['limitReason'] as String? ?? resData?['rewardMessage'] as String?;
          _listenToPosts();
          return {
            'success': true,
            'postId': createdPostId,
            'pointsAwarded': pointsAwarded,
            'newBalance': newBalance,
            'limitReason': limitReason,
          };
        } catch (_) {}
        _listenToPosts();
        return {'success': true};
      } else {
        throw Exception('Failed to create post: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error adding post: $e');
      rethrow;
    }
  }

  int getUserVote(String postId) {
    return _localVotes[postId] ?? 0;
  }

  /// Returns total likes accumulated across all posts by a specific user handle
  int getTotalLikesForUser(String handle) => getTotalUpvotesForUser(handle);

  /// Like/unlike toggle for a post (1 = liked, 0 = unliked)
  Future<void> likePost(String postId) => votePost(postId, 1);

  /// Check whether current user liked the post
  bool isPostLiked(String postId) => getUserVote(postId) == 1;

  /// Returns total upvotes accumulated across all posts by a specific user handle
  int getTotalUpvotesForUser(String handle) {
    int total = 0;
    final Set<String> countedPostIds = {};
    for (final p in _postsRegistry.values.where((post) => post.authorHandle == handle)) {
      countedPostIds.add(p.id);
      total += (p.upvotes > 0 ? p.upvotes : 0);
    }
    for (final p in _posts.where((post) => post.authorHandle == handle && !countedPostIds.contains(post.id))) {
      total += (p.upvotes > 0 ? p.upvotes : 0);
    }
    return total;
  }

  Future<void> votePost(String postId, int direction) async {
    if (_pendingVotePostIds.contains(postId)) {
      return;
    }
    _pendingVotePostIds.add(postId);

    final int oldVote = _localVotes[postId] ?? 0;
    final int newVote = (oldVote == direction) ? 0 : direction;

    int upvoteDelta = 0;
    int downvoteDelta = 0;

    if (oldVote == direction) {
      if (direction == 1) {
        upvoteDelta = -1;
      } else {
        downvoteDelta = -1;
      }
    } else if (oldVote == 0) {
      if (direction == 1) {
        upvoteDelta = 1;
      } else {
        downvoteDelta = 1;
      }
    } else {
      if (direction == 1) {
        upvoteDelta = 1;
        downvoteDelta = -1;
      } else {
        upvoteDelta = -1;
        downvoteDelta = 1;
      }
    }

    _localVotes[postId] = newVote;
    _saveLocalVotes();
    ActionStateProvider.instance.setVote(postId, newVote);
    UserActionStateService.instance.setActionState(
      targetId: postId,
      isLiked: newVote == 1,
      voteDirection: newVote,
    );

    final postIndex = _posts.indexWhere((p) => p.id == postId);
    Post? targetPost;
    if (postIndex != -1) {
      final p = _posts[postIndex];
      targetPost = p;
      p.userVote = newVote;
      p.upvotes = (p.upvotes + upvoteDelta).clamp(0, 9999999);
      p.downvotes = (p.downvotes + downvoteDelta).clamp(0, 9999999);
    }
    final regPost = _postsRegistry[postId];
    if (regPost != null) {
      targetPost ??= regPost;
      if (postIndex == -1 || _posts[postIndex] != regPost) {
        regPost.userVote = newVote;
        regPost.upvotes = (regPost.upvotes + upvoteDelta).clamp(0, 9999999);
        regPost.downvotes = (regPost.downvotes + downvoteDelta).clamp(0, 9999999);
      }
    }
    notifyListeners();

    try {
      Map<String, String> headers = await _getAuthHeaders();
      http.Response response = await _httpClient.post(
        Uri.parse('$backendBaseUrl/posts/$postId/vote'),
        headers: headers,
        body: jsonEncode({'direction': direction, 'voteType': direction == 1 ? 1 : (direction == -1 ? -1 : 0)}),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 401) {
        final refreshedToken = await AuthService.instance.refreshToken();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          headers = {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $refreshedToken',
          };
          response = await _httpClient.post(
            Uri.parse('$backendBaseUrl/posts/$postId/vote'),
            headers: headers,
            body: jsonEncode({'direction': direction, 'voteType': direction == 1 ? 1 : (direction == -1 ? -1 : 0)}),
          ).timeout(const Duration(seconds: 12));
        }
      }

      if (response.statusCode != 200) {
        String errorMsg = 'Like update failed on server (${response.statusCode})';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['detail'] != null) {
            errorMsg = decoded['detail'].toString();
          }
        } catch (_) {}
        throw Exception(errorMsg);
      }

      final data = jsonDecode(response.body);
      if (data['userVote'] != null) {
        final serverVote = data['userVote'] as int;
        _localVotes[postId] = serverVote;
        _saveLocalVotes();
        ActionStateProvider.instance.setVote(postId, serverVote);
        if (postIndex != -1) {
          _posts[postIndex].userVote = serverVote;
        }
        if (regPost != null) {
          regPost.userVote = serverVote;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error voting on post $postId: $e');
      _localVotes[postId] = oldVote;
      _saveLocalVotes();
      ActionStateProvider.instance.setVote(postId, oldVote);
      UserActionStateService.instance.setActionState(
        targetId: postId,
        isLiked: oldVote == 1,
        voteDirection: oldVote,
      );

      if (postIndex != -1) {
        final p = _posts[postIndex];
        p.userVote = oldVote;
        p.upvotes = (p.upvotes - upvoteDelta).clamp(0, 9999999);
        p.downvotes = (p.downvotes - downvoteDelta).clamp(0, 9999999);
      }
      if (regPost != null && (postIndex == -1 || _posts[postIndex] != regPost)) {
        regPost.userVote = oldVote;
        regPost.upvotes = (regPost.upvotes - upvoteDelta).clamp(0, 9999999);
        regPost.downvotes = (regPost.downvotes - downvoteDelta).clamp(0, 9999999);
      }
      notifyListeners();
      rethrow;
    } finally {
      _pendingVotePostIds.remove(postId);
    }
  }

  /// Returns all posts by [handle] across all categories.
  Future<List<Post>> fetchPostsByUser(String handle) async {
    List<Post> results = [];
    try {
      final response = await _httpClient.get(
        Uri.parse('$backendBaseUrl/posts?limit=50&author=$handle&authorHandle=$handle'),
        headers: await _getAuthHeaders(),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> postsData = data['posts'] ?? [];
        results = postsData.map((d) => _parsePost(d)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching posts for profile: $e');
    }

    if (results.isEmpty) {
      final clean = handle.replaceAll('@', '').trim().toLowerCase();
      results = _posts.where((p) => p.authorHandle.replaceAll('@', '').trim().toLowerCase() == clean).toList();
      if (results.isEmpty) {
        results = _postsRegistry.values.where((p) => p.authorHandle.replaceAll('@', '').trim().toLowerCase() == clean).toList();
      }
    }

    for (final p in results) {
      if (_localVotes.containsKey(p.id)) {
        p.userVote = _localVotes[p.id]!;
      }
    }
    registerPosts(results);
    final mediaUrls = results
        .expand((p) => [if (p.imageUrl != null) p.imageUrl!, ...p.mediaUrls])
        .where((u) => u.trim().isNotEmpty && (u.startsWith('http://') || u.startsWith('https://')))
        .take(15)
        .toList();
    if (mediaUrls.isNotEmpty) {
      unawaited(AppImageCacheService.instance.prefetchImages(mediaUrls));
    }
    return results;
  }

  /// 🛍️ Phase 2: Toggle "Mark as Sold" for Buy & Sell items
  Future<void> markAsSold(String postId, {bool isSold = true}) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx != -1) {
      _posts[idx] = _posts[idx].copyWith(isSold: isSold);
    }
    final reg = _postsRegistry[postId];
    if (reg != null) {
      _postsRegistry[postId] = reg.copyWith(isSold: isSold);
    }
    notifyListeners();

    try {
      final headers = await _getAuthHeaders();
      await _httpClient.post(
        Uri.parse('$backendBaseUrl/posts/$postId/sold'),
        headers: headers,
        body: jsonEncode({'isSold': isSold}),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Error syncing markAsSold to backend: $e');
    }
  }

  /// 🔧 Phase 2: Toggle "Neighbor Recommended" status for services
  Future<void> toggleRecommendService(String postId) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx != -1) {
      final current = _posts[idx].isRecommended;
      _posts[idx] = _posts[idx].copyWith(isRecommended: !current);
    }
    final reg = _postsRegistry[postId];
    if (reg != null) {
      _postsRegistry[postId] = reg.copyWith(isRecommended: !reg.isRecommended);
    }
    notifyListeners();

    try {
      final headers = await _getAuthHeaders();
      await _httpClient.post(
        Uri.parse('$backendBaseUrl/posts/$postId/recommend'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Error syncing recommend to backend: $e');
    }
  }

  /// 🎉 Phase 2: Toggle RSVP / Going for events
  Future<void> toggleEventRsvp(String postId) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    bool isRsvped = true;
    if (idx != -1) {
      final post = _posts[idx];
      final newRsvp = !post.isUserRsvped;
      isRsvped = newRsvp;
      final newCount = (post.eventRsvpCount + (newRsvp ? 1 : -1)).clamp(0, 99999);
      _posts[idx] = post.copyWith(isUserRsvped: newRsvp, eventRsvpCount: newCount);
    }
    final reg = _postsRegistry[postId];
    if (reg != null) {
      final newRsvp = !reg.isUserRsvped;
      isRsvped = newRsvp;
      final newCount = (reg.eventRsvpCount + (newRsvp ? 1 : -1)).clamp(0, 99999);
      _postsRegistry[postId] = reg.copyWith(isUserRsvped: newRsvp, eventRsvpCount: newCount);
    }
    notifyListeners();

    try {
      final headers = await _getAuthHeaders();
      await _httpClient.post(
        Uri.parse('$backendBaseUrl/posts/$postId/rsvp'),
        headers: headers,
        body: jsonEncode({'isRsvped': isRsvped}),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Error syncing RSVP to backend: $e');
    }
  }


  void clearCache() {
    _posts.clear();
    _postsRegistry.clear();
    _categoryPostsCache.clear();
    _localVotes.clear();
    _pendingVotePostIds.clear();
    _nextCursor = null;
    _currentUserHandle = '';
    _hasLoadedOnce = false;
    _isLoading = true;
    notifyListeners();
  }
}
