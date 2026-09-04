import 'package:flutter/material.dart';
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
