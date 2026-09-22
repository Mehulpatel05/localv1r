import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/widgets/post_image_view.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/vote_capsule.dart';
import '../../models/post_model.dart';
import '../../models/comment_model.dart';
import '../../services/post_repository.dart';
import '../../core/utils/content_filter.dart';
import '../../services/notification_service.dart';
import '../profile/other_user_profile_sheet.dart';

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

    final author = widget.post.authorHandle.replaceAll('@', '').trim();
    final me = widget.currentUserHandle.replaceAll('@', '').trim();
    if (author.isNotEmpty && author != me) {
      NotificationService().sendNotification(
        targetHandle: author,
        title: '@$me commented on your post',
        body: text,
        data: {
          'type': 'post',
          'postId': widget.post.id,
        },
      );
    }

    _commentController.clear();
    FocusScope.of(context).unfocus();

    // Scroll to the bottom to see new comment
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppMotion.durationStandard,
          curve: AppMotion.enterCurve,
        );
      }
    });
  }

  void _confirmDeletePost(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete Post?', style: TextStyle(color: Colors.black87)),
        content: const Text(
          'Are you sure you want to permanently delete this anonymous post? This action cannot be undone.',
          style: TextStyle(color: Colors.black54, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
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
            child: const Text('Delete', style: TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        title: Text(
          (widget.post.category == PostCategory.general || (widget.post.areaName?.contains('General') ?? true))
              ? 'Discussion Thread — Vadodara'
              : 'Discussion Thread — ${widget.post.areaName}',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
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
                    color: widget.post.isEmergency
                        ? (isDark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2))
                        : (isDark ? const Color(0xFF141414) : Colors.white),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: widget.post.isEmergency
                          ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                          : (isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          UserAvatar(
                            handle: widget.post.authorHandle,
                            size: 38,
                            fontSize: 14,
                            onTap: () {
                              if (widget.post.authorHandle != widget.currentUserHandle) {
                                showOtherUserProfileSheet(
                                  context,
                                  partnerHandle: widget.post.authorHandle,
                                  currentUserHandle: widget.currentUserHandle,
                                  repository: widget.repository,
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    if (widget.post.authorHandle != widget.currentUserHandle) {
                                      showOtherUserProfileSheet(
                                        context,
                                        partnerHandle: widget.post.authorHandle,
                                        currentUserHandle: widget.currentUserHandle,
                                        repository: widget.repository,
                                      );
                                    }
                                  },
                                  child: Text(
                                    '@${widget.post.authorHandle}',
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${widget.post.category.icon} ${widget.post.category.label} • ${_formatTime(widget.post.createdAt)}',
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.post.content,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                      if ((widget.post.imageUrl != null && widget.post.imageUrl!.isNotEmpty) || widget.post.mediaUrls.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        PostImageView(
                          imageUrl: (widget.post.imageUrl != null && widget.post.imageUrl!.isNotEmpty)
                              ? widget.post.imageUrl!
                              : widget.post.mediaUrls.first,
                          allImages: widget.post.mediaUrls.isNotEmpty
                              ? widget.post.mediaUrls
                              : [widget.post.imageUrl!],
                          height: 280,
                          borderRadius: BorderRadius.circular(14),
                          heroTagPrefix: 'detail_post_${widget.post.id}',
                          caption: widget.post.content,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Divider(color: isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9)),
                      ListenableBuilder(
                        listenable: widget.repository,
                        builder: (context, _) {
                          final currentPost = widget.repository.allPosts.firstWhere(
                            (p) => p.id == widget.post.id,
                            orElse: () => widget.post,
                          );
                          return Row(
                            children: [
                              VoteCapsule(
                                post: currentPost,
                                repository: widget.repository,
                              ),
                              const SizedBox(width: 16),
                              Row(
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 16,
                                    color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${currentPost.commentCount} comments',
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Section title
                Text(
                  'NEIGHBOR COMMENTS',
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
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
                      return Center(child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ));
                    }
                    final comments = snapshot.data ?? [];
                    if (comments.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.question_answer_outlined,
                                size: 40,
                                color: isDark ? Colors.white24 : Colors.black26,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No replies yet',
                                style: TextStyle(
                                  color: isDark ? Colors.white60 : Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Ask for details or reply as "${widget.currentUserHandle}"',
                                style: TextStyle(
                                  color: isDark ? Colors.white38 : Colors.black38,
                                  fontSize: 11,
                                ),
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
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final comment = comments[idx];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF141414) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              UserAvatar(
                                handle: comment.authorHandle,
                                size: 30,
                                fontSize: 11.5,
                                onTap: () {
                                  if (comment.authorHandle != widget.currentUserHandle) {
                                    showOtherUserProfileSheet(
                                      context,
                                      partnerHandle: comment.authorHandle,
                                      currentUserHandle: widget.currentUserHandle,
                                      repository: widget.repository,
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            if (comment.authorHandle != widget.currentUserHandle) {
                                              showOtherUserProfileSheet(
                                                context,
                                                partnerHandle: comment.authorHandle,
                                                currentUserHandle: widget.currentUserHandle,
                                                repository: widget.repository,
                                              );
                                            }
                                          },
                                          child: Text(
                                            '@${comment.authorHandle}',
                                            style: TextStyle(
                                              color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _formatTime(comment.createdAt),
                                          style: TextStyle(
                                            color: isDark ? const Color(0xFF737373) : const Color(0xFF94A3B8),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      comment.content,
                                      style: TextStyle(
                                        color: isDark ? const Color(0xFFE5E5E5) : const Color(0xFF1E293B),
                                        fontSize: 13.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
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
                    icon: const Icon(Icons.close, color: Colors.white70, size: 14),
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
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                UserAvatar(
                  handle: widget.currentUserHandle,
                  size: 34,
                  fontSize: 12,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                      ),
                    ),
                    child: TextField(
                      controller: _commentController,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Reply anonymously as ${widget.currentUserHandle}...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 13,
                        ),
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
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white : Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send_rounded,
                      color: isDark ? Colors.black : Colors.white,
                      size: 18,
                    ),
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
