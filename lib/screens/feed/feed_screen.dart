import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../chat/widgets/voice_note_bubble.dart';
import '../../theme/app_colors.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/location/location_service.dart';
import '../../core/widgets/post_image_view.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/like_capsule.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../../features/feed/widgets/ai_voice_post_sheet.dart';
import '../create/create_post_screen.dart';
import '../detail/post_detail_screen.dart';
import '../notifications/notifications_screen.dart';
import '../../services/notification_service.dart';
import '../profile/other_user_profile_sheet.dart';
import '../profile/profile_screen.dart';
import '../../core/services/app_image_cache_service.dart';
import '../../core/services/badge_cache_service.dart';
import '../../core/widgets/verified_badge.dart';
import '../../services/rewards_service.dart';
import '../rewards/rewards_hub_screen.dart';
import '../../services/app_asset_service.dart';
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
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SlidingCategoryTabBar(
        categories: _feedCategoryFilters,
        selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
        isScrollable: true,
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
                      key: ValueKey('feed_general_posts_$_selectedFilterChip'),
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
                              bottom: 120 + MediaQuery.paddingOf(context).bottom,
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PressableScale(
            onTap: _openAiVoicePostSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7EAF5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: AppColors.primary, size: 16),
                  SizedBox(width: 5),
                  Icon(Icons.mic, color: AppColors.primary, size: 18),
                  SizedBox(width: 4),
                  Text(
                    'AI Voice',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          PressableScale(
            onTap: _openCreatePostScreen,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
        ],
      ),
    );
  }

  Future<void> _openAiVoicePostSheet() async {
    final result = await AiVoicePostSheet.show(
      context,
      repository: widget.repository,
      currentUserHandle: widget.currentUserHandle,
      directPublish: true,
    );
    if (result == true && mounted) {
      widget.repository.refresh();
    }
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
                  icon: Icons.explicit_rounded,
                  iconBgColor: const Color(0xFFFEE2E2),
                  iconColor: const Color(0xFFDC2626),
                  title: 'Adult / Obscene Content',
                  subtitle: 'Pornographic, explicit, or sexually inappropriate media',
                  reason: 'adult_content',
                ),
                const SizedBox(height: 12),
                _buildReportCard(
                  ctx: ctx,
                  postId: postId,
                  icon: Icons.warning_amber_rounded,
                  iconBgColor: const Color(0xFFFEF3C7),
                  iconColor: const Color(0xFFD97706),
                  title: 'Harassment / Impersonation',
                  subtitle: 'Targeting or pretending to be someone else',
                  reason: 'harassment',
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
                  reason: 'personal_info',
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
                  reason: 'spam_scam',
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
                  reason: 'hate_speech',
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
                  reason: 'false_alert',
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
    required String reason,
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
            widget.repository.reportPost(postId, widget.currentUserHandle, reason: reason);
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
        bg = const Color(0xFFFCEBEB);
        fg = const Color(0xFF791F1F);
        break;
      case PostCategory.question:
        bg = const Color(0xFFFFF3D6);
        fg = const Color(0xFF7A5200);
        break;
      case PostCategory.events:
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF1D4ED8);
        break;
      default:
        bg = const Color(0xFFF6EEF4);
        fg = const Color(0xFF3B1038);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        category.label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final post = widget.repository.getPostById(widget.post.id) ?? widget.post;
    final isEmergency = post.isEmergency;
    final isEvent = post.category == PostCategory.events || post.eventTitle != null;
    final isUrgent = isEmergency ||
        post.category == PostCategory.alerts ||
        post.category == PostCategory.safetyAlert ||
        post.category == PostCategory.safety ||
        post.postType == 'emergency';

    final dayStr = post.createdAt.day.toString().padLeft(2, '0');
    final monthStr = const ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][post.createdAt.month - 1];

    final cleanHandle = post.authorHandle.replaceAll('@', '').trim();
    final authorHandle = '@$cleanHandle';

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isUrgent ? const Color(0xFFFFF9F9) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isUrgent ? const Color(0xFFE24B4A) : const Color(0xFFEBDCE8),
            width: isUrgent ? 1.5 : 0.5,
          ),
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
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (post.isPinned)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE24B4A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Urgent safety alert · Local broadcast',
                            style: TextStyle(
                              color: Color(0xFFA32D2D),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: const Color(0xFFE24B4A),
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              'Priority',
                              style: TextStyle(
                                color: Color(0xFFA32D2D),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      UserAvatar(
                        handle: post.authorHandle,
                        size: 36,
                        fontSize: 13,
                        backgroundColor: isUrgent ? const Color(0xFF791F1F) : const Color(0xFF3B1038),
                        foregroundColor: Colors.white,
                        onTap: widget.onProfileTap,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Builder(
                          builder: (context) {
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
                            String locationText = cleanArea;
                            if (post.distanceKm != null) {
                              if (post.distanceKm! <= 0.6) {
                                locationText = '$cleanArea · Nearby';
                              } else {
                                locationText = '$cleanArea · ${post.distanceKm!.toStringAsFixed(1)}km';
                              }
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
                                          authorHandle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF2A1027),
                                            fontSize: 14,
                                            letterSpacing: -0.1,
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
                                const SizedBox(height: 1.5),
                                Text(
                                  '$locationText · ${_formatTimeAgo(post.createdAt)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF7A5C76),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildCategoryChip(post.category),
                      const SizedBox(width: 2),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: Color(0xFF7A5C76),
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

                  if (isEvent)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF7F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFEBDCE8),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 46,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    dayStr,
                                    style: const TextStyle(
                                      color: AppColors.primaryText,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      height: 1.1,
                                    ),
                                  ),
                                  Text(
                                    monthStr,
                                    style: const TextStyle(
                                      color: AppColors.primaryText,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    post.eventTitle ?? post.content,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF2A1027),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${post.eventLocationText ?? "Vadodara"} · ${post.eventDate ?? "8:00 AM"}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF7A5C76),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${post.eventRsvpCount > 0 ? post.eventRsvpCount : 42} going',
                                style: const TextStyle(
                                  color: AppColors.primaryText,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const postTextStyle = TextStyle(
                          color: Color(0xFF2A1027),
                          fontSize: 14.5,
                          height: 1.45,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -0.1,
                        );

                        final span = TextSpan(text: post.content, style: postTextStyle);
                        final tp = TextPainter(
                          text: span,
                          maxLines: 3,
                          textDirection: Directionality.of(context),
                        );
                        tp.layout(maxWidth: constraints.maxWidth);
                        final hasOverflow = tp.didExceedMaxLines || post.content.split('\n').length > 3;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.content,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: postTextStyle,
                            ),
                            if (hasOverflow)
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: GestureDetector(
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
                                  child: const Text(
                                    'Read more',
                                    style: TextStyle(
                                      color: Color(0xFF3B1038),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),

                  if (post.audioUrl != null && post.audioUrl!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: VoiceNoteBubble(
                        audioUrl: post.audioUrl!,
                        durationSeconds: 30,
                        waveformData: const [],
                        isMe: false,
                        timeStr: '',
                        isRead: true,
                        status: 'sent',
                      ),
                    ),

                  if ((post.imageUrl != null && post.imageUrl!.isNotEmpty) || post.mediaUrls.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: PostImageView(
                        imageUrl: (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                            ? post.imageUrl!
                            : post.mediaUrls.first,
                        allImages: post.mediaUrls.isNotEmpty
                            ? post.mediaUrls
                            : [post.imageUrl!],
                        height: 210,
                        borderRadius: BorderRadius.circular(14),
                        heroTagPrefix: 'feed_post_${post.id}',
                        caption: post.content,
                        overlay: post.foodRating != null
                            ? Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${post.foodRating}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(
                                        Icons.star_rounded,
                                        color: Color(0xFFFBBF24),
                                        size: 13,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        LikeCapsule(
                          post: post,
                          repository: widget.repository,
                          isCompact: true,
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
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6EEF4),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFEBDCE8),
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 15,
                                  color: Color(0xFF3B1038),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${post.commentCount}',
                                  style: const TextStyle(
                                    color: Color(0xFF3B1038),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () async {
                            final text = post.content.isNotEmpty ? post.content : 'Community update on Nearhood';
                            final area = post.areaName ?? 'Vadodara';
                            final shareMessage = '$text\n\n📍 $area\n🔗 https://nearhood.in/p/${post.id}\n\nJoin the Vadodara Community on Nearhood: https://nearhood.in';
                            await SharePlus.instance.share(ShareParams(text: shareMessage, subject: 'Nearhood Update'));
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6EEF4),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFEBDCE8),
                                width: 0.5,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.share_outlined,
                                  size: 14,
                                  color: Color(0xFF3B1038),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Share',
                                  style: TextStyle(
                                    color: Color(0xFF3B1038),
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
      ),
    );
  }
}
