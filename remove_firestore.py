import re

with open('lib/services/post_repository.dart', 'r', encoding='utf-8') as f:
    content = f.read()

replacement_comments = '''
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
'''

content = re.sub(
    r'Stream<List<Comment>> listenToComments\(String postId\) \{.*?(?=\n\s*/// REST call to Backend for comments)',
    replacement_comments.strip() + '\n\n',
    content,
    flags=re.DOTALL
)

# Remove FirebaseFirestore.instance
content = re.sub(
    r'final FirebaseFirestore _db = FirebaseFirestore\.instance;\s*\n',
    '',
    content
)

# Remove import
content = re.sub(
    r"import 'package:cloud_firestore/cloud_firestore\.dart';\s*\n",
    '',
    content
)

with open('lib/services/post_repository.dart', 'w', encoding='utf-8') as f:
    f.write(content)
