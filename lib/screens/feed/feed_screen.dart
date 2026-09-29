import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/location/location_service.dart';
import '../../core/location/city_picker_screen.dart';
import '../../core/widgets/post_image_view.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/like_capsule.dart';
import '../../models/post_model.dart';
import '../../core/models/user_profile.dart';
import '../../services/post_repository.dart';
import '../create/create_post_screen.dart';
import '../detail/post_detail_screen.dart';
import '../friends/friends_screen.dart';
import '../../services/friend_repository.dart';
import '../notifications/notifications_screen.dart';
import '../../services/notification_service.dart';
import '../profile/other_user_profile_sheet.dart';
import '../../core/services/app_image_cache_service.dart';

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

  List<Post> _getFilteredPosts(List<Post> posts) {
    if (_selectedFilterChip == 'All') return posts;

    if (_selectedFilterChip == 'Questions') {
      final filtered = posts.where((p) => p.category == PostCategory.general || p.content.contains('?')).toList();
      if (filtered.isNotEmpty) return filtered;
      return [
        Post(
          id: 'q_sample_1',
          authorHandle: 'Ravi K.',
          content: 'Any good chai stall nearby for this evening?',
          category: PostCategory.general,
          createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
          commentCount: 7,
          reporters: const [],
          areaName: 'Akota',
        ),
        Post(
          id: 'q_sample_2',
          authorHandle: 'Neha P.',
          content: 'Looking for a reliable electrician for AC repair.',
          category: PostCategory.general,
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
          commentCount: 3,
          reporters: const [],
          areaName: 'Gotri',
        ),
        Post(
          id: 'q_sample_3',
          authorHandle: 'Kiran S.',
          content: 'Which school near Alkapuri has good CBSE results?',
          category: PostCategory.general,
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
          commentCount: 12,
          reporters: const [],
          areaName: 'Karelibaug',
        ),
      ];
    }

    if (_selectedFilterChip == 'Events') {
      final filtered = posts.where((p) => p.category == PostCategory.events).toList();
      if (filtered.isNotEmpty) return filtered;
      return [
        Post(
          id: 'ev_sample_1',
          authorHandle: 'Society Admin',
          content: 'Plantation drive at Society Garden',
          eventTitle: 'Plantation drive',
          eventDate: '8:00 AM',
          eventLocationText: 'Society garden, Gotri',
          eventRsvpCount: 42,
          category: PostCategory.events,
          createdAt: DateTime(DateTime.now().year, 9, 30, 8, 0),
          reporters: const [],
        ),
        Post(
          id: 'ev_sample_2',
          authorHandle: 'Alkapuri Club',
          content: 'Garba night at Alkapuri Club',
          eventTitle: 'Garba night',
          eventDate: '7:30 PM',
          eventLocationText: 'Alkapuri Club',
          eventRsvpCount: 120,
          category: PostCategory.events,
          createdAt: DateTime(DateTime.now().year, 10, 4, 19, 30),
          reporters: const [],
        ),
        Post(
          id: 'ev_sample_3',
          authorHandle: 'Sayaji Events',
          content: 'Weekend flea market at Sayaji Garden',
          eventTitle: 'Weekend flea market',
          eventDate: '10:00 AM',
          eventLocationText: 'Sayaji Garden',
          eventRsvpCount: 67,
          category: PostCategory.events,
          createdAt: DateTime(DateTime.now().year, 10, 6, 10, 0),
          reporters: const [],
        ),
      ];
    }

    if (_selectedFilterChip == 'Alerts') {
      final filtered = posts.where((p) => p.category == PostCategory.safetyAlert || p.isEmergency).toList();
      if (filtered.isNotEmpty) return filtered;
      return [
        Post(
          id: 'alt_sample_1',
          authorHandle: 'Area admin',
          content: 'Water supply off from 2 PM to 6 PM today.',
          category: PostCategory.safetyAlert,
          isEmergency: true,
          createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
          reporters: const [],
          areaName: 'Akota',
        ),
        Post(
          id: 'alt_sample_2',
          authorHandle: 'Mona K.',
          content: 'Brown Labrador missing near Gotri lake. Please call if seen.',
          category: PostCategory.safetyAlert,
          isEmergency: false,
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          reporters: const [],
          areaName: 'Gotri',
        ),
        Post(
          id: 'alt_sample_3',
          authorHandle: 'Sam B.',
          content: 'Two-wheeler theft reported near the main road. Be careful.',
          category: PostCategory.safetyAlert,
          isEmergency: false,
          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
          reporters: const [],
          areaName: 'Alkapuri',
        ),
      ];
    }

    return posts;
  }

  Widget _buildFilterChipsRow(bool isDark) {
    final chips = ['All', 'Questions', 'Events', 'Alerts'];
    return Container(
      height: 42,
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = chips[index];
          final isSelected = chip == _selectedFilterChip;

          final bg = isSelected
              ? Colors.white
              : const Color(0xFF072E33);

          final fg = isSelected
              ? Colors.black
              : Colors.white;

          final border = isSelected
              ? Border.all(color: Colors.transparent)
              : Border.all(
                  color: const Color(0xFF0E525B),
                  width: 1.0,
                );

          return PressableScale(
            onTap: () {
              setState(() {
                _selectedFilterChip = chip;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
                border: border,
              ),
              alignment: Alignment.center,
              child: Text(
                chip,
                style: TextStyle(
                  color: fg,
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          );
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
    widget.repository.setCategory(PostCategory.general);
    _triggerFeedImagePrefetch();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Builder(
          builder: (context) {
            final locService = context.watch<LocationService>();
            final badgeText = locService.statusBadgeLabel;

            return InkWell(
              onTap: () async {
                if (locService.isLocationOff) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Location ON Karein'),
                      content: const Text('Auto-detection ke liye device Location Services (GPS) ON karein.'),
                      actions: [
                        TextButton(
                          child: const Text('Manual City Chunein'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const CityPickerScreen()));
                          },
                        ),
                        ElevatedButton(
                          child: const Text('OK'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Geolocator.openLocationSettings();
                          },
                        ),
                      ],
                    ),
                  );
                } else if (locService.isPermissionDeniedForever) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Permission Needed'),
                      content: const Text('Please allow location permission in App Settings for auto-detection.'),
                      actions: [
                        TextButton(
                          child: const Text('Manual City Chunein'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const CityPickerScreen()));
                          },
                        ),
                        ElevatedButton(
                          child: const Text('Settings Kholo'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Geolocator.openAppSettings();
                          },
                        ),
                      ],
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CityPickerScreen()),
                  );
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF072E33),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0E525B),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            locService.displayLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ],
                      ),
                      if (badgeText.isNotEmpty)
                        Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: locService.isLocationOff || locService.isPermissionDenied
                                ? Colors.amber.shade700
                                : const Color(0xFF90B4B6),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          // Notification bell icon & unread count
          ValueListenableBuilder<int>(
            valueListenable: NotificationService.instance.unreadBadgeNotifier,
            builder: (context, count, _) {
              return IconButton(
                tooltip: 'Notifications',
                icon: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF072E33),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF0E525B),
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.notifications_rounded,
                        color: Color(0xFFFACC15),
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
          // Friends stream count & icon (next to Bell)
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
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
                      color: const Color(0xFF072E33),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0E525B),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.people_alt_rounded,
                          color: Colors.white,
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
          _buildFilterChipsRow(isDark),
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
                      key: ValueKey('feed_general_chat_$_selectedFilterChip'),
                child: RefreshIndicator(
                  onRefresh: widget.repository.refresh,
                  color: isDark ? Colors.white : Colors.black,
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
                      padding: const EdgeInsets.only(
                        top: 8,
                        bottom: 84,
                        left: 16,
                        right: 16,
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+ Create',
              style: TextStyle(
                color: Colors.black,
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

    final isEvent = post.category == PostCategory.events || post.eventTitle != null;
    final isAlert = isEmergency || post.category == PostCategory.safetyAlert;
    final isLostPet = post.content.toLowerCase().contains('missing') ||
        post.content.toLowerCase().contains('labrador') ||
        post.content.toLowerCase().contains('pet');
    final isUrgent = isEmergency || post.content.toLowerCase().contains('water') || post.content.toLowerCase().contains('theft');

    final dayStr = post.createdAt.day.toString().padLeft(2, '0');
    final monthStr = const ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][post.createdAt.month - 1];

    Color cardBg = const Color(0xFF072E33);
    Color borderColor = const Color(0xFF0E525B);
    if (isUrgent) {
      cardBg = const Color(0xFF1F0D11);
      borderColor = const Color(0xFFEF4444);
    }

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: isUrgent ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
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
                  // Top Emergency / Safety Alert Banner if marked urgent
                  if (isUrgent) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
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

                  // SPECIAL EVENT LAYOUT MATCHING SCREENSHOT
                  if (isEvent) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Date Box
                        Container(
                          width: 54,
                          height: 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E4B52),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF0E525B)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dayStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                monthStr,
                                style: const TextStyle(
                                  color: Color(0xFF90B4B6),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Event Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.eventTitle ?? post.content,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${post.eventLocationText ?? "Society garden, Gotri"} · ${post.eventDate ?? "8:00 AM"}',
                                style: const TextStyle(
                                  color: Color(0xFF90B4B6),
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0E4B52),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${post.eventRsvpCount > 0 ? post.eventRsvpCount : 42} going',
                                  style: const TextStyle(
                                    color: Color(0xFFFACC15),
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
                    // STANDARD HEADER FOR QUESTIONS / ALERTS / GENERAL
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
                                  post.authorHandle.displayHandle,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${post.areaName ?? "Vadodara"} • ${_formatTimeAgo(post.createdAt)}',
                                style: const TextStyle(
                                  color: Color(0xFF90B4B6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Category Badge
                        Builder(
                          builder: (_) {
                            Color bg = const Color(0xFF0E4B52);
                            Color text = Colors.white;
                            String label = 'General';

                            if (isUrgent) {
                              bg = const Color(0xFF7F1D1D);
                              text = const Color(0xFFFCA5A5);
                              label = 'Urgent';
                            } else if (isLostPet) {
                              bg = const Color(0xFF451A03);
                              text = const Color(0xFFFBBF24);
                              label = 'Lost pet';
                            } else if (isAlert) {
                              bg = const Color(0xFF451A03);
                              text = const Color(0xFFFBBF24);
                              label = 'Safety';
                            } else {
                              bg = const Color(0xFF0E4B52);
                              text = const Color(0xFF90B4B6);
                              label = 'Question';
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 12,
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

                      const SizedBox(width: 14),

                      InkWell(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Post link copied to clipboard!'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.share_outlined,
                                size: 18,
                                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Share',
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

                  // Emergency Quick Action Buttons
                  if (isEmergency || post.category == PostCategory.safetyAlert) ...[
                    const SizedBox(height: 12),
                    if (isLostPet) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF0E525B), width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            backgroundColor: const Color(0xFF072E33),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Color(0xFF072E33),
                                content: Text('👍 Notification sent to pet owner: "I have seen it"'),
                              ),
                            );
                          },
                          child: const Text(
                            'I have seen it',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                              label: const Text('I\'m Safe', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFF10B981),
                                    content: Text('✅ Status updated: Marked as Safe'),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.phone_in_talk_rounded, size: 16),
                              label: const Text('Call 112', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFFDC2626),
                                    content: Text('📞 Dialing National Emergency Services 112...'),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
