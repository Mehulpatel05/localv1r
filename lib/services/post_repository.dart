import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../core/constants/areas_and_categories.dart';
import '../models/post_model.dart';
import '../models/comment_model.dart';
import '../services/device_service.dart';

enum FeedTab { latest, trending, nearby }

class PostRepository extends ChangeNotifier {
    // ⚠️ CONFIGURATION: Replace with your deployed FastAPI server URL.
  // When running locally on Android Emulator, 10.0.2.2 points to local machine's localhost.
  static const String backendBaseUrl = 'https://localv1r.onrender.com/api/v1';

  List<Post> _posts = [];
  String _currentUserHandle = '';
  Map<String, int> _localVotes = {}; // Maps postId -> vote direction (1, -1, 0)
  Map<String, DateTime>? _lastVoteTime; // Debounce timestamps per post
  
  VadodaraArea _selectedArea = VadodaraArea.general;
  PostCategory? _selectedCategory;
  FeedTab _currentTab = FeedTab.latest;
  bool _isLoading = true;

  String? _lastDoc;
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
  VadodaraArea get selectedArea => _selectedArea;
  PostCategory? get selectedCategory => _selectedCategory;
  FeedTab get currentTab => _currentTab;

  set currentUserHandle(String handle) {
    _currentUserHandle = handle;
    _listenToPosts();
  }

  List<Post> get posts {
    // 🛡️ Filter flagged posts inline using server-derived fields directly
    var list = _posts.where((p) {
      if (p.reportCount >= 3) return false;
      if (_currentUserHandle.isNotEmpty && p.reporters.contains(_currentUserHandle)) return false;
      return true;
    }).toList();

    if (_currentTab == FeedTab.nearby || _selectedArea != VadodaraArea.general) {
      list = list.where((p) => p.area == _selectedArea || p.area == VadodaraArea.general).toList();
    }

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
          area: _parseArea(d['area']),
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
        }
      } catch (e) {
        debugPrint('Error fetching comments: $e');
      }
      await Future.delayed(const Duration(seconds: 10)); // Poll every 10s
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
        debugPrint('Delete post warning from server: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error deleting post via backend: $e');
    } catch (e) {
      debugPrint('Error deleting post via backend: $e');
      // If error occurs, let it stay removed locally or log
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

  void setArea(VadodaraArea area) {
    _selectedArea = area;
    _listenToPosts();
  }

  // --- Missing API Methods ---

  Future<Map<String, String>> _getHeaders() async {
    return {
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'accessToken') ?? await storage.read(key: 'session_token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  VadodaraArea _parseArea(dynamic value) {
    if (value == null) return VadodaraArea.general;
    final str = value.toString();
    return VadodaraArea.values.firstWhere((e) => e.name == str, orElse: () => VadodaraArea.general);
  }

  PostCategory _parseCategory(dynamic value) {
    if (value == null) return PostCategory.general;
    final str = value.toString();
    return PostCategory.values.firstWhere((e) => e.name == str, orElse: () => PostCategory.general);
  }

  Future<void> addPost({
    required String authorHandle,
    required String content,
    required VadodaraArea area,
    required PostCategory category,
    String? imageUrl,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$backendBaseUrl/posts/create'),
        headers: headers,
        body: jsonEncode({
          'authorHandle': authorHandle,
          'content': content,
          'area': area.name,
          'category': category.name,
          'imageUrl': imageUrl,
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
      // Should revert optimistic UI in real app
    }
  }
}
