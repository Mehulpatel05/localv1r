import re

with open('lib/services/post_repository.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace FirebaseFirestore imports/instances with HTTP implementation
# Wait, rewriting the whole class with regex could be messy, but I can just replace `_listenToPosts` and `loadMorePosts` and `listenToComments`

replacement_listen = '''
  String? _nextCursor;

  Future<void> _fetchPosts({bool refresh = false}) async {
    if (refresh) _nextCursor = null;
    
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
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching posts over REST: $e');
    }
  }

  void _listenToPosts() {
    _fetchPosts(refresh: true);
  }
'''

content = re.sub(
    r'void _listenToPosts\(\).*?(?=\n\s*Stream<List<Comment>> listenToComments)',
    replacement_listen.strip() + '\n\n',
    content,
    flags=re.DOTALL
)

replacement_comments = '''
  Stream<List<Comment>> listenToComments(String postId) async* {
    // Replace with polling or just a single fetch via REST
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
'''

content = re.sub(
    r'Stream<List<Comment>> listenToComments\(String postId\) \{.*?(?=\n\s*Future<void> loadMorePosts)',
    replacement_comments.strip() + '\n\n',
    content,
    flags=re.DOTALL
)

replacement_load_more = '''
  Future<void> loadMorePosts() async {
    if (_isLoadingMore || !_hasMore || _posts.length >= 200) return;
    _isLoadingMore = true;
    notifyListeners();

    await _fetchPosts(refresh: false);

    _isLoadingMore = false;
    notifyListeners();
  }
'''

content = re.sub(
    r'Future<void> loadMorePosts\(\) async \{.*?(?=\n\s*/// REST call to Backend for transaction)',
    replacement_load_more.strip() + '\n\n',
    content,
    flags=re.DOTALL
)

with open('lib/services/post_repository.dart', 'w', encoding='utf-8') as f:
    f.write(content)
