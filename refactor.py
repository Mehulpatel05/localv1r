import os
import re

lib_path = r'C:\Users\swatm\StudioProjects\localv1\lib'

# 1. Create Generic Category Screen
generic_screen_content = """import 'package:flutter/material.dart';
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
"""

generic_post_screen_content = """import 'package:flutter/material.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../services/post_repository.dart';

class GenericCategoryPostScreen extends StatefulWidget {
  final PostRepository repository;
  final String authorHandle;
  final PostCategory category;
  final String title;

  const GenericCategoryPostScreen({
    super.key,
    required this.repository,
    required this.authorHandle,
    required this.category,
    required this.title,
  });

  @override
  State<GenericCategoryPostScreen> createState() => _GenericCategoryPostScreenState();
}

class _GenericCategoryPostScreenState extends State<GenericCategoryPostScreen> {
  final _descController = TextEditingController();
  bool _isPublishing = false;

  Future<void> _submit() async {
    if (_descController.text.trim().isEmpty) return;
    setState(() => _isPublishing = true);

    try {
      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: _descController.text,
        category: widget.category,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Post in ${widget.title}')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _descController,
              decoration: const InputDecoration(hintText: 'What do you want to post?'),
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isPublishing ? null : _submit,
              child: _isPublishing ? const CircularProgressIndicator() : const Text('Publish'),
            )
          ],
        ),
      ),
    );
  }
}
"""

os.makedirs(os.path.join(lib_path, 'screens', 'generic_category'), exist_ok=True)
with open(os.path.join(lib_path, 'screens', 'generic_category', 'generic_category_screen.dart'), 'w', encoding='utf-8') as f:
    f.write(generic_screen_content)
with open(os.path.join(lib_path, 'screens', 'generic_category', 'generic_category_post_screen.dart'), 'w', encoding='utf-8') as f:
    f.write(generic_post_screen_content)

# Update feed_screen.dart
feed_path = os.path.join(lib_path, 'screens', 'feed', 'feed_screen.dart')
with open(feed_path, 'r', encoding='utf-8') as f:
    feed_code = f.read()

# Replace imports
feed_code = re.sub(r"import '\.\./(jobs|food|events|rooms|shop|services)/.*_screen\.dart';", "", feed_code)
feed_code = feed_code.replace("import '../profile/other_user_profile_sheet.dart';", 
    "import '../profile/other_user_profile_sheet.dart';\nimport '../generic_category/generic_category_screen.dart';")

# Replace navigation
replacements = {
    'RoomsScreen(': 'GenericCategoryScreen(category: PostCategory.rooms, title: "Rooms & PGs", ',
    'ShopScreen(': 'GenericCategoryScreen(category: PostCategory.shop, title: "Marketplace", ',
    'FoodScreen(': 'GenericCategoryScreen(category: PostCategory.food, title: "Food", ',
    'EventsScreen(': 'GenericCategoryScreen(category: PostCategory.events, title: "Events", ',
    'JobsScreen(': 'GenericCategoryScreen(category: PostCategory.jobs, title: "Jobs", ',
    'ServicesScreen(': 'GenericCategoryScreen(category: PostCategory.services, title: "Services", ',
}

for old, new in replacements.items():
    feed_code = feed_code.replace(old, new)

with open(feed_path, 'w', encoding='utf-8') as f:
    f.write(feed_code)

print("Refactored categories!")
