import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/location/location_service.dart';
import '../../core/location/location_chip.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/widgets/safe_image.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../detail/post_detail_screen.dart';
import 'services_post_screen.dart';

/// Dedicated Local Services screen.
class ServicesScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const ServicesScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  late final PostRepository _localRepo;

  @override
  void initState() {
    super.initState();
    _localRepo = PostRepository(context.read<LocationService>());
    _localRepo.setCategory(PostCategory.services);
    _localRepo.addListener(_onRepoChanged);
  }

  @override
  void dispose() {
    _localRepo.removeListener(_onRepoChanged);
    _localRepo.dispose();
    super.dispose();
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final posts = _localRepo.allPosts;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Text('🔧', style: TextStyle(fontSize: 20)),
            SizedBox(width: 6),
            Text(
              'Services',
              style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
          ],
        ),
        actions: const [
          Center(child: LocationChip()),
          SizedBox(width: 12),
        ],
      ),
      body: _localRepo.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
          : posts.isEmpty
              ? _buildEmpty()
              : GridView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.65, // Adjust for image + content
                  ),
                  itemCount: posts.length,
                  itemBuilder: (context, i) => _buildServiceCard(posts[i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFF1F5F9),
        elevation: 4,
        icon: const Icon(Icons.handyman_rounded, color: Colors.black87),
        label: const Text(
          'Offer a Service',
          style: TextStyle(color: Colors.black87,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ServicesPostScreen(
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
            const Text('🛠️', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text(
              'No services offered yet',
              style: TextStyle(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Are you a professional? Be the first to offer your services here!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Service card (Grid View) ──────────────────────────────────────────
  Widget _buildServiceCard(Post post) {
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    final title = post.serviceTitle ?? 'Untitled Service';
    final price = post.servicePrice ?? 'Contact for pricing';
    final category = post.serviceCategoryText ?? 'Service';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
              // ── Image Section ──────────────────────────────────
              Expanded(
                flex: 4,
                child: Stack(
                  children: [
                    if (hasImage)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: SafeImage(
                          imageUrl: post.imageUrl!,
                          height: double.infinity,
                          width: double.infinity,
                          borderRadius: BorderRadius.zero,
                        ),
                      )
                    else
                      Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: const Center(
                          child: Icon(Icons.home_repair_service, color: Colors.black87, size: 40),
                        ),
                      ),
                    
                    // Category Badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(color: Colors.black87,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Details Section ─────────────────────────────────────
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Price
                      Text(
                        price,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      
                      // Title
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // Location
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 12, color: Colors.black38),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              post.areaName ?? 'Nearhood',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      
                      // Author
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 8,
                            backgroundColor: const Color(0xFFF1F5F9),
                            child: Text(
                              post.authorHandle[0].toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '@${post.authorHandle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.blue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
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
      ),
    );
  }
}

