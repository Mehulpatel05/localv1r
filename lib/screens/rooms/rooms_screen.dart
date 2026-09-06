import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/location/location_service.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/widgets/safe_image.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import 'room_post_screen.dart';

/// Dedicated Rooms listing screen.
/// Opens with slide-up animation from [FeedScreen] when Rooms chip is tapped.
class RoomsScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const RoomsScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  late final PostRepository _localRepo;

  @override
  void initState() {
    super.initState();
    _localRepo = PostRepository(context.read<LocationService>());
    _localRepo.setCategory(PostCategory.rooms);
    _localRepo.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _localRepo.removeListener(_onUpdate);
    _localRepo.dispose();
    super.dispose();
  }

  void _onUpdate() {
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
            Text('🏠', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text(
              'Rooms in Vadodara',
              style: TextStyle(color: Colors.black87,
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: Text(
                  '${posts.length} listings',
                  style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _localRepo.isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF3B82F6)))
          : posts.isEmpty
              ? _buildEmpty()
              : GridView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(
                      top: 12, bottom: 100, left: 14, right: 14),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 12,
                    childAspectRatio: 338 / 435,
                  ),
                  itemCount: posts.length,
                  itemBuilder: (context, i) => _buildRoomCard(posts[i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFF1F5F9),
        elevation: 4,
        icon: const Icon(Icons.add_home_work_rounded,
            color: Colors.black87),
        label: const Text(
          'List Your Room',
          style: TextStyle(color: Colors.black87,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoomPostScreen(
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
            const Text('🏠',
                style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text(
              'No rooms listed yet',
              style: TextStyle(
                  color: Colors.black54,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Be the first to list a room for rent in Vadodara.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.black38, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Room card ──────────────────────────────────────────────────────────
  Widget _buildRoomCard(Post post) {
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    final rent = post.roomRent ?? '0';
    final title = (post.roomTitle != null && post.roomTitle!.isNotEmpty)
        ? post.roomTitle!
        : post.content;

    // Formatting date as "24 FEB" roughly
    final months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    final timeStr = "${post.createdAt.day} ${months[post.createdAt.month - 1]}";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image ────────────────────────────────────────────────
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: hasImage
                      ? SafeImage(
                          imageUrl: post.imageUrl!,
                          height: double.infinity,
                          borderRadius: BorderRadius.zero,
                        )
                      : Container(
                          color: const Color(0xFF1E3A5F),
                          child: const Center(
                            child: Text('🏠', style: TextStyle(fontSize: 32)),
                          ),
                        ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.favorite_border,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),

            // ── Info section ─────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Rent
                    Text(
                      '₹ $rent / mo',
                      style: const TextStyle(color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),

                    // Title
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14),
                    ),
                    
                    const Spacer(),

                    // Details (Location & Time)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Icon(Icons.location_on, size: 12, color: Colors.black38),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            'Vadodara'.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.black38,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          timeStr,
                          style: const TextStyle(
                              color: Colors.black38,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
