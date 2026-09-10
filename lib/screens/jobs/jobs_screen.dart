import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/location/location_service.dart';
import '../../core/location/location_chip.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/widgets/safe_image.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../detail/post_detail_screen.dart';
import 'jobs_post_screen.dart';

/// Dedicated Jobs & Referrals screen.
class JobsScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const JobsScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  late final PostRepository _localRepo;

  @override
  void initState() {
    super.initState();
    _localRepo = PostRepository(context.read<LocationService>());
    _localRepo.setCategory(PostCategory.jobs);
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
      backgroundColor: const Color(0xFFF3F2EF), // LinkedIn style background
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Text('💼', style: TextStyle(fontSize: 20)),
            SizedBox(width: 6),
            Text(
              'Jobs',
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
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0A66C2)))
          : posts.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(
                      top: 12, bottom: 100),
                  itemCount: posts.length,
                  itemBuilder: (context, i) => _buildJobCard(posts[i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0A66C2), // LinkedIn blue
        elevation: 4,
        icon: const Icon(Icons.add_box_rounded, color: Colors.black87),
        label: const Text(
          'Post a Job',
          style: TextStyle(color: Colors.black87,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobsPostScreen(
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
            const Text('🏢', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text(
              'No jobs posted yet',
              style: TextStyle(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Be the first to post a job opening or request a referral!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Job card (LinkedIn/Professional Style) ─────────────────────────────
  Widget _buildJobCard(Post post) {
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    final title = post.jobTitle ?? 'Untitled Position';
    final company = post.jobCompany ?? 'Confidential Company';
    final location = post.jobLocation ?? 'Location not specified';
    final jobType = post.jobType ?? 'Full-time';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (Author info) ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFFE0E7FF),
                      child: Text(
                        post.authorHandle[0].toUpperCase(),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4F46E5)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '@${post.authorHandle}',
                            style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _timeAgo(post.createdAt),
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.more_horiz, color: Colors.black54),
                  ],
                ),
              ),
              
              // ── Job Details Section ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      company,
                      style: const TextStyle(
                        color: Color(0xFF0A66C2), // LinkedIn blue for company
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_city_rounded, size: 14, color: Colors.black54),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$location • ${post.areaName ?? 'Nearhood'}',
                            style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    
                    // Badges (Job Type)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F2EF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        jobType,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              
              // ── Description ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  post.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Optional Banner Image ──────────────────────────────────
              if (hasImage)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: SafeImage(
                    imageUrl: post.imageUrl!,
                    height: 180,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              
              // ── Actions (Upvotes/Downvotes, Comments count) ────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    // Upvote/Downvote container
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.thumb_up_alt_rounded,
                            size: 20,
                            color: post.userVote == 1 ? const Color(0xFF0A66C2) : Colors.black45,
                          ),
                          onPressed: () => widget.repository.votePost(post.id, 1),
                        ),
                        Text(
                          '${post.score}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: post.userVote == 1
                                ? const Color(0xFF0A66C2)
                                : (post.userVote == -1 ? const Color(0xFFEF4444) : Colors.black54),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.thumb_down_alt_rounded,
                            size: 20,
                            color: post.userVote == -1 ? const Color(0xFFEF4444) : Colors.black45,
                          ),
                          onPressed: () => widget.repository.votePost(post.id, -1),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),

                    // Comments Icon
                    Row(
                      children: [
                        const Icon(Icons.comment_rounded, size: 18, color: Colors.black45),
                        const SizedBox(width: 6),
                        Text(
                          '${post.commentCount} Comments',
                          style: const TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.w600),
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
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

