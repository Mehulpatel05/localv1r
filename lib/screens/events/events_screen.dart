import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/location/location_service.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/widgets/safe_image.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../detail/post_detail_screen.dart';
import 'events_post_screen.dart';

/// Dedicated Events & Meetups screen.
class EventsScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const EventsScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  late final PostRepository _localRepo;

  @override
  void initState() {
    super.initState();
    _localRepo = PostRepository(context.read<LocationService>());
    _localRepo.setCategory(PostCategory.events);
    _localRepo.addListener(_onRepoChanged);
  }





  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  

  @override
  Widget build(BuildContext context) {
    final posts = _localRepo.allPosts;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.black54, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Text('🎉', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text(
              'Events & Meetups',
              style: TextStyle(color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: Text(
                  '${posts.length} events',
                  style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _localRepo.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
          : posts.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(
                      top: 16, bottom: 100, left: 14, right: 14),
                  itemCount: posts.length,
                  itemBuilder: (context, i) => _buildEventCard(posts[i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF8B5CF6),
        elevation: 6,
        icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.black87),
        label: const Text(
          'Host an Event',
          style: TextStyle(color: Colors.black87,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EventsPostScreen(
              repository: widget.repository,
              authorHandle: widget.currentUserHandle,
            ),
          ),
        ),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎪', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text(
              'No upcoming events',
              style: TextStyle(
                  color: Colors.black54,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Be the first to host an event or party in your area!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black38, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Event card (Party / Tech Vibe) ──────────────────────────────────────────
  Widget _buildEventCard(Post post) {
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    final title = post.eventTitle ?? 'Secret Meetup';
    final date = post.eventDate ?? 'TBA';
    final location = post.eventLocationText ?? 'Location revealed soon';
    final price = post.eventPrice ?? 'Free';

    // Parse date for badge (Assuming format like "OCT 28, 6:00 PM" or something similar)
    // For demo purposes, we will split by space to try getting month and day.
    String badgeTop = 'DATE';
    String badgeBottom = 'TBA';
    if (date.contains(' ')) {
      final parts = date.split(' ');
      if (parts.length >= 2) {
        badgeTop = parts[0].replaceAll(',', '').toUpperCase(); // e.g. OCT
        badgeBottom = parts[1].replaceAll(',', ''); // e.g. 28
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Banner Image with Date Badge ──────────────────────────────────
                Stack(
                  children: [
                    if (hasImage)
                      SafeImage(
                        imageUrl: post.imageUrl!,
                        height: 200,
                        borderRadius: BorderRadius.zero,
                      )
                    else
                      Container(
                        height: 180,
                        color: const Color(0xFFE2E8F0),
                        child: const Center(
                          child: Text('🎊', style: TextStyle(fontSize: 64)),
                        ),
                      ),
                    
                    // Date Badge Overlay
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              badgeTop,
                              style: const TextStyle(
                                color: Color(0xFFEF4444), // Red month
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              badgeBottom,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Price tag overlay
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          price,
                          style: const TextStyle(color: Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Details Section ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Date & Time row
                      Row(
                        children: [
                          const Icon(Icons.access_time_filled_rounded, size: 16, color: Color(0xFF8B5CF6)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              date,
                              style: const TextStyle(
                                  color: Color(0xFFC4B5FD),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Area and Location row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF8B5CF6)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  location,
                                  style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  post.areaName ?? 'Nearhood',
                                  style: const TextStyle(
                                      color: Colors.black38,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      Divider(color: Colors.grey.shade200, height: 1),
                      const SizedBox(height: 16),

                      // Event Description
                      Text(
                        post.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Footer (Author & Actions)
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: const Color(0xFF8B5CF6),
                            child: Text(
                              post.authorHandle[0].toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '@${post.authorHandle}',
                            style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 13,
                                fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            _timeAgo(post.createdAt),
                            style: const TextStyle(
                                color: Colors.black38, fontSize: 11),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Actions (Upvotes/Downvotes, Comments count)
                      Row(
                        children: [
                          // Upvote/Downvote container
                          Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                    size: 22,
                                    color: post.userVote == 1 ? const Color(0xFF10B981) : Colors.black54,
                                  ),
                                  onPressed: () => widget.repository.votePost(post.id, 1),
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
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 22,
                                    color: post.userVote == -1 ? const Color(0xFFEF4444) : Colors.black54,
                                  ),
                                  onPressed: () => widget.repository.votePost(post.id, -1),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Comments Icon
                          Row(
                            children: [
                              const Icon(Icons.mode_comment_outlined, size: 18, color: Colors.black54),
                              const SizedBox(width: 6),
                              Text(
                                '${post.commentCount}',
                                style: const TextStyle(color: Colors.black54, fontSize: 13),
                              ),
                            ],
                          ),
                        ],
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

