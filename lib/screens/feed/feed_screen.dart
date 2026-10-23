import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/location/location_service.dart';
import '../../core/widgets/post_image_view.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/like_capsule.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../create/create_post_screen.dart';
import '../detail/post_detail_screen.dart';
import '../notifications/notifications_screen.dart';
import '../../services/notification_service.dart';
import '../profile/other_user_profile_sheet.dart';
import '../profile/profile_screen.dart';
import '../../core/services/app_image_cache_service.dart';
import '../../core/services/name_cache_service.dart';
import '../../core/services/badge_cache_service.dart';
import '../../core/widgets/verified_badge.dart';
import '../../services/rewards_service.dart';
import '../rewards/rewards_hub_screen.dart';
import '../../services/app_asset_service.dart';

class FeedScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;
  final VoidCallback? onOpenProfileTab;

  const FeedScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
    this.onOpenProfileTab,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Post> _getFilteredPosts(List<Post> posts) {
    return posts;
  }

  void _openProfile() {
    if (widget.onOpenProfileTab != null) {
      widget.onOpenProfileTab!();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            repository: widget.repository,
            currentUserHandle: widget.currentUserHandle,
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    AppAssetService.instance.init();
    AppAssetService.instance.syncAllFromServer();
    widget.repository.addListener(_onRepositoryUpdated);
    widget.repository.setCategory(null);
    _triggerFeedImagePrefetch();
    RewardsService.instance.fetchSummary(forceRefresh: true);
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onRepositoryUpdated);
    super.dispose();
  }

  void _onRepositoryUpdated() {
    _triggerFeedImagePrefetch();
    if (mounted) setState(() {});
  }

  void _triggerFeedImagePrefetch() {
    final posts = widget.repository.posts;
    final List<String> imageUrlsToPrefetch = [];
    for (final post in posts.take(15)) {
      if (post.imageUrl != null && post.imageUrl!.isNotEmpty) {
        imageUrlsToPrefetch.add(post.imageUrl!);
      }
      for (final media in post.mediaUrls) {
        if (media.isNotEmpty && !imageUrlsToPrefetch.contains(media)) {
          imageUrlsToPrefetch.add(media);
        }
      }
    }
    if (imageUrlsToPrefetch.isNotEmpty) {
      AppImageCacheService.instance.prefetchImages(imageUrlsToPrefetch);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;

    return Scaffold(
      backgroundColor: AppColors.softBackground,
      appBar: AppBar(
        backgroundColor: AppColors.softBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        automaticallyImplyLeading: false,
        toolbarHeight: 62,
        title: SizedBox(
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Builder(
                  builder: (context) {
                    final locService = context.watch<LocationService>();
                    final areaName = (locService.area?.name != null && locService.area!.name.trim().isNotEmpty)
                        ? locService.area!.name
                        : (locService.city.areas.firstOrNull?.name ?? locService.city.name);

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.22),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 96),
                            child: Text(
                              areaName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Center(
                child: Text(
                  'NEARHOOD',
                  style: GoogleFonts.jersey25(
                    color: AppColors.primary,
                    fontSize: 26,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (RewardsService.isRewardsEnabled) ...[
                      ListenableBuilder(
                        listenable: RewardsService.instance,
                        builder: (context, _) {
                          final points = RewardsService.instance.summary?.balance ?? 0;
                          return PressableScale(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RewardsHubScreen(currentUserHandle: widget.currentUserHandle),
                                ),
                              );
                            },
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFFD97706),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$points',
                                    style: const TextStyle(
                                      color: Color(0xFFB45309),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    ValueListenableBuilder<int>(
                      valueListenable: NotificationService.instance.unreadBadgeNotifier,
                      builder: (context, count, _) {
                        return GestureDetector(
                          onTap: () async {
                            NotificationService.instance.unreadBadgeNotifier.value = 0;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NotificationsScreen(
                                  currentUserHandle: widget.currentUserHandle,
                                ),
                              ),
                            );
                            if (context.mounted) {
                              NotificationService.instance.prefetchBadgeCounts(widget.currentUserHandle);
                            }
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(
                                  Icons.notifications_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                if (count > 0)
                                  Positioned(
                                    right: -1,
                                    top: -1,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                      decoration: BoxDecoration(
                                        color: AppColors.error,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        count > 99 ? '99+' : '$count',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          height: 1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: repo.isLoading
                  ? _buildLoadingSkeleton()
                  : KeyedSubtree(
                      key: const ValueKey('feed_general_all_posts'),
                      child: RefreshIndicator(
                        onRefresh: () async {
                          await Future.wait([
                            widget.repository.refresh(),
                            RewardsService.instance.fetchSummary(forceRefresh: true),
                          ]);
                        },
                        color: AppColors.primary,
                        child: () {
                          final posts = _getFilteredPosts(repo.posts);
                          if (posts.isEmpty) {
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: SizedBox(
                                height: MediaQuery.of(context).size.height * 0.58,
                                child: _buildEmptyState(),
                              ),
                            );
                          }
                          return ListView.builder(
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            addRepaintBoundaries: true,
                            addAutomaticKeepAlives: true,
                            padding: EdgeInsets.only(
                              top: 0,
                              bottom: 88 + MediaQuery.paddingOf(context).bottom,
                              left: 0,
                              right: 0,
                            ),
                            itemCount: posts.length,
                            itemBuilder: (context, index) {
                              final post = posts[index];
                              return _PostCardItem(
                                key: ValueKey('post_${post.id}'),
                                post: post,
                                repository: repo,
                                currentUserHandle: widget.currentUserHandle,
                                onDelete: () => _showDeleteConfirmation(context, post.id),
                                onReport: () => _showReportContentSheet(post.id),
                                onProfileTap: () {
                                  if (post.authorHandle != widget.currentUserHandle) {
                                    showOtherUserProfileSheet(
                                      context,
                                      partnerHandle: post.authorHandle,
                                      currentUserHandle: widget.currentUserHandle,
                                      repository: widget.repository,
                                    );
                                  } else {
                                    _openProfile();
                                  }
                                },
                              );
                            },
                          );
                        }(),
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingCreateButton(),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.chipBg,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 100,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 60,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    width: 70,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 220,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 80,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 60,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: AppColors.chipBg,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primarySoft,
              ),
              child: const Center(
                child: Icon(
                  Icons.home_work_outlined,
                  size: 54,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Nothing happening here yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Be the first neighbor to share an update,\nask a question, or help your local\ncommunity.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor: AppColors.primary.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Create First Post',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
              onPressed: _openCreatePostScreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingCreateButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 100),
      child: PressableScale(
        onTap: _openCreatePostScreen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: Colors.white, size: 18),
              SizedBox(width: 4),
              Text(
                'Create',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCreatePostScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          repository: widget.repository,
          authorHandle: widget.currentUserHandle,
        ),
      ),
    );
    if (result == true) {
      RewardsService.instance.fetchSummary(forceRefresh: true);
    }
    widget.repository.refresh();
  }

  void _showReportContentSheet(String postId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Report content',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Help keep Nearhood safe.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                _buildReportCard(
                  ctx: ctx,
                  postId: postId,
                  icon: Icons.warning_amber_rounded,
                  iconBgColor: const Color(0xFFFEF3C7),
                  iconColor: const Color(0xFFD97706),
                  title: 'Harassment / Impersonation',
                  subtitle: 'Targeting or pretending to be someone else',
                ),
                const SizedBox(height: 12),
                _buildReportCard(
                  ctx: ctx,
                  postId: postId,
                  icon: Icons.lock_rounded,
                  iconBgColor: const Color(0xFFEFF6FF),
                  iconColor: const Color(0xFF2563EB),
                  title: 'Personal information',
                  subtitle: 'Shares private details without consent',
                ),
                const SizedBox(height: 12),
                _buildReportCard(
                  ctx: ctx,
                  postId: postId,
                  icon: Icons.block_rounded,
                  iconBgColor: AppColors.chipBg,
                  iconColor: AppColors.textMuted,
                  title: 'Spam / Scams',
                  subtitle: 'Misleading, repetitive, or fraudulent content',
                ),
                const SizedBox(height: 12),
                _buildReportCard(
                  ctx: ctx,
                  postId: postId,
                  icon: Icons.chat_bubble_rounded,
                  iconBgColor: AppColors.errorSoft,
                  iconColor: AppColors.error,
                  title: 'Hate Speech / Civic Threat',
                  subtitle: 'Hateful, violent, or threatening content',
                ),
                const SizedBox(height: 12),
                _buildReportCard(
                  ctx: ctx,
                  postId: postId,
                  icon: Icons.notification_important_rounded,
                  iconBgColor: const Color(0xFFFEE2E2),
                  iconColor: const Color(0xFFDC2626),
                  title: 'False Safety Alert',
                  subtitle: 'Fake emergency or misleading urgent notification',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportCard({
    required BuildContext ctx,
    required String postId,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            widget.repository.reportPost(postId, widget.currentUserHandle);
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Report submitted for "$title". Post hidden from your feed.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, String postId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete Post?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Are you sure you want to permanently delete this post? This action cannot be undone.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.repository.deletePostPermanently(postId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    content: const Text('Post permanently deleted.'),
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _PostCardItem extends StatefulWidget {
  final Post post;
  final PostRepository repository;
  final String currentUserHandle;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onProfileTap;

  const _PostCardItem({
    super.key,
    required this.post,
    required this.repository,
    required this.currentUserHandle,
    required this.onDelete,
    required this.onReport,
    required this.onProfileTap,
  });

  @override
  State<_PostCardItem> createState() => _PostCardItemState();
}

class _PostCardItemState extends State<_PostCardItem> with AutomaticKeepAliveClientMixin {
  bool _isExpanded = false;

  @override
  bool get wantKeepAlive => true;

  static String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Widget _buildCategoryChip(PostCategory category) {
    Color bg;
    Color fg;

    switch (category) {
      case PostCategory.alerts:
      case PostCategory.safetyAlert:
      case PostCategory.safety:
        bg = AppColors.errorSoft;
        fg = AppColors.errorSoftText;
        break;
      case PostCategory.events:
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF1D4ED8);
        break;
      case PostCategory.question:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        break;
      case PostCategory.food:
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFFC2410C);
        break;
      case PostCategory.shop:
        bg = const Color(0xFFF0FDF4);
        fg = const Color(0xFF15803D);
        break;
      case PostCategory.rooms:
        bg = const Color(0xFFF5F3FF);
        fg = const Color(0xFF6D28D9);
        break;
      case PostCategory.jobs:
        bg = const Color(0xFFECFEFF);
        fg = const Color(0xFF0E7490);
        break;
      default:
        bg = AppColors.chipBg;
        fg = AppColors.primary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            category.icon,
            style: const TextStyle(fontSize: 10),
          ),
          const SizedBox(width: 3.5),
          Text(
            category.label,
            style: TextStyle(
              color: fg,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final post = widget.repository.getPostById(widget.post.id) ?? widget.post;
    final isEmergency = post.isEmergency;
    final isLongText = post.content.length > 220;
    final displayContent = (isLongText && !_isExpanded)
        ? '${post.content.substring(0, 220)}...'
        : post.content;

    final isEvent = post.category == PostCategory.events || post.eventTitle != null;
    final isUrgent = isEmergency || post.content.toLowerCase().contains('water') || post.content.toLowerCase().contains('theft');

    final dayStr = post.createdAt.day.toString().padLeft(2, '0');
    final monthStr = const ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][post.createdAt.month - 1];

    final cardBg = isUrgent ? const Color(0xFFFFF7F7) : AppColors.surface;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isUrgent
                ? AppColors.error.withValues(alpha: 0.35)
                : AppColors.cardBorder,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isUrgent
                  ? AppColors.error.withValues(alpha: 0.08)
                  : AppColors.primary.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.isPinned)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.divider.withValues(alpha: 0.6),
                          width: 0.8,
                        ),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.push_pin_rounded, size: 13, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text(
                          'OFFICIAL CITY GUIDE',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (isUrgent)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.white),
                        SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'URGENT SAFETY ALERT • NEIGHBORHOOD BROADCAST',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      UserAvatar(
                        handle: post.authorHandle,
                        size: 42,
                        fontSize: 15,
                        onTap: widget.onProfileTap,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final authorName = getDisplayName(
                              post.authorHandle,
                              fallback: post.authorName,
                            );
                            final authorBadge = BadgeCacheService.instance.getUserBadge(
                              post.authorHandle,
                              fallback: post.authorBadge,
                            );
                            final isAuthorVerified = BadgeCacheService.instance.isUserVerified(
                              post.authorHandle,
                              fallback: post.isVerified,
                            );
                            final fallbackCity = context.read<LocationService>().city.name;
                            String cleanArea = post.areaName != null && post.areaName!.isNotEmpty
                                ? post.areaName!
                                : fallbackCity;
                            if (cleanArea.contains('General / All')) {
                              cleanArea = cleanArea.replaceAll('General / All', 'General · All');
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: widget.onProfileTap,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          authorName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.textPrimary,
                                            fontSize: 14.5,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                      if (isAuthorVerified || (authorBadge != null && authorBadge.isNotEmpty)) ...[
                                        const SizedBox(width: 4),
                                        VerifiedBadge(
                                          isVerified: isAuthorVerified,
                                          badgeText: authorBadge,
                                          compact: true,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () async {
                                        final lat = post.lat;
                                        final lng = post.lng;
                                        Uri uri;
                                        if (lat != null && lng != null) {
                                          uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
                                        } else {
                                          final query = Uri.encodeComponent('$cleanArea, Gujarat, India');
                                          uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
                                        }
                                        try {
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                                          }
                                        } catch (_) {}
                                      },
                                      borderRadius: BorderRadius.circular(999),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.location_on_rounded,
                                            size: 11,
                                            color: AppColors.primary,
                                          ),
                                          const SizedBox(width: 2),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 110),
                                            child: Text(
                                              cleanArea,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors.primary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Text(
                                      '·',
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _formatTimeAgo(post.createdAt),
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildCategoryChip(post.category),
                      const SizedBox(width: 2),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () {
                          if (post.authorHandle == widget.currentUserHandle) {
                            widget.onDelete();
                          } else {
                            widget.onReport();
                          }
                        },
                      ),
                    ],
                  ),
                ),

                if (isEvent)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF7F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.cardBorder,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 50,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                width: 0.8,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dayStr,
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    height: 1.1,
                                  ),
                                ),
                                Text(
                                  monthStr,
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  post.eventTitle ?? post.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.schedule_rounded,
                                      size: 12,
                                      color: AppColors.textMuted,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        '${post.eventLocationText ?? "Vadodara"} · ${post.eventDate ?? "8:00 AM"}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${post.eventRsvpCount > 0 ? post.eventRsvpCount : 42} going',
                              style: const TextStyle(
                                color: AppColors.primaryText,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Text.rich(
                    TextSpan(
                      text: displayContent,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14.5,
                        height: 1.45,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.15,
                      ),
                      children: [
                        if (isLongText)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isExpanded = !_isExpanded;
                                });
                              },
                              child: Text(
                                _isExpanded ? '  Show less' : '  Read more',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                if ((post.imageUrl != null && post.imageUrl!.isNotEmpty) || post.mediaUrls.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: PostImageView(
                      imageUrl: (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                          ? post.imageUrl!
                          : post.mediaUrls.first,
                      allImages: post.mediaUrls.isNotEmpty
                          ? post.mediaUrls
                          : [post.imageUrl!],
                      height: 240,
                      borderRadius: BorderRadius.circular(14),
                      heroTagPrefix: 'feed_post_${post.id}',
                      caption: post.content,
                      overlay: post.foodRating != null
                          ? Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${post.foodRating}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Color(0xFFFBBF24),
                                      size: 14,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      LikeCapsule(
                        post: post,
                        repository: widget.repository,
                      ),
                      const SizedBox(width: 8),
                      InkWell(
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
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F5F8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.cardBorder,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${post.commentCount}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppColors.primary,
                              content: Text('Post link copied to clipboard!'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F5F8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.cardBorder,
                              width: 0.8,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.share_outlined,
                                size: 15,
                                color: AppColors.textMuted,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Share',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
