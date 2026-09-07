import 'package:flutter/material.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/location/location_chip.dart';
import '../../core/widgets/safe_image.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../communities/create_community_screen.dart';
import '../../services/community_repository.dart';
import '../create/create_post_screen.dart';
import '../detail/post_detail_screen.dart';
import '../friends/friends_screen.dart';
import '../../services/friend_repository.dart';
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

  const FeedScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_onRepositoryUpdated);
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            const LocationChip(),
            const SizedBox(width: 8),
            const Text(
              'Local',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black87,
                fontSize: 20,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          StreamBuilder<int>(
            stream: (FriendRepository()..currentUserHandle = widget.currentUserHandle).getPendingRequestCount(),
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return IconButton(
                tooltip: 'Friends',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.people, color: Colors.black87, size: 26),
                    if (count > 0)
                      Positioned(
                        right: -6,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(color: Colors.black87, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FriendsScreen(
                        repository: FriendRepository()..currentUserHandle = widget.currentUserHandle,
                        currentUserHandle: widget.currentUserHandle,
                      ),
                    ),
                  );
                },
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0, left: 4.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.currentUserHandle,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: repo.isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF3B82F6),
              ),
            )
          : Column(
              children: [
                // Horizontal Category filter bar
                Container(
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF1F293D), width: 1),
                    ),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    itemCount: PostCategory.values.length,
                    itemBuilder: (context, index) {
                      final cat = PostCategory.values[index];
                      // 🏠 Rooms chip — opens dedicated Rooms page
                      if (cat == PostCategory.rooms) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                transitionDuration:
                                    const Duration(milliseconds: 380),
                                reverseTransitionDuration:
                                    const Duration(milliseconds: 300),
                                pageBuilder: (_, __, ___) => RoomsScreen(
                                  repository: widget.repository,
                                  currentUserHandle: widget.currentUserHandle,
                                ),
                                transitionsBuilder:
                                    (_, animation, __, child) {
                                  final slide = Tween<Offset>(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ));
                                  final fade = Tween<double>(
                                          begin: 0.0, end: 1.0)
                                      .animate(CurvedAnimation(
                                    parent: animation,
                                    curve: const Interval(0.0, 0.6),
                                  ));
                                  return FadeTransition(
                                    opacity: fade,
                                    child: SlideTransition(
                                      position: slide,
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.black12),
                              ),
                              child: const Row(
                                children: [
                                  Text('🏠',
                                      style: TextStyle(fontSize: 13)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Rooms',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      size: 10,
                                      color: Color(0xFF60A5FA)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // 🍲 Food chip — opens dedicated Food page
                      if (cat == PostCategory.food) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                transitionDuration:
                                    const Duration(milliseconds: 380),
                                reverseTransitionDuration:
                                    const Duration(milliseconds: 300),
                                pageBuilder: (_, __, ___) => FoodScreen(
                                  repository: widget.repository,
                                  currentUserHandle: widget.currentUserHandle,
                                ),
                                transitionsBuilder:
                                    (_, animation, __, child) {
                                  final slide = Tween<Offset>(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ));
                                  final fade = Tween<double>(
                                          begin: 0.0, end: 1.0)
                                      .animate(CurvedAnimation(
                                    parent: animation,
                                    curve: const Interval(0.0, 0.6),
                                  ));
                                  return FadeTransition(
                                    opacity: fade,
                                    child: SlideTransition(
                                      position: slide,
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B2A1A), // Warm brown/orange tone
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFF59E0B)
                                        .withOpacity(0.6)),
                              ),
                              child: const Row(
                                children: [
                                  Text('🍲',
                                      style: TextStyle(fontSize: 13)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Food',
                                    style: TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      size: 10,
                                      color: Color(0xFFF59E0B)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // 🎉 Events chip — opens dedicated Events page
                      if (cat == PostCategory.events) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                transitionDuration:
                                    const Duration(milliseconds: 380),
                                reverseTransitionDuration:
                                    const Duration(milliseconds: 300),
                                pageBuilder: (_, __, ___) => EventsScreen(
                                  repository: widget.repository,
                                  currentUserHandle: widget.currentUserHandle,
                                ),
                                transitionsBuilder:
                                    (_, animation, __, child) {
                                  final slide = Tween<Offset>(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ));
                                  final fade = Tween<double>(
                                          begin: 0.0, end: 1.0)
                                      .animate(CurvedAnimation(
                                    parent: animation,
                                    curve: const Interval(0.0, 0.6),
                                  ));
                                  return FadeTransition(
                                    opacity: fade,
                                    child: SlideTransition(
                                      position: slide,
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF281C43), // Dark purple tone
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFF8B5CF6)
                                        .withOpacity(0.6)),
                              ),
                              child: const Row(
                                children: [
                                  Text('🎉',
                                      style: TextStyle(fontSize: 13)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Events',
                                    style: TextStyle(
                                      color: Color(0xFFC4B5FD),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      size: 10,
                                      color: Color(0xFFC4B5FD)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // 💼 Jobs chip — opens dedicated Jobs page
                      if (cat == PostCategory.jobs) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                transitionDuration:
                                    const Duration(milliseconds: 380),
                                reverseTransitionDuration:
                                    const Duration(milliseconds: 300),
                                pageBuilder: (_, __, ___) => JobsScreen(
                                  repository: widget.repository,
                                  currentUserHandle: widget.currentUserHandle,
                                ),
                                transitionsBuilder:
                                    (_, animation, __, child) {
                                  final slide = Tween<Offset>(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ));
                                  final fade = Tween<double>(
                                          begin: 0.0, end: 1.0)
                                      .animate(CurvedAnimation(
                                    parent: animation,
                                    curve: const Interval(0.0, 0.6),
                                  ));
                                  return FadeTransition(
                                    opacity: fade,
                                    child: SlideTransition(
                                      position: slide,
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B), // Dark slate
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFF64748B)
                                        .withOpacity(0.6)),
                              ),
                              child: const Row(
                                children: [
                                  Text('💼',
                                      style: TextStyle(fontSize: 13)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Jobs',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      size: 10,
                                      color: Color(0xFF94A3B8)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // 🛍️ Shop chip — opens dedicated Shop page
                      if (cat == PostCategory.shop) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                transitionDuration:
                                    const Duration(milliseconds: 380),
                                reverseTransitionDuration:
                                    const Duration(milliseconds: 300),
                                pageBuilder: (_, __, ___) => ShopScreen(
                                  repository: widget.repository,
                                  currentUserHandle: widget.currentUserHandle,
                                ),
                                transitionsBuilder:
                                    (_, animation, __, child) {
                                  final slide = Tween<Offset>(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ));
                                  final fade = Tween<double>(
                                          begin: 0.0, end: 1.0)
                                      .animate(CurvedAnimation(
                                    parent: animation,
                                    curve: const Interval(0.0, 0.6),
                                  ));
                                  return FadeTransition(
                                    opacity: fade,
                                    child: SlideTransition(
                                      position: slide,
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A3A2F),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFF10B981)
                                        .withOpacity(0.6)),
                              ),
                              child: const Row(
                                children: [
                                  Text('🛍️',
                                      style: TextStyle(fontSize: 13)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Shop',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      size: 10,
                                      color: Color(0xFF10B981)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // 🔧 Local Services chip — opens dedicated Services page
                      if (cat == PostCategory.services) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                transitionDuration:
                                    const Duration(milliseconds: 380),
                                reverseTransitionDuration:
                                    const Duration(milliseconds: 300),
                                pageBuilder: (_, __, ___) => ServicesScreen(
                                  repository: widget.repository,
                                  currentUserHandle: widget.currentUserHandle,
                                ),
                                transitionsBuilder:
                                    (_, animation, __, child) {
                                  final slide = Tween<Offset>(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ));
                                  final fade = Tween<double>(
                                          begin: 0.0, end: 1.0)
                                      .animate(CurvedAnimation(
                                    parent: animation,
                                    curve: const Interval(0.0, 0.6),
                                  ));
                                  return FadeTransition(
                                    opacity: fade,
                                    child: SlideTransition(
                                      position: slide,
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF), // Light blue
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.black12),
                              ),
                              child: const Row(
                                children: [
                                  Text('🔧',
                                      style: TextStyle(fontSize: 13)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Local Services',
                                    style: TextStyle(
                                      color: Color(0xFF3B82F6),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      size: 10,
                                      color: Color(0xFF3B82F6)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // All other chips — normal filter
                      final isSelected = repo.selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: InkWell(
                          onTap: () => repo.setCategory(cat),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF60A5FA)
                                    : Colors.black12,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(cat.icon,
                                    style: const TextStyle(fontSize: 13)),
                                const SizedBox(width: 6),
                                Text(
                                  cat.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black54,
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Feed List
                Builder(
                  builder: (context) {
                    final feedPosts = repo.posts;

                    return Expanded(
                      child: feedPosts.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: feedPosts.length,
                              itemBuilder: (context, index) {
                                final post = feedPosts[index];
                                return _buildPostCard(post);
                              },
                            ),
                    );
                  },
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF3B82F6),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            builder: (ctx) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.edit, color: Colors.white),
                      title: const Text('Create Global Post', style: TextStyle(color: Colors.black87)),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => CreatePostScreen(repository: widget.repository, authorHandle: widget.currentUserHandle)));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.group, color: Colors.white),
                      title: const Text('Create New Group', style: TextStyle(color: Colors.black87)),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => CreateCommunityScreen(repository: CommunityRepository()..currentUserHandle = widget.currentUserHandle, isChannel: false)));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.campaign, color: Colors.white),
                      title: const Text('Create New Channel', style: TextStyle(color: Colors.black87)),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => CreateCommunityScreen(repository: CommunityRepository()..currentUserHandle = widget.currentUserHandle, isChannel: true)));
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTabButton(FeedTab tab, String label) {
    final repo = widget.repository;
    final isSelected = repo.currentTab == tab;
    return InkWell(
      onTap: () => repo.setTab(tab),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black54,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'No posts in this area yet',
              style: TextStyle(color: Colors.black54, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Be the first to warn or update neighbors in Vadodara anonymously.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black38, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF8FAFC),
                foregroundColor: Colors.black87,
                side: const BorderSide(color: Colors.black12),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add First Post'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreatePostScreen(
                      repository: widget.repository,
                      authorHandle: widget.currentUserHandle,
                    ),
                  ),
                );
              },
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(Post post) {
    final repo = widget.repository;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: post.isEmergency ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: post.isEmergency ? const Color(0xFFFCA5A5) : Colors.black12,
          width: post.isEmergency ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PostDetailScreen(
                  post: post,
                  repository: repo,
                  currentUserHandle: widget.currentUserHandle,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (Author handle + Category + Area)
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (post.authorHandle != widget.currentUserHandle) {
                          showOtherUserProfileSheet(
                            context,
                            partnerHandle: post.authorHandle,
                            currentUserHandle: widget.currentUserHandle,
                            repository: widget.repository,
                          );
                        }
                      },
                      child: Text(
                        '@${post.authorHandle}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('•', style: TextStyle(color: Colors.black26)),
                    const SizedBox(width: 6),
                    Text(
                      'Vadodara',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: post.isEmergency ? const Color(0xFFFECACA) : Colors.black12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(post.category.icon, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            post.category.label,
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Post Content
                Text(
                  post.content,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                if (post.imageUrl != null && post.imageUrl!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SafeImage(
                    imageUrl: post.imageUrl!,
                    height: 180,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
                const SizedBox(height: 14),

                // Actions (Upvotes/Downvotes, Comments count, Report flag)
                Row(
                  children: [
                    // Upvote/Downvote container
                    Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.arrow_upward_rounded,
                              size: 18,
                              color: post.userVote == 1 ? const Color(0xFF10B981) : Colors.black54,
                            ),
                            onPressed: () => repo.votePost(post.id, 1),
                          ),
                          Text(
                            '${post.score}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: post.userVote == 1
                                  ? const Color(0xFF10B981)
                                  : (post.userVote == -1 ? const Color(0xFFEF4444) : Colors.black87),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.arrow_downward_rounded,
                              size: 18,
                              color: post.userVote == -1 ? const Color(0xFFEF4444) : Colors.black54,
                            ),
                            onPressed: () => repo.votePost(post.id, -1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Comments Icon
                    Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Colors.black54),
                        const SizedBox(width: 6),
                        Text(
                          '${post.commentCount}',
                          style: const TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),

                    // Delete button if active user is author, otherwise Report button
                    if (post.authorHandle == widget.currentUserHandle)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                        tooltip: 'Delete Post',
                        onPressed: () => _showDeleteConfirmation(context, post.id),
                      )
                    else
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.flag_outlined, size: 18, color: Colors.white30),
                        tooltip: 'Report Post',
                        onPressed: () => _showReportSheet(post.id),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Area picker is handled by LocationChip in the AppBar (tap the location badge).

  void _showDeleteConfirmation(BuildContext context, String postId) {
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
              await widget.repository.deletePostPermanently(postId);
              if (context.mounted) {
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

  void _showReportSheet(String postId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Report Content',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Reports are reviewed within 24h as per IT Act Rules 2021.',
                  style: TextStyle(color: Colors.black38, fontSize: 12),
                ),
                const SizedBox(height: 12),
                _buildReportOption(ctx, postId, 'Harassment / Impersonation'),
                _buildReportOption(ctx, postId, 'Doxxing / Personal Phone Numbers'),
                _buildReportOption(ctx, postId, 'Spam / Scams / Commercial'),
                _buildReportOption(ctx, postId, 'Hate Speech / Civic Threat'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportOption(BuildContext ctx, String postId, String reason) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.report_problem, color: Colors.amberAccent, size: 20),
      title: Text(reason, style: const TextStyle(color: Colors.black54, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white30),
      onTap: () {
        widget.repository.reportPost(postId, widget.currentUserHandle);
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Row(
              children: [
                const Icon(Icons.check, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Content reported for "$reason". It has been hidden from your feed.',
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

