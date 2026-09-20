import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../core/constants/areas_and_categories.dart';
import '../models/post_model.dart';
import '../models/comment_model.dart';
import '../core/location/location_service.dart';
import 'auth_service.dart';

enum FeedTab { latest, trending }

class PostRepository extends ChangeNotifier {
  // ⚠️ CONFIGURATION: Replace with your deployed FastAPI server URL.
  // When running locally on Android Emulator, 10.0.2.2 points to local machine's localhost.
  static const String backendBaseUrl = 'https://localv1r.onrender.com/api/v1';

  // 🚀 PERSISTENT HTTP CONNECTION POOL (re-uses TCP/TLS sockets to save 300ms per request)
  static final http.Client _httpClient = http.Client();

  List<Post> _posts = [];
  final Map<String, Post> _postsRegistry = {};
  String _currentUserHandle = '';
  Map<String, int> _localVotes = {}; // Maps postId -> vote direction (1, -1, 0)
  PostCategory? _selectedCategory = PostCategory.general;
  FeedTab _currentTab = FeedTab.latest;
  bool _isLoading = false; // Starts false if disk cache loads in 0ms!
  SharedPreferences? _prefs;

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

  PostRepository(this.locationService) {
    locationService.addListener(_listenToPosts);
    _initStorageAndLoad();
  }

  Future<void> _initStorageAndLoad() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadLocalVotes();
      // 0ms instant display from disk cache before network call
      _loadCachedPosts();
      _fetchPosts(refresh: true);
    } catch (e) {
      debugPrint('Error during PostRepository init: $e');
      _listenToPosts();
    }
  }

  String _getCacheKey() {
    final cityId = locationService.cityId;
    final areaId = locationService.areaId;
    final effectiveAreaId = (areaId != null && !areaId.contains('GENERAL')) ? areaId : 'ALL';
    final categoryStr = _selectedCategory?.name ?? 'ALL';
    return 'cached_feed_${cityId}_${effectiveAreaId}_$categoryStr';
  }

  /// 🚀 0ms Instant Disk Cache Reader (Offline-First)
  void _loadCachedPosts() {
    if (_prefs == null) return;
    try {
      final key = _getCacheKey();
      final cachedJson = _prefs!.getString(key);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List<dynamic> rawList = jsonDecode(cachedJson);
        final cached = rawList.map((d) => _parsePost(d)).toList();
        if (cached.isNotEmpty) {
          _posts = cached;
          registerPosts(cached);
          _isLoading = false;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error loading cached posts: $e');
    }
  }

  void _saveCachedPosts(List<dynamic> postsData) {
    if (_prefs == null) return;
    try {
      final key = _getCacheKey();
      _prefs!.setString(key, jsonEncode(postsData));
    } catch (e) {
      debugPrint('Error saving cached posts: $e');
    }
  }

  Future<void> _loadLocalVotes() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final String? jsonStr = _prefs!.getString('local_user_votes');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> rawMap = jsonDecode(jsonStr);
        _localVotes = rawMap.map((key, value) => MapEntry(key, value as int));
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
      debugPrint('Error loading local votes: $e');
    }
  }

  Future<void> _saveLocalVotes() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString('local_user_votes', jsonEncode(_localVotes));
    } catch (e) {
      debugPrint('Error saving local votes: $e');
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
    var list = _posts.where((p) {
      if (_currentUserHandle.isNotEmpty && p.reporters.contains(_currentUserHandle)) return false;
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

  /// 🚀 Stale-While-Revalidate Fetcher (Instant UI + Background Refresh)
  Future<void> _fetchPosts({bool refresh = false}) async {
    if (refresh) {
      _nextCursor = null;
      // If we don't have posts yet, show loading; otherwise keep showing cached posts
      if (_posts.isEmpty) {
        _loadCachedPosts();
        if (_posts.isEmpty) {
          _isLoading = true;
          notifyListeners();
        }
      }
    } else {
      _isLoadingMore = true;
      notifyListeners();
    }
    
    try {
      final cityId = locationService.cityId;
      final areaId = locationService.areaId;
      // Don't send areaId filter for GENERAL area — it means "all areas"
      final effectiveAreaId = (areaId != null && !areaId.contains('GENERAL')) ? areaId : null;
      final categoryStr = _selectedCategory?.name;
      
      var uri = Uri.parse('$backendBaseUrl/posts');
      final queryParams = <String, String>{
        'limit': '50',
        'cityId': cityId,
        'cursor': ?_nextCursor,
        'areaId': ?effectiveAreaId,
        'category': ?categoryStr,
      };
      
      uri = uri.replace(queryParameters: queryParams);
        
      final response = await _httpClient.get(uri, headers: await _getHeaders()).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> postsData = data['posts'] ?? [];
        _nextCursor = data['nextCursor'];
        
        final newPosts = postsData.map((d) => _parsePost(d)).toList();
        
        if (refresh) {
          _posts = newPosts;
          _saveCachedPosts(postsData);
        } else {
          _posts.addAll(newPosts);
        }
        registerPosts(newPosts);

        // Demo posts removed for production

        _hasMore = postsData.isNotEmpty;
      }
    } catch (e) {
      debugPrint('Error fetching posts over REST: $e');
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
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
    // 0ms instant display of cached posts for newly selected category/area
    _loadCachedPosts();
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
        Uri.parse('$backendBaseUrl/posts/$postId/comment'),
        headers: headers,
        body: jsonEncode({'content': content}),
      );
      if (response.statusCode != 201) {
        throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to write comment.');
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
    _selectedCategory = cat;
    _listenToPosts();
  }

  void setTab(FeedTab tab) {
    _currentTab = tab;
    _listenToPosts();
  }

  // --- Missing API Methods ---

  Future<Map<String, String>> _getHeaders() async {
    return {
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService.instance.getAccessToken();
    final user = FirebaseAuth.instance.currentUser;
    final fallbackToken = user != null ? await user.getIdToken() : '';
    final finalToken = (token != null && token.isNotEmpty) ? token : fallbackToken;
    
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $finalToken',
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
    required String areaId,
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
          'areaId': areaId,
          if (roomTitle != null) 'roomTitle': _cleanOptional(roomTitle),
          if (roomArea != null) 'roomArea': _cleanOptional(roomArea),
          if (roomRent != null) 'roomRent': _cleanOptional(roomRent, maxLen: 30),
          if (mediaUrls.isNotEmpty) 'mediaUrls': mediaUrls,
          if (shopTitle != null) 'shopTitle': _cleanOptional(shopTitle),
          if (shopPrice != null) 'shopPrice': _cleanOptional(shopPrice, maxLen: 30),
          if (shopCategory != null) 'shopCategory': _cleanOptional(shopCategory, maxLen: 50),
          if (foodTitle != null) 'foodTitle': _cleanOptional(foodTitle),
          if (foodRating != null) 'foodRating': foodRating,
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
        }),
      );
      if (response.statusCode == 201) {
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
    _saveLocalVotes();

    final postIndex = _posts.indexWhere((p) => p.id == postId);
    if (postIndex != -1) {
      final p = _posts[postIndex];
      p.userVote = newVote;
      p.upvotes = (p.upvotes + upvoteDelta).clamp(0, 9999999);
      p.downvotes = (p.downvotes + downvoteDelta).clamp(0, 9999999);
    }
    final regPost = _postsRegistry[postId];
    if (regPost != null && (postIndex == -1 || _posts[postIndex] != regPost)) {
      regPost.userVote = newVote;
      regPost.upvotes = (regPost.upvotes + upvoteDelta).clamp(0, 9999999);
      regPost.downvotes = (regPost.downvotes + downvoteDelta).clamp(0, 9999999);
    }
    notifyListeners();

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
        final freshFirebaseToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
        final retryToken = refreshedToken ?? freshFirebaseToken;
        if (retryToken != null && retryToken.isNotEmpty) {
          headers = {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $retryToken',
          };
          response = await _httpClient.post(
            Uri.parse('$backendBaseUrl/posts/$postId/vote'),
            headers: headers,
            body: jsonEncode({'direction': direction}),
          ).timeout(const Duration(seconds: 12));
        }
      }

      if (response.statusCode != 200) {
        String errorMsg = 'Vote failed on server (${response.statusCode})';
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
        if (postIndex != -1) {
          _posts[postIndex].userVote = serverVote;
        }
        if (regPost != null) {
          regPost.userVote = serverVote;
        }
        _saveLocalVotes();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error voting on post $postId: $e');
      // 3. Rollback optimistic state on failure
      _localVotes[postId] = oldVote;
      _saveLocalVotes();

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
        headers: await _getHeaders(),
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
      try {
        final query = await FirebaseFirestore.instance
            .collection('posts')
            .where('authorHandle', isEqualTo: handle)
            .limit(50)
            .get();
        if (query.docs.isNotEmpty) {
          results = query.docs.map((doc) {
            final d = doc.data();
            d['id'] = doc.id;
            return Post.fromJson(d);
          }).toList();
        }
      } catch (e) {
        debugPrint('Firestore fallback error for fetchPostsByUser: $e');
      }
    }

    if (results.isEmpty) {
      results = _posts.where((p) => p.authorHandle == handle).toList();
    }

    for (final p in results) {
      if (_localVotes.containsKey(p.id)) {
        p.userVote = _localVotes[p.id]!;
      }
    }
    registerPosts(results);
    return results;
  }
}
