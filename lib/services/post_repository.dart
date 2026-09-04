import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../core/constants/areas_and_categories.dart';
import '../models/post_model.dart';
import '../models/comment_model.dart';
import '../services/device_service.dart';

enum FeedTab { latest, trending }

class PostRepository extends ChangeNotifier {
    // ⚠️ CONFIGURATION: Replace with your deployed FastAPI server URL.
  // When running locally on Android Emulator, 10.0.2.2 points to local machine's localhost.
  static const String backendBaseUrl = 'https://localv1r.onrender.com/api/v1';

  List<Post> _posts = [];
  String _currentUserHandle = '';
  Map<String, int> _localVotes = {}; // Maps postId -> vote direction (1, -1, 0)
  PostCategory? _selectedCategory = PostCategory.general;
  FeedTab _currentTab = FeedTab.latest;
  bool _isLoading = true;


  bool _isLoadingMore = false;
  bool _hasMore = true;

  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;

  PostRepository() {
    _loadLocalVotes().then((_) {
      _listenToPosts();
    });
  }

  Future<void> _loadLocalVotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('local_user_votes');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> rawMap = jsonDecode(jsonStr);
        _localVotes = rawMap.map((key, value) => MapEntry(key, value as int));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading local votes: $e');
    }
  }

  Future<void> _saveLocalVotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('local_user_votes', jsonEncode(_localVotes));
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

  List<Post> get posts {
    // 🛡️ Filter flagged posts inline using server-derived fields directly
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

  String? _nextCursor;

  Future<void> _fetchPosts({bool refresh = false}) async {
    if (refresh) {
      _nextCursor = null;
      _isLoading = true;
      notifyListeners();
    } else {
      _isLoadingMore = true;
      notifyListeners();
    }
    
    try {
      final url = _nextCursor == null 
        ? '$backendBaseUrl/posts?limit=20'
        : '$backendBaseUrl/posts?limit=20&cursor=$_nextCursor';
        
      final response = await http.get(Uri.parse(url), headers: await _getHeaders());
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> postsData = data['posts'];
        _nextCursor = data['nextCursor'];
        
        final newPosts = postsData.map((d) => Post(
          id: d['id'],
          authorHandle: d['authorHandle'] ?? 'Anon',
          content: d['content'] ?? '',
          category: _parseCategory(d['category']),
          imageUrl: d['imageUrl'],
          upvotes: d['upvotes'] ?? 0,
          downvotes: d['downvotes'] ?? 0,
          reportCount: d['reportCount'] ?? 0,
          reporters: List<String>.from(d['reporters'] ?? []),
          createdAt: DateTime.tryParse(d['createdAt'] ?? '') ?? DateTime.now(),
        )).toList();
        
        if (refresh) {
          _posts = newPosts;
        } else {
          _posts.addAll(newPosts);
        }

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

  void _listenToPosts() {
    _fetchPosts(refresh: true);
  }


  Stream<List<Comment>> listenToComments(String postId) async* {
    int backoffSeconds = 2;
    while (true) {
      try {
        final response = await http.get(Uri.parse('$backendBaseUrl/posts/$postId/comments'), headers: await _getHeaders());
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
      final response = await http.post(
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
      final response = await http.post(
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

  /// REST call to Backend for moderation restore
  Future<void> restorePost(String postId) async {
    // Note: Restore and Admin actions can be securely verified on backend (or roles)
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$backendBaseUrl/posts/$postId/restore'),
        headers: headers,
      );
      if (response.statusCode != 200) {
        debugPrint('Restore failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error restoring post: $e');
    }
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
      final response = await http.post(
        Uri.parse('$backendBaseUrl/posts/$postId/delete'),
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
    final user = FirebaseAuth.instance.currentUser;
    final token = user != null ? await user.getIdToken() : '';
    
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  PostCategory _parseCategory(dynamic value) {
    if (value == null) return PostCategory.general;
    final str = value.toString();
    return PostCategory.values.firstWhere((e) => e.name == str, orElse: () => PostCategory.general);
  }

  Future<void> addPost({
    required String authorHandle,
    required String content,
    required PostCategory category,
    String? imageUrl,
    // 🏠 Room-specific optional fields
    String? roomTitle,
    String? roomArea,
    String? roomRent,
    List<String> mediaUrls = const [],
    // 🛍️ Shop-specific optional fields
    String? shopTitle,
    String? shopPrice,
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
      final response = await http.post(
        Uri.parse('$backendBaseUrl/posts/create'),
        headers: headers,
        body: jsonEncode({
          'authorHandle': authorHandle,
          'content': content,
          'category': category.name,
          'imageUrl': imageUrl,
          if (roomTitle != null) 'roomTitle': roomTitle,
          if (roomArea != null) 'roomArea': roomArea,
          if (roomRent != null) 'roomRent': roomRent,
          if (mediaUrls.isNotEmpty) 'mediaUrls': mediaUrls,
          if (shopTitle != null) 'shopTitle': shopTitle,
          if (shopPrice != null) 'shopPrice': shopPrice,
          if (foodTitle != null) 'foodTitle': foodTitle,
          if (foodRating != null) 'foodRating': foodRating,
          if (foodPrice != null) 'foodPrice': foodPrice,
          if (eventTitle != null) 'eventTitle': eventTitle,
          if (eventDate != null) 'eventDate': eventDate,
          if (eventLocationText != null) 'eventLocationText': eventLocationText,
          if (eventPrice != null) 'eventPrice': eventPrice,
          if (jobTitle != null) 'jobTitle': jobTitle,
          if (jobCompany != null) 'jobCompany': jobCompany,
          if (jobLocation != null) 'jobLocation': jobLocation,
          if (jobType != null) 'jobType': jobType,
          if (serviceTitle != null) 'serviceTitle': serviceTitle,
          if (serviceCategoryText != null) 'serviceCategoryText': serviceCategoryText,
          if (servicePrice != null) 'servicePrice': servicePrice,
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

  Future<void> votePost(String postId, int direction) async {
    // Optimistic UI updates
    final int oldVote = _localVotes[postId] ?? 0;
    if (oldVote == direction) return;

    final index = _posts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final p = _posts[index];
      if (oldVote == 1) p.upvotes--;
      if (oldVote == -1) p.downvotes--;
      if (direction == 1) p.upvotes++;
      if (direction == -1) p.downvotes++;

      _localVotes[postId] = direction;
      _saveLocalVotes();
      notifyListeners();
    }

    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$backendBaseUrl/posts/$postId/vote'),
        headers: headers,
        body: jsonEncode({'direction': direction}),
      );
      if (response.statusCode != 200) {
        throw Exception('Vote failed');
      }
    } catch (e) {
      debugPrint('Error voting: $e');
      // Revert optimistic UI
      final revertIndex = _posts.indexWhere((p) => p.id == postId);
      if (revertIndex != -1) {
        final p = _posts[revertIndex];
        if (direction == 1) p.upvotes--;
        if (direction == -1) p.downvotes--;
        if (oldVote == 1) p.upvotes++;
        if (oldVote == -1) p.downvotes++;
        
        _localVotes[postId] = oldVote;
        _saveLocalVotes();
        notifyListeners();
      }
    }
  }

  /// Returns all posts by [handle] — filters from the already-loaded in-memory
  /// list first (fast & accurate). Falls back to a fresh backend fetch if the
  /// in-memory list is empty (e.g. profile opened before feed loads).
  Future<List<Post>> fetchPostsByUser(String handle) async {
    // ── 1. Filter from already-loaded in-memory posts (most reliable) ──────
    final fromMemory = _posts
        .where((p) => p.authorHandle == handle)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (fromMemory.isNotEmpty) {
      return fromMemory;
    }

    // ── 2. Fallback: fetch fresh from backend ────────
    try {
      final response = await http.get(
        Uri.parse('$backendBaseUrl/posts?limit=50&author=$handle'),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> postsData = data['posts'] ?? [];
        final allPosts = postsData.map((d) => Post(
          id: d['id'],
          authorHandle: d['authorHandle'] ?? '',
          content: d['content'] ?? '',
          category: _parseCategory(d['category']),
          imageUrl: d['imageUrl'],
          upvotes: d['upvotes'] ?? 0,
          downvotes: d['downvotes'] ?? 0,
          reportCount: d['reportCount'] ?? 0,
          reporters: List<String>.from(d['reporters'] ?? []),
          createdAt: DateTime.tryParse(d['createdAt'] ?? '') ?? DateTime.now(),
        )).toList();

        return allPosts;
      }
    } catch (e) {
      debugPrint('Error fetching posts for profile: $e');
    }
    return [];
  }
}
