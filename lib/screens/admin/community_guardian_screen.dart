import 'package:flutter/material.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../../theme/app_colors.dart';

class CommunityGuardianScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const CommunityGuardianScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<CommunityGuardianScreen> createState() => _CommunityGuardianScreenState();
}

class _CommunityGuardianScreenState extends State<CommunityGuardianScreen> {
  List<Post> _reportedPosts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReportedPosts();
  }

  Future<void> _loadReportedPosts() async {
    setState(() => _isLoading = true);
    final posts = await widget.repository.fetchReportedPosts();
    if (mounted) {
      setState(() {
        _reportedPosts = posts;
        _isLoading = false;
      });
    }
  }

  Future<void> _restorePost(Post post) async {
    final success = await widget.repository.adminRestorePost(post.id);
    if (!mounted) return;
    if (success) {
      setState(() {
        _reportedPosts.removeWhere((p) => p.id == post.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Post by @${post.authorHandle} restored back to the feed.'),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to restore post. Please check connection.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deletePost(Post post) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete this post?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: const Text('This will permanently delete this post from the community feed and storage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Post'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final success = await widget.repository.adminDeletePost(post.id);
    if (!mounted) return;
    if (success) {
      setState(() {
        _reportedPosts.removeWhere((p) => p.id == post.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post deleted permanently.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _banAuthor(Post post) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Ban @${post.authorHandle}?', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: Text('This user will be permanently restricted from posting on Nearhood, and all their posts will be hidden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ban User'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final success = await widget.repository.adminBanAuthor(post.authorHandle);
    if (!mounted) return;
    if (success) {
      setState(() {
        _reportedPosts.removeWhere((p) => p.authorHandle.toLowerCase() == post.authorHandle.toLowerCase());
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('@${post.authorHandle} has been banned from Nearhood.'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_rounded, color: AppColors.primary, size: 20),
                SizedBox(width: 6),
                Text(
                  'Mohalla Guardian Desk',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            Text(
              'Community safety & reported posts review',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: _loadReportedPosts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _loadReportedPosts,
              color: AppColors.primary,
              child: _reportedPosts.isEmpty ? _buildEmptyState() : _buildPostsList(),
            ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFF0FDF4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'All Clear! No Flagged Posts',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Your mohalla feed is clean and safe. When residents report inappropriate or adult content, it will appear here for your review.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPostsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: _reportedPosts.length,
      itemBuilder: (context, index) {
        final post = _reportedPosts[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFE11D48)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Reported ${post.reportCount > 0 ? post.reportCount : 1} times by residents',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFBE123C),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE11D48),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'FLAGGED',
                        style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    UserAvatar(
                      handle: post.authorHandle,
                      size: 38,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (post.authorName != null && post.authorName!.isNotEmpty)
                                ? post.authorName!
                                : post.authorHandle,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            '@${post.authorHandle.replaceAll("@", "")} · ${post.areaName ?? "Vadodara"}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (post.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Text(
                    post.content,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B), height: 1.4),
                  ),
                ),
              if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      post.imageUrl!,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF16A34A),
                          side: const BorderSide(color: Color(0xFFBBF7D0)),
                          backgroundColor: const Color(0xFFF0FDF4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                        label: const Text('Restore', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        onPressed: () => _restorePost(post),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: Color(0xFFFECDD3)),
                          backgroundColor: const Color(0xFFFFF1F2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        onPressed: () => _deletePost(post),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Ban Author',
                      icon: const Icon(Icons.block_rounded, color: Color(0xFFDC2626), size: 20),
                      onPressed: () => _banAuthor(post),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
