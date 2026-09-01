import 'package:flutter/material.dart';
import '../../core/widgets/safe_image.dart';
import '../../models/post_model.dart';
import '../../models/comment_model.dart';
import '../../services/post_repository.dart';
import '../../core/utils/content_filter.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;
  final PostRepository repository;
  final String currentUserHandle;

  const PostDetailScreen({
    super.key,
    required this.post,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _commentError;

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final validationError = ContentFilter.validateContent(text);
    if (validationError != null) {
      setState(() {
        _commentError = validationError;
      });
      return;
    }

    setState(() {
      _commentError = null;
    });

    widget.repository.addComment(
      widget.post.id,
      widget.currentUserHandle,
      text,
    );

    _commentController.clear();
    FocusScope.of(context).unfocus();

    // Scroll to the bottom to see new comment
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _confirmDeletePost(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151D30),
        title: const Text('Delete Post?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to permanently delete this anonymous post? This action cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7F1D1D)),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.repository.deletePostPermanently(widget.post.id);
              if (context.mounted) {
                Navigator.pop(context); // Pop back to feed screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFFEF4444),
                    content: Text('Post permanently deleted.'),
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D30),
        elevation: 0,
        title: Text(
          'Discussion Thread — ${widget.post.area.displayName}',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (widget.post.authorHandle == widget.currentUserHandle)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              tooltip: 'Delete Post',
              onPressed: () => _confirmDeletePost(context),
            ),
        ],
      ),
      body: Column(
        children: [
          // Comments list + Post Card
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(14),
              children: [
                // Highlighted original post card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: widget.post.isEmergency ? const Color(0xFF3A1A22) : const Color(0xFF151D30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.post.isEmergency ? const Color(0xFFEF4444).withOpacity(0.5) : const Color(0xFF243049),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.post.authorHandle,
                            style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.post.category.icon} ${widget.post.category.label}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          const Spacer(),
                          Text(
                            _formatTime(widget.post.createdAt),
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.post.content,
                        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.45),
                      ),
                      if (widget.post.imageUrl != null && widget.post.imageUrl!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SafeImage(
                          imageUrl: widget.post.imageUrl!,
                          height: 220,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFF243049)),
                      Row(
                        children: [
                          const Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.white30),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.post.score} votes',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          const SizedBox(width: 16),
                          const Icon(Icons.mode_comment_outlined, size: 15, color: Colors.white30),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.post.commentCount} comments',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Section title
                const Text(
                  'NEIGHBOR COMMENTS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),

                // Comments body
                StreamBuilder<List<Comment>>(
                  stream: repo.listenToComments(widget.post.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
                      ));
                    }
                    final comments = snapshot.data ?? [];
                    if (comments.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(Icons.question_answer_outlined, size: 40, color: Colors.white12),
                              const SizedBox(height: 8),
                              const Text(
                                'No replies yet',
                                style: TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Ask for details or reply as "${widget.currentUserHandle}"',
                                style: const TextStyle(color: Colors.white24, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: comments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final comment = comments[idx];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF1F293D)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    comment.authorHandle,
                                    style: const TextStyle(
                                      color: Color(0xFF38BDF8),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatTime(comment.createdAt),
                                    style: const TextStyle(color: Colors.white24, fontSize: 11),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                comment.content,
                                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),

          // Real-time error warning above the typing box
          if (_commentError != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF7F1D1D),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white70, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _commentError!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, color: Colors.white60, size: 14),
                    onPressed: () => setState(() => _commentError = null),
                  ),
                ],
              ),
            ),

          // Interactive Reply Typing Bar
          Container(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 10,
              bottom: MediaQuery.of(context).padding.bottom + 10,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF151D30),
              border: Border(
                top: BorderSide(color: Color(0xFF243049), width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0F19),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF243049)),
                    ),
                    child: TextField(
                      controller: _commentController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Reply anonymously as ${widget.currentUserHandle}...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                      ),
                      onSubmitted: (_) => _submitComment(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _submitComment,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF3B82F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
