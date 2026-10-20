import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import '../friends/friends_screen.dart';
import '../../services/friend_repository.dart';
import '../notifications/notifications_screen.dart';
import '../../services/notification_service.dart';
import '../profile/other_user_profile_sheet.dart';
import '../../core/services/app_image_cache_service.dart';
import '../../core/services/name_cache_service.dart';
import '../../core/services/badge_cache_service.dart';
import '../../core/widgets/verified_badge.dart';
import '../../services/rewards_service.dart';
import '../rewards/rewards_hub_screen.dart';
import '../../core/widgets/sliding_category_tab_bar.dart';

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
  late final FriendRepository _friendRepository;
  late final Stream<int> _pendingRequestsStream;
  String _selectedFilterChip = 'All';

  static const List<String> _feedCategoryFilters = [
    'All',
    'General',
    'Question',
    'Events',
    'Alerts',
    'Safety',
  ];

  List<Post> _getFilteredPosts(List<Post> posts) {
    if (_selectedFilterChip == 'All') return posts;

    if (_selectedFilterChip == 'General') {
      return posts.where((p) => p.category == PostCategory.general && !p.isEmergency).toList();
    }

    if (_selectedFilterChip == 'Question') {
      return posts
          .where((p) =>
              p.category == PostCategory.question ||
              (p.category == PostCategory.general && p.content.contains('?')))
          .toList();
    }

    if (_selectedFilterChip == 'Events') {
      return posts.where((p) => p.category == PostCategory.events || p.eventTitle != null).toList();
    }

    if (_selectedFilterChip == 'Alerts') {
      return posts.where((p) => p.category == PostCategory.alerts).toList();
    }

    if (_selectedFilterChip == 'Safety') {
      return posts
          .where((p) =>
              p.category == PostCategory.safety ||
              p.category == PostCategory.safetyAlert ||
              p.isEmergency)
          .toList();
    }

    return posts;
  }

  Widget _buildFilterChipsRow() {
    final selectedIndex = _feedCategoryFilters.indexOf(_selectedFilterChip);
    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SlidingCategoryTabBar(
        categories: _feedCategoryFilters,
        selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
        onSelected: (index) {
          final chip = _feedCategoryFilters[index];
          if (_selectedFilterChip != chip) {
            setState(() {
              _selectedFilterChip = chip;
            });
          }
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _friendRepository = FriendRepository()..currentUserHandle = widget.currentUserHandle;
    _pendingRequestsStream = _friendRepository.getPendingRequestCount();
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
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        automaticallyImplyLeading: false,
        toolbarHeight: 62,
        title: Row(
          children: [
            Expanded(
              child: Builder(
                builder: (context) {
                  final locService = context.watch<LocationService>();
                  final areaName = (locService.area?.name != null && locService.area!.name.trim().isNotEmpty)
                      ? locService.area!.name
                      : (locService.city.areas.firstOrNull?.name ?? locService.city.name);
                  final cityName = locService.city.name;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        areaName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            color: AppColors.primary,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              cityName,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            if (RewardsService.isRewardsEnabled) ...[
              const SizedBox(width: 8),
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
            ],
            const SizedBox(width: 8),
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.divider,
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.notifications_rounded,
                          color: AppColors.textPrimary,
                          size: 20,
                        ),
                        if (count > 0)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                count > 99 ? '99+' : '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
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
            const SizedBox(width: 8),
            StreamBuilder<int>(
              stream: _pendingRequestsStream,
              builder: (context, snap) {
                final count = snap.data ?? 0;
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FriendsScreen(
                          repository: _friendRepository,
                          currentUserHandle: widget.currentUserHandle,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.divider,
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.people_alt_rounded,
                          color: AppColors.textPrimary,
                          size: 20,
                        ),
                        if (count > 0)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
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
      body: Column(
        children: [
          _buildFilterChipsRow(),
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
                      key: ValueKey('feed_general_chat_$_selectedFilterChip'),
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
                                    widget.onOpenProfileTab?.call();
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
    return PressableScale(
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
    final isAlert = isEmergency || post.category == PostCategory.safetyAlert;
    final isLostPet = post.content.toLowerCase().contains('missing') ||
        post.content.toLowerCase().contains('labrador') ||
        post.content.toLowerCase().contains('pet');
    final isUrgent = isEmergency || post.content.toLowerCase().contains('water') || post.content.toLowerCase().contains('theft');

    final dayStr = post.createdAt.day.toString().padLeft(2, '0');
    final monthStr = const ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][post.createdAt.month - 1];

    Color cardBg = AppColors.surface;
    if (isUrgent) {
      cardBg = AppColors.errorSoft;
    }

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          border: Border(
            bottom: BorderSide(
              color: isUrgent
                  ? AppColors.error.withValues(alpha: 0.35)
                  : const Color(0xFFF1F5F9),
              width: 1.0,
            ),
          ),
        ),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUrgent) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 18, color: Colors.white),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '🚨 URGENT SAFETY ALERT • NEIGHBORHOOD BROADCAST',
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
                  ],

                  if (isEvent) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 54,
                          height: 58,
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.primarySoft),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dayStr,
                                style: const TextStyle(
                                  color: AppColors.primaryText,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                monthStr,
                                style: const TextStyle(
                                  color: AppColors.primaryText,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.eventTitle ?? post.content,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${post.eventLocationText ?? "Society garden, Gotri"} · ${post.eventDate ?? "8:00 AM"}',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${post.eventRsvpCount > 0 ? post.eventRsvpCount : 42} going',
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        UserAvatar(
                          handle: post.authorHandle,
                          size: 40,
                          fontSize: 14,
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

                              return Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 5,
                                runSpacing: 3,
                                children: [
                                  GestureDetector(
                                    onTap: widget.onProfileTap,
                                    child: Text(
                                      authorName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                        fontSize: 14.5,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  if (isAuthorVerified || (authorBadge != null && authorBadge.isNotEmpty))
                                    VerifiedBadge(
                                      isVerified: isAuthorVerified,
                                      badgeText: authorBadge,
                                      compact: true,
                                    ),
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
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFECFDF5),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: const Color(0xFF0E8A3E).withValues(alpha: 0.25),
                                          width: 0.6,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.location_on_rounded,
                                            size: 10,
                                            color: Color(0xFF0E8A3E),
                                          ),
                                          const SizedBox(width: 2.5),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 110),
                                            child: Text(
                                              cleanArea,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF065F46),
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '• ${_formatTimeAgo(post.createdAt)}',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        const SizedBox(width: 8),

                        Builder(
                          builder: (_) {
                            Color bg = AppColors.chipBg;
                            Color text = AppColors.textPrimary;
                            String label = 'General';

                            if (isUrgent) {
                              bg = AppColors.error;
                              text = Colors.white;
                              label = 'Urgent';
                            } else if (isAlert || post.category == PostCategory.safetyAlert || post.category == PostCategory.safety) {
                              bg = AppColors.errorSoft;
                              text = AppColors.errorSoftText;
                              label = 'Safety';
                            } else if (post.category == PostCategory.alerts) {
                              bg = const Color(0xFFFEF3C7);
                              text = const Color(0xFFB45309);
                              label = 'Alerts';
                            } else if (post.category == PostCategory.question) {
                              bg = AppColors.primarySoft;
                              text = AppColors.primaryText;
                              label = 'Question';
                            } else if (post.category == PostCategory.events) {
                              bg = const Color(0xFFEDE9FE);
                              text = const Color(0xFF6D28D9);
                              label = 'Events';
                            } else if (isLostPet) {
                              bg = const Color(0xFFFEF3C7);
                              text = const Color(0xFFB45309);
                              label = 'Lost pet';
                            } else {
                              bg = AppColors.chipBg;
                              text = AppColors.textPrimary;
                              label = post.category.label;
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: text,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  Text.rich(
                    TextSpan(
                      text: displayContent,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        height: 1.45,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.15,
                      ),
                      children: [
                        if (isLongText && !_isExpanded)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isExpanded = true;
                                });
                              },
                              child: const Text(
                                ' Read more',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  if ((post.imageUrl != null && post.imageUrl!.isNotEmpty) || post.mediaUrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    PostImageView(
                      imageUrl: (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                          ? post.imageUrl!
                          : post.mediaUrls.first,
                      allImages: post.mediaUrls.isNotEmpty
                          ? post.mediaUrls
                          : [post.imageUrl!],
                      height: 250,
                      borderRadius: BorderRadius.circular(16),
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
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(12),
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
                  ],

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      LikeCapsule(
                        post: post,
                        repository: widget.repository,
                      ),

                      const SizedBox(width: 14),

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
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${post.commentCount}',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 14),

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
                        borderRadius: BorderRadius.circular(18),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.share_outlined,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Share',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),

                      IconButton(
                        visualDensity: VisualDensity.compact,
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

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
