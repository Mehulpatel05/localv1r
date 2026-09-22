import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/widgets/post_image_view.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/vote_capsule.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../create/create_post_screen.dart';
import '../detail/post_detail_screen.dart';
import '../friends/friends_screen.dart';
import '../../services/friend_repository.dart';
import '../notifications/notifications_screen.dart';
import '../../services/notification_service.dart';
import '../profile/other_user_profile_sheet.dart';
import '../events/events_screen.dart';
import '../food/food_screen.dart';
import '../jobs/jobs_screen.dart';
import '../rooms/rooms_screen.dart';
import '../services/services_screen.dart';
import '../shop/shop_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _friendRepository = FriendRepository()..currentUserHandle = widget.currentUserHandle;
    _pendingRequestsStream = _friendRepository.getPendingRequestCount();
    widget.repository.addListener(_onRepositoryUpdated);
    if (widget.repository.selectedCategory == null) {
      widget.repository.setCategory(PostCategory.general);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onRepositoryUpdated);
    super.dispose();
  }

  void _onRepositoryUpdated() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.location_on_outlined,
                color: isDark ? Colors.white : Colors.black,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Vadodara',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          // Notification bell icon & unread count
          StreamBuilder<int>(
            stream: NotificationService().getUnreadNotificationCount(widget.currentUserHandle),
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return IconButton(
                tooltip: 'Notifications',
                icon: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.notifications_outlined,
                        color: isDark ? Colors.white : Colors.black,
                        size: 20,
                      ),
                      if (count > 0)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
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
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsScreen(
                        currentUserHandle: widget.currentUserHandle,
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // Friends stream count & icon
          Padding(
            padding: const EdgeInsets.only(right: 14.0),
            child: StreamBuilder<int>(
              stream: _pendingRequestsStream,
              builder: (context, snap) {
                final count = snap.data ?? 0;
                return IconButton(
                  tooltip: 'Friends',
                  icon: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
                          color: isDark ? Colors.white : Colors.black,
                          size: 20,
                        ),
                        if (count > 0)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
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
                  onPressed: () {
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
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Controls: Categories Bar
          Container(
            color: isDark ? Colors.black : Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _buildCategoriesBar(repo),
          ),

          // Feed List or Loading or Empty State
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.durationStandard,
              switchInCurve: AppMotion.enterCurve,
              switchOutCurve: AppMotion.exitCurve,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: repo.isLoading
                  ? _buildLoadingSkeleton()
                  : KeyedSubtree(
                      key: ValueKey('feed_category_${repo.selectedCategory?.name ?? "all"}'),
                      child: RefreshIndicator(
                        onRefresh: widget.repository.refresh,
                        color: isDark ? Colors.white : Colors.black,
                        child: repo.posts.isEmpty
                            ? SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: SizedBox(
                                  height: MediaQuery.of(context).size.height * 0.62,
                                  child: _buildEmptyState(),
                                ),
                              )
                            : ListView.builder(
                                physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                                // ignore: deprecated_member_use
                                cacheExtent: 800.0,
                                addRepaintBoundaries: true,
                                addAutomaticKeepAlives: true,
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 84,
                                  left: 16,
                                  right: 16,
                                ),
                                itemCount: repo.posts.length,
                                itemBuilder: (context, index) {
                                  final post = repo.posts[index];
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
                              ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingCreateButton(),
    );
  }

  static IconData _getCategoryIconData(PostCategory cat) {
    switch (cat) {
      case PostCategory.general:
        return Icons.chat_bubble_outline_rounded;
      case PostCategory.services:
        return Icons.build_outlined;
      case PostCategory.food:
        return Icons.restaurant_outlined;
      case PostCategory.rooms:
        return Icons.home_outlined;
      case PostCategory.shop:
        return Icons.shopping_bag_outlined;
      case PostCategory.events:
        return Icons.celebration_outlined;
      case PostCategory.jobs:
        return Icons.work_outline_rounded;
    }
  }

  static String _getCategoryDisplayLabel(PostCategory cat) {
    if (cat == PostCategory.food) return 'Restaurants';
    return cat.label;
  }

  Widget _buildCategoriesBar(PostRepository repo) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Hide 'Jobs & Referrals' chip from UI while preserving all jobs code & screens
    final categories = PostCategory.values.where((c) => c != PostCategory.jobs).toList();

    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          VoidCallback onTap;
          if (cat == PostCategory.rooms) {
            onTap = () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoomsScreen(
                      repository: widget.repository,
                      currentUserHandle: widget.currentUserHandle,
                    ),
                  ),
                );
          } else if (cat == PostCategory.food) {
            onTap = () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FoodScreen(
                      repository: widget.repository,
                      currentUserHandle: widget.currentUserHandle,
                    ),
                  ),
                );
          } else if (cat == PostCategory.events) {
            onTap = () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventsScreen(
                      repository: widget.repository,
                      currentUserHandle: widget.currentUserHandle,
                    ),
                  ),
                );
          } else if (cat == PostCategory.jobs) {
            onTap = () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JobsScreen(
                      repository: widget.repository,
                      currentUserHandle: widget.currentUserHandle,
                    ),
                  ),
                );
          } else if (cat == PostCategory.shop) {
            onTap = () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShopScreen(
                      repository: widget.repository,
                      currentUserHandle: widget.currentUserHandle,
                    ),
                  ),
                );
          } else if (cat == PostCategory.services) {
            onTap = () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServicesScreen(
                      repository: widget.repository,
                      currentUserHandle: widget.currentUserHandle,
                    ),
                  ),
                );
          } else {
            onTap = () => repo.setCategory(cat);
          }

          final isSelected = repo.selectedCategory == cat;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _buildCategoryChip(
              label: _getCategoryDisplayLabel(cat),
              iconData: _getCategoryIconData(cat),
              isSelected: isSelected,
              onTap: onTap,
              isDark: isDark,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required IconData iconData,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final bgColor = isSelected
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4));
    final fgColor = isSelected
        ? (isDark ? Colors.black : Colors.white)
        : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF4B5563));
    final borderColor = isSelected
        ? Colors.transparent
        : (isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6));

    return PressableScale(
      onTap: onTap,
      targetScale: 0.96,
      child: AnimatedContainer(
        duration: AppMotion.durationMicro,
        curve: AppMotion.interactiveCurve,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconData, size: 15, color: fgColor),
            const SizedBox(width: 7),
            AnimatedDefaultTextStyle(
              duration: AppMotion.durationMicro,
              curve: AppMotion.interactiveCurve,
              style: TextStyle(
                color: fgColor,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Skeleton
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE2E8F0),
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
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 60,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
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
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Body Lines Skeleton
              Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 220,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 14),
              // Media Box Skeleton
              Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 14),
              // Bottom Bar Skeleton
              Row(
                children: [
                  Container(
                    width: 80,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 60,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Minimalist geometric neighborhood illustration
            Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF0F7FF),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Little house on top
                  Positioned(
                    top: 28,
                    right: 44,
                    child: const Icon(
                      Icons.home_rounded,
                      size: 16,
                      color: Color(0xFF93C5FD),
                    ),
                  ),
                  // Geometric building shapes
                  Positioned(
                    bottom: 32,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Left blue building
                        Container(
                          width: 18,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white38 : Colors.black38,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Center tall slate building
                        Container(
                          width: 22,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Right purple building
                        Container(
                          width: 18,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Nothing happening here yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF0F172A),
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
                color: Color(0xFF64748B),
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xFF1E293B).withValues(alpha: 0.3),
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
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.add, size: 20, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Create',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCreatePostScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          repository: widget.repository,
          authorHandle: widget.currentUserHandle,
        ),
      ),
    );
    widget.repository.refresh();
  }

  // ── IMAGE 4: Report Content Sheet ("Report content") ──
  void _showReportContentSheet(String postId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                // Top Handle Grabber
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                const Text(
                  'Report content',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Help keep Nearhood safe.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),

                // 1. Harassment / Impersonation
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

                // 2. Personal information
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

                // 3. Spam / Scams
                _buildReportCard(
                  ctx: ctx,
                  postId: postId,
                  icon: Icons.block_rounded,
                  iconBgColor: const Color(0xFFF1F5F9),
                  iconColor: const Color(0xFF475569),
                  title: 'Spam / Scams',
                  subtitle: 'Misleading, repetitive, or fraudulent content',
                ),
                const SizedBox(height: 12),

                // 4. Hate Speech / Civic Threat
                _buildReportCard(
                  ctx: ctx,
                  postId: postId,
                  icon: Icons.chat_bubble_rounded,
                  iconBgColor: const Color(0xFFFEF2F2),
                  iconColor: const Color(0xFFEF4444),
                  title: 'Hate Speech / Civic Threat',
                  subtitle: 'Hateful, violent, or threatening content',
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            widget.repository.reportPost(postId, widget.currentUserHandle);
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF10B981),
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
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete Post?',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Are you sure you want to permanently delete this post? This action cannot be undone.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
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
                    backgroundColor: const Color(0xFFEF4444),
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
    final post = widget.post;
    final isEmergency = post.isEmergency;
    final isLongText = post.content.length > 220;
    final displayContent = (isLongText && !_isExpanded)
        ? '${post.content.substring(0, 220)}...'
        : post.content;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isEmergency
              ? (isDark ? const Color(0xFF2A1215) : const Color(0xFFFFF5F5))
              : (isDark ? const Color(0xFF141414) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isEmergency
                ? const Color(0xFFEF4444)
                : (isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
            width: isEmergency ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
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
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Emergency Banner if marked
                  if (isEmergency) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'EMERGENCY',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Card Header
                  Row(
                    children: [
                      UserAvatar(
                        handle: post.authorHandle,
                        size: 38,
                        fontSize: 14,
                        onTap: widget.onProfileTap,
                      ),
                      const SizedBox(width: 10),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: widget.onProfileTap,
                              child: Text(
                                '@${post.authorHandle}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Vadodara • ${_formatTimeAgo(post.createdAt)}',
                              style: TextStyle(
                                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Category Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF4F4F4),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                          ),
                        ),
                        child: Text(
                          post.category.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                          ),
                        ),
                      ),

                      // 3-dots Menu
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.only(left: 6),
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF8E8E93),
                          size: 22,
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

                  const SizedBox(height: 12),

                  // Post Content Text
                  Text.rich(
                    TextSpan(
                      text: displayContent,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
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
                              child: Text(
                                ' Read more',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Post Image if present
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

                  // Card Footer Actions
                  Row(
                    children: [
                      VoteCapsule(
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
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${post.commentCount}',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
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
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF8E8E93),
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
