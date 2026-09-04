import 'package:flutter/material.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../detail/post_detail_screen.dart';
import 'generic_category_post_screen.dart';

class GenericCategoryScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;
  final PostCategory category;
  final String title;

  const GenericCategoryScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
    required this.category,
    required this.title,
  });

  @override
  State<GenericCategoryScreen> createState() => _GenericCategoryScreenState();
}

class _GenericCategoryScreenState extends State<GenericCategoryScreen> {
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_onRepoChanged);
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  List<Post> get _posts => widget.repository.posts
      .where((p) => p.category == widget.category)
      .toList();

  @override
  Widget build(BuildContext context) {
    final posts = _posts;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F2EF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D30),
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF60A5FA)),
            tooltip: 'Create Post',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GenericCategoryPostScreen(
                    repository: widget.repository,
                    authorHandle: widget.currentUserHandle,
                    category: widget.category,
                    title: widget.title,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: posts.isEmpty
          ? const Center(child: Text('No posts yet.', style: TextStyle(color: Colors.black54)))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(
                          post: post,
                          repository: widget.repository,
                          currentUserHandle: widget.currentUserHandle,
                        ),
                      ),
                    );
                  },
                  child: Card(
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(post.content, style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('By ${post.authorHandle}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
