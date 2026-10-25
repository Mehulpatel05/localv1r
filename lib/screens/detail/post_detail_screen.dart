import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../chat/widgets/voice_note_bubble.dart';
import '../../theme/app_colors.dart';
import '../../core/motion.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/widgets/post_image_view.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/like_capsule.dart';
import '../../models/post_model.dart';
import '../../models/comment_model.dart';
import '../../services/post_repository.dart';
import '../../core/utils/content_filter.dart';
import '../../services/rewards_service.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/verified_badge.dart';
import '../../core/services/name_cache_service.dart';
import '../../core/services/badge_cache_service.dart';
import '../profile/other_user_profile_sheet.dart';
import '../main/main_screen.dart';

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
  final Map<String, bool> _likeVotedOverrides = {};
  final Map<String, int> _likeCountOverrides = {};
  final Set<String> _inFlightCommentLikes = {};
  final Map<String, DateTime> _likeOptimisticTimestamps = {};
  final List<Comment> _optimisticComments = [];
  late final bool _isOwnPost;

  @override
  void initState() {
    super.initState();
    _isOwnPost = widget.post.authorHandle.replaceAll('@', '').toLowerCase() ==
        widget.currentUserHandle.replaceAll('@', '').toLowerCase();
  }

  bool _isCommentLiked(Comment comment) {
    if (_likeVotedOverrides.containsKey(comment.id)) {
      return _likeVotedOverrides[comment.id]!;
    }
    return comment.isLiked;
  }

  int _getCommentLikeCount(Comment comment) {
    if (_likeCountOverrides.containsKey(comment.id)) {
      return _likeCountOverrides[comment.id]!;
    }
    return comment.likeCount;
  }

  Future<void> _toggleCommentLike(Comment comment) async {
    final isOwn = comment.authorHandle.replaceAll('@', '').toLowerCase() ==
        widget.currentUserHandle.replaceAll('@', '').toLowerCase();
    if (isOwn) return;

    if (_inFlightCommentLikes.contains(comment.id)) return;

    final isCurrentlyVoted = _isCommentLiked(comment);
    final currentCount = _getCommentLikeCount(comment);
    final nextVoted = !isCurrentlyVoted;
    final nextCount = (isCurrentlyVoted ? currentCount - 1 : currentCount + 1).clamp(0, 99999);

    setState(() {
      _inFlightCommentLikes.add(comment.id);
      _likeVotedOverrides[comment.id] = nextVoted;
      _likeCountOverrides[comment.id] = nextCount;
      _likeOptimisticTimestamps[comment.id] = DateTime.now();
    });

    try {
      final res = await RewardsService.instance.toggleCommentLike(comment.id);
      if (!mounted) return;

      if (res['success'] == true) {
        final serverLiked = res['isLiked'] as bool? ?? res['liked_by_me'] as bool? ?? nextVoted;
        final serverCount = (res['likeCount'] as num?)?.toInt() ?? nextCount;
        setState(() {
          _likeVotedOverrides[comment.id] = serverLiked;
          _likeCountOverrides[comment.id] = serverCount;
        });
      } else {
        setState(() {
          _likeVotedOverrides[comment.id] = isCurrentlyVoted;
          _likeCountOverrides[comment.id] = currentCount;
          _likeOptimisticTimestamps.remove(comment.id);
        });
        final rawMsg = res['message'] as String?;
        final msg = (rawMsg != null && rawMsg.trim().isNotEmpty)
            ? rawMsg.trim()
            : 'Could not update like. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            content: Text(msg),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _likeVotedOverrides[comment.id] = isCurrentlyVoted;
          _likeCountOverrides[comment.id] = currentCount;
          _likeOptimisticTimestamps.remove(comment.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            content: Text('Network error. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _inFlightCommentLikes.remove(comment.id);
        });
      } else {
        _inFlightCommentLikes.remove(comment.id);
      }
    }
  }

  void _reportContent(BuildContext context, String type, String id) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.surface,
        content: Text(
          'Report submitted. Our moderation team will review this.',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final validationError = ContentFilter.validateContent(text);
    if (validationError != null) {
      setState(() {
        _commentError = validationError;
      });
      return;
    }

    final localCommentId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticComment = Comment(
      id: localCommentId,
      postId: widget.post.id,
      authorHandle: widget.currentUserHandle,
      content: text,
      createdAt: DateTime.now(),
    );

    setState(() {
      _commentError = null;
      _optimisticComments.add(optimisticComment);
    });

    _commentController.clear();
    FocusScope.of(context).unfocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppMotion.durationStandard,
          curve: AppMotion.enterCurve,
        );
      }
    });

    try {
      final res = await widget.repository.addComment(
        widget.post.id,
        widget.currentUserHandle,
        text,
      );

      final pointsAwarded = (res['pointsAwarded'] as num?)?.toInt() ?? 0;
      if (mounted && pointsAwarded > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.star_rounded, color: Color(0xFFFEF3C7), size: 18),
                const SizedBox(width: 8),
                Text(
                  'Comment posted · +$pointsAwarded pts',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticComments.removeWhere((c) => c.id == localCommentId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('Failed to post comment: $e'),
          ),
        );
      }
    }
  }

  void _confirmDeletePost(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Post?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to permanently delete this anonymous post? This action cannot be undone.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.repository.deletePostPermanently(widget.post.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppColors.error,
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

  void _handleBackNavigation(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => MainScreen(
            repository: widget.repository,
            currentUserHandle: widget.currentUserHandle,
          ),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackNavigation(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => _handleBackNavigation(context),
          ),
          title: Text(
          (widget.post.category == PostCategory.general || (widget.post.areaName?.contains('General') ?? true))
              ? 'Discussion Thread — Vadodara'
              : 'Discussion Thread — ${widget.post.areaName}',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.textPrimary, size: 21),
            tooltip: 'Share',
            onPressed: () async {
              final text = widget.post.content.isNotEmpty ? widget.post.content : 'Community update on Nearhood';
              final area = widget.post.areaName ?? 'Vadodara';
              final shareMessage = '$text\n\n📍 $area\n🔗 https://nearhood.in/p/${widget.post.id}\n\nJoin the Vadodara Community on Nearhood: https://nearhood.in';
              await SharePlus.instance.share(ShareParams(text: shareMessage, subject: 'Nearhood Update'));
            },
          ),
          if (_isOwnPost)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              tooltip: 'Delete Post',
              onPressed: () => _confirmDeletePost(context),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textPrimary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'report') {
                _reportContent(context, 'post', widget.post.id);
              } else if (val == 'delete' && _isOwnPost) {
                _confirmDeletePost(context);
              }
            },
            itemBuilder: (ctx) => [
              if (_isOwnPost)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppColors.error, fontSize: 13)),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, color: AppColors.textPrimary, size: 18),
                    SizedBox(width: 8),
                    Text('Report Post', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(14),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: widget.post.isEmergency
                        ? AppColors.errorSoft
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: widget.post.isEmergency
                          ? AppColors.error
                          : AppColors.divider,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (widget.post.isAnonymous)
                            Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: AppColors.primarySoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.visibility_off_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            )
                          else
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
                                Builder(
                                  builder: (context) {
                                    final cleanHandle = widget.post.authorHandle.replaceAll('@', '').trim();
                                    final authorName = widget.post.isAnonymous
                                        ? widget.post.displayAuthorName
                                        : getDisplayName(
                                            widget.post.authorHandle,
                                            fallback: widget.post.authorName,
                                          );
                                    final showHandleText = !widget.post.isAnonymous &&
                                        cleanHandle.isNotEmpty &&
                                        cleanHandle.toLowerCase() != 'anon' &&
                                        !cleanHandle.toLowerCase().startsWith('user_') &&
                                        authorName.toLowerCase() != cleanHandle.toLowerCase();
                                    final isVerified = !widget.post.isAnonymous &&
                                        BadgeCacheService.instance.isUserVerified(
                                          widget.post.authorHandle,
                                          fallback: widget.post.isVerified,
                                        );
                                    final badgeText = widget.post.isAnonymous
                                        ? null
                                        : BadgeCacheService.instance.getUserBadge(
                                            widget.post.authorHandle,
                                            fallback: widget.post.authorBadge,
                                          );

                                    return GestureDetector(
                                      onTap: () {
                                        if (!widget.post.isAnonymous && widget.post.authorHandle != widget.currentUserHandle) {
                                          showOtherUserProfileSheet(
                                            context,
                                            partnerHandle: widget.post.authorHandle,
                                            currentUserHandle: widget.currentUserHandle,
                                            repository: widget.repository,
                                          );
                                        }
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              authorName,
                                              style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (showHandleText) ...[
                                            const SizedBox(width: 5),
                                            Flexible(
                                              child: Text(
                                                '@$cleanHandle',
                                                style: const TextStyle(
                                                  color: AppColors.textMuted,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                          if (isVerified || (badgeText != null && badgeText.isNotEmpty)) ...[
                                            const SizedBox(width: 5),
                                            VerifiedBadge(
                                              isVerified: isVerified,
                                              badgeText: badgeText,
                                              compact: true,
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 2),
                                InkWell(
                                  onTap: () async {
                                    final lat = widget.post.lat;
                                    final lng = widget.post.lng;
                                    Uri uri;
                                    if (lat != null && lng != null) {
                                      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
                                    } else {
                                      final query = Uri.encodeComponent('${widget.post.areaName ?? "Vadodara"}, Gujarat, India');
                                      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
                                    }
                                    try {
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    } catch (_) {}
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on_rounded, size: 12, color: AppColors.primary),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Builder(
                                          builder: (context) {
                                            final locationAndTime = '${widget.post.areaName != null && widget.post.areaName!.isNotEmpty ? widget.post.areaName : "Vadodara"} • ${_formatTime(widget.post.createdAt)}';

                                            return Text(
                                              locationAndTime,
                                              style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
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
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                      if (widget.post.audioUrl != null && widget.post.audioUrl!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        VoiceNoteBubble(
                          audioUrl: widget.post.audioUrl!,
                          durationSeconds: 30,
                          waveformData: const [],
                          isMe: false,
                          timeStr: '',
                          isRead: true,
                          status: 'sent',
                        ),
                      ],
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
                      const Divider(color: AppColors.divider),
                      ListenableBuilder(
                        listenable: widget.repository,
                        builder: (context, _) {
                          final currentPost = widget.repository.getPostById(widget.post.id) ?? widget.post;
                          return Row(
                            children: [
                              LikeCapsule(
                                post: currentPost,
                                repository: widget.repository,
                              ),
                              const SizedBox(width: 16),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 16,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    currentPost.commentCount == 1 ? '1 comment' : '${currentPost.commentCount} comments',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
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
                const Text(
                  'NEIGHBOR COMMENTS',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                StreamBuilder<List<Comment>>(
                  stream: repo.listenToComments(widget.post.id, userHandle: widget.currentUserHandle),
                  builder: (context, snapshot) {
                    final fetchedComments = snapshot.data ?? [];
                    final comments = [...fetchedComments];
                    for (final opt in _optimisticComments) {
                      final alreadyIncluded = comments.any((c) =>
                          c.id == opt.id ||
                          (c.content == opt.content &&
                              c.authorHandle.toLowerCase().replaceAll('@', '') ==
                                  opt.authorHandle.toLowerCase().replaceAll('@', '')));
                      if (!alreadyIncluded) {
                        comments.add(opt);
                      }
                    }

                    if (snapshot.connectionState == ConnectionState.waiting && comments.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      );
                    }
                    if (comments.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.question_answer_outlined,
                                size: 40,
                                color: AppColors.textMuted,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'No replies yet',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Ask for details or reply to join the conversation',
                                style: TextStyle(
                                  color: AppColors.textMuted,
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
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.divider,
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
                                        Builder(
                                          builder: (context) {
                                            final cName = getDisplayName(
                                              comment.authorHandle,
                                              fallback: comment.authorName,
                                            );
                                            final isVerified = BadgeCacheService.instance.isUserVerified(
                                              comment.authorHandle,
                                              fallback: comment.isVerified,
                                            );
                                            final badgeText = BadgeCacheService.instance.getUserBadge(
                                              comment.authorHandle,
                                              fallback: comment.authorBadge,
                                            );

                                            return GestureDetector(
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
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    cName,
                                                    style: const TextStyle(
                                                      color: AppColors.textPrimary,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  if (isVerified || (badgeText != null && badgeText.isNotEmpty)) ...[
                                                    const SizedBox(width: 4),
                                                    VerifiedBadge(
                                                      isVerified: isVerified,
                                                      badgeText: badgeText,
                                                      fontSize: 8.5,
                                                      iconSize: 12,
                                                      compact: true,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                        const Spacer(),
                                        Text(
                                          _formatTime(comment.createdAt),
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        PopupMenuButton<String>(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(Icons.more_vert_rounded, size: 16, color: AppColors.textMuted),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          onSelected: (val) {
                                            if (val == 'report') {
                                              _reportContent(context, 'comment', comment.id);
                                            }
                                          },
                                          itemBuilder: (ctx) => [
                                            const PopupMenuItem(
                                              value: 'report',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.flag_outlined, color: AppColors.textPrimary, size: 18),
                                                  SizedBox(width: 8),
                                                  Text('Report Comment', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      comment.content,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13.5,
                                        height: 1.4,
                                      ),
                                    ),
                                        Builder(
                                          builder: (context) {
                                            final isOwnComment = comment.authorHandle.replaceAll('@', '').toLowerCase() ==
                                                widget.currentUserHandle.replaceAll('@', '').toLowerCase();
                                            final isVoted = _isCommentLiked(comment);
                                            final count = _getCommentLikeCount(comment);

                                            if (!isOwnComment) {
                                              final isInFlight = _inFlightCommentLikes.contains(comment.id);
                                              return Padding(
                                                padding: const EdgeInsets.only(top: 6),
                                                child: PressableScale(
                                                  onTap: isInFlight ? null : () => _toggleCommentLike(comment),
                                                  child: Opacity(
                                                    opacity: isInFlight ? 0.7 : 1.0,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: isVoted ? AppColors.primarySoft : AppColors.chipBg,
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: Border.all(
                                                          color: isVoted ? AppColors.primary : Colors.transparent,
                                                          width: 0.8,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            isVoted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                                            size: 12,
                                                            color: isVoted ? AppColors.primary : AppColors.textMuted,
                                                          ),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            count > 0 ? 'Like ($count)' : 'Like',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: isVoted ? FontWeight.w700 : FontWeight.w500,
                                                              color: isVoted ? AppColors.primary : AppColors.textMuted,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            } else if (count > 0) {
                                              return Padding(
                                                padding: const EdgeInsets.only(top: 6),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primarySoft,
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons.favorite_rounded,
                                                        size: 12,
                                                        color: AppColors.primary,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        count == 1 ? '1 like' : '$count likes',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w700,
                                                          color: AppColors.primary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            }
                                            return const SizedBox.shrink();
                                          },
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
          if (_commentError != null)
            Container(
              width: double.infinity,
              color: AppColors.errorSoft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _commentError!,
                      style: const TextStyle(color: AppColors.errorSoftText, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, color: AppColors.errorSoftText, size: 14),
                    onPressed: () => setState(() => _commentError = null),
                  ),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 10,
              bottom: MediaQuery.of(context).padding.bottom + 10,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(
                  color: AppColors.divider,
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
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.divider,
                      ),
                    ),
                    child: TextField(
                      controller: _commentController,
                      cursorColor: AppColors.primary,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Reply as ${getDisplayName(widget.currentUserHandle)}...',
                        hintStyle: const TextStyle(
                          color: AppColors.textMuted,
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
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
