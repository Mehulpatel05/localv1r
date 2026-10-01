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
import 'r2_storage_service.dart';
import 'user_action_state_service.dart';
import '../core/action_state/action_state_provider.dart';

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
  final Map<String, Post> _postsRegistry = {};
  String _currentUserHandle = '';
  final Map<String, int> _localVotes = {}; // Maps postId -> vote direction (1, -1, 0)
  PostCategory? _selectedCategory = PostCategory.general;
  FeedTab _currentTab = FeedTab.latest;
  bool _isLoading = true;
  bool _hasLoadedOnce = false;

  bool get hasLoadedOnce => _hasLoadedOnce;

  Post? getPostById(String postId) => _postsRegistry[postId];

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
        final List<dynamic> data = jsonDecode(response.body);
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
    _listenToPosts();
  }

  String get currentUserHandle => _currentUserHandle;

  List<Post> get allPosts {
    final originLat = locationService.area?.lat ?? locationService.city.lat ?? 22.3072;
    final originLng = locationService.area?.lng ?? locationService.city.lng ?? 73.1812;

    var list = _posts.where((p) {
      if (_currentUserHandle.isNotEmpty && p.reporters.contains(_currentUserHandle)) return false;

      // 🌐 Proximity Radius Distance Filter (distance <= 50.0 km)
      final postLat = p.lat ?? LocationEngine.lookupCity(p.cityId ?? '')?.lat ?? 22.3072;
      final postLng = p.lng ?? LocationEngine.lookupCity(p.cityId ?? '')?.lng ?? 73.1812;

      final distKm = LocationService.calculateDistanceKm(originLat, originLng, postLat, postLng);
      if (distKm > 50.0 && p.cityId != locationService.cityId) return false;

      return true;
    }).toList();

    if (_selectedCategory != null) {
      list = list.where((p) => p.category == _selectedCategory).toList();
    }

    if (_currentTab == FeedTab.trending) {
      list.sort((a, b) => b.score.compareTo(a.score));
    } else {
      // Nearest posts first
      list.sort((a, b) {
        final postLatA = a.lat ?? LocationEngine.lookupCity(a.cityId ?? '')?.lat ?? 22.3072;
        final postLngA = a.lng ?? LocationEngine.lookupCity(a.cityId ?? '')?.lng ?? 73.1812;
        final distA = LocationService.calculateDistanceKm(originLat, originLng, postLatA, postLngA);

        final postLatB = b.lat ?? LocationEngine.lookupCity(b.cityId ?? '')?.lat ?? 22.3072;
        final postLngB = b.lng ?? LocationEngine.lookupCity(b.cityId ?? '')?.lng ?? 73.1812;
        final distB = LocationService.calculateDistanceKm(originLat, originLng, postLatB, postLngB);

        if ((distA - distB).abs() > 0.5) {
          return distA.compareTo(distB);
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    return list;
  }

  List<Post> get posts {
    // 🛡️ Filter flagged posts inline using server-derived fields directly
    var list = allPosts;

    if (_selectedCategory != null) {
      list = list.where((p) => p.category == _selectedCategory).toList();
    }

    return list;
  }

  String? _nextCursor;

  Post _parsePost(dynamic d) {
    return Post(
      id: d['id'],
      authorHandle: d['authorHandle'] ?? 'Anon',
      content: d['content'] ?? '',
      category: _parseCategory(d['category']),
      imageUrl: d['imageUrl'],
      upvotes: d['upvotes'] ?? 0,
      downvotes: d['downvotes'] ?? 0,
      commentCount: d['commentCount'] ?? 0,
      userVote: _localVotes[d['id']] ?? (d['userVote'] ?? 0),
      reportCount: d['reportCount'] ?? 0,
      reporters: List<String>.from(d['reporters'] ?? []),
      createdAt: DateTime.tryParse(d['createdAt'] ?? '') ?? DateTime.now(),
      stateId: d['stateId'],
      cityId: d['cityId'],
      areaId: d['areaId'],
      areaName: d['areaName'],
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

  /// 🚀 Real-time Fetcher from Cloudflare D1 Backend
  Future<void> _fetchPosts({bool refresh = false}) async {
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
        'limit': '50',
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
          _posts = newPosts;
        } else {
          _posts.addAll(newPosts);
        }
        registerPosts(newPosts);

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


  Stream<List<Comment>> listenToComments(String postId) async* {
    int backoffSeconds = 2;
    while (true) {
      try {
        final response = await _httpClient.get(Uri.parse('$backendBaseUrl/posts/$postId/comments'), headers: await _getHeaders());
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> commentsData = data['comments'];
          yield commentsData.map((d) => Comment(
            id: d['id'],
            postId: postId,
            authorHandle: d['authorHandle'] ?? 'Anon',
            content: d['content'] ?? '',
            createdAt: DateTime.tryParse(d['createdAt'] ?? '') ?? DateTime.now(),
          )).toList();
          
          // Reset backoff on success
          backoffSeconds = 2;
        } else {
          // Increase backoff on error/non-200
          if (backoffSeconds < 60) backoffSeconds *= 2;
        }
      } catch (e) {
        debugPrint('Error fetching comments: $e');
        // Increase backoff on network error
        if (backoffSeconds < 60) backoffSeconds *= 2;
      }
      await Future.delayed(Duration(seconds: backoffSeconds));
    }
  }



  /// REST call to Backend for comments
  Future<void> addComment(String postId, String authorHandle, String content) async {
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

  Future<void> addPost({
    required String authorHandle,
    required String content,
    required PostCategory category,
    String? imageUrl,
    required String cityId,
    String? areaId,
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
      if (response.statusCode == 201) {
        try {
          final resData = jsonDecode(response.body) as Map<String, dynamic>?;
          final createdPostId = resData?['id'] as String? ?? resData?['post']?['id'] as String?;
          final cleanAuthor = authorHandle.replaceAll('@', '').trim();
          if (cleanAuthor.isNotEmpty) {
            NotificationService().sendNotification(
              targetHandle: cleanAuthor,
              title: 'Post Published',
              body: 'Your post is now live in Nearhood!',
              data: {
                'type': 'post_upload',
                'postId': createdPostId ?? '',
                'senderHandle': cleanAuthor,
              },
            );
          }
        } catch (_) {}
        _listenToPosts(); // refresh feed
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

  /// Concurrency-safe optimistic vote toggle method
  Future<void> votePost(String postId, int direction) async {
    final int oldVote = _localVotes[postId] ?? 0;
    final int newVote = (oldVote == direction) ? 0 : direction;

    int upvoteDelta = 0;
    int downvoteDelta = 0;

    if (oldVote == direction) {
      // Toggle off existing vote
      if (direction == 1) {
        upvoteDelta = -1;
      } else {
        downvoteDelta = -1;
      }
    } else if (oldVote == 0) {
      // Cast first vote
      if (direction == 1) {
        upvoteDelta = 1;
      } else {
        downvoteDelta = 1;
      }
    } else {
      // Switch direction (+1 to -1 or -1 to +1)
      if (direction == 1) {
        upvoteDelta = 1;
        downvoteDelta = -1;
      } else {
        upvoteDelta = -1;
        downvoteDelta = 1;
      }
    }

    // 1. Optimistic memory update
    _localVotes[postId] = newVote;
    ActionStateProvider.instance.setVote(postId, newVote);

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

    // 🔔 Dispatch Instagram-style Like notification to post author when liked
    if (direction == 1 && newVote == 1 && targetPost != null) {
      final author = targetPost.authorHandle.replaceAll('@', '').trim();
      final me = _currentUserHandle.replaceAll('@', '').trim();
      if (author.isNotEmpty && me.isNotEmpty && author.toLowerCase() != me.toLowerCase()) {
        NotificationService().sendNotification(
          targetHandle: author,
          title: 'New Like',
          body: '@$me liked your post',
          data: {
            'type': 'post_like',
            'postId': postId,
            'senderHandle': me,
          },
        );
      }
    }

    // 2. Dispatch vote transaction to backend proxy
    try {
      Map<String, String> headers = await _getAuthHeaders();
      http.Response response = await _httpClient.post(
        Uri.parse('$backendBaseUrl/posts/$postId/vote'),
        headers: headers,
        body: jsonEncode({'direction': direction}),
      ).timeout(const Duration(seconds: 12));

      // If unauthorized (401), attempt token refresh & retry once
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
            body: jsonEncode({'direction': direction}),
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

      // Sync server-returned userVote if returned
      final data = jsonDecode(response.body);
      if (data['userVote'] != null) {
        final serverVote = data['userVote'] as int;
        _localVotes[postId] = serverVote;
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
      // 3. Rollback optimistic state on failure
      _localVotes[postId] = oldVote;
      ActionStateProvider.instance.setVote(postId, oldVote);

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
      results = _posts.where((p) => p.authorHandle == handle).toList();
      if (results.isEmpty) {
        results = _postsRegistry.values.where((p) => p.authorHandle == handle).toList();
      }
    }

    for (final p in results) {
      if (_localVotes.containsKey(p.id)) {
        p.userVote = _localVotes[p.id]!;
      }
    }
    registerPosts(results);
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


  /// ⚡ Phase 4: Wipes in-memory posts, registry, and local votes on logout
  void clearCache() {
    _posts.clear();
    _postsRegistry.clear();
    _localVotes.clear();
    _currentUserHandle = '';
    notifyListeners();
  }
}
