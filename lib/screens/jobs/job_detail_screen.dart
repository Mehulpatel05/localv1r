import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/widgets/safe_image.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../chat/personal_chat_screen.dart';
import '../profile/other_user_profile_sheet.dart';

class JobDetailScreen extends StatefulWidget {
  final Post post;
  final PostRepository repository;
  final String currentUserHandle;

  const JobDetailScreen({
    super.key,
    required this.post,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  bool _isBookmarked = false;

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()} weeks ago';
    if (diff.inDays >= 1) return '${diff.inDays} days ago';
    if (diff.inHours >= 1) return '${diff.inHours} hours ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} minutes ago';
    return 'Just now';
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded, color: Color(0xFF2563EB)),
              title: const Text('Share Opportunity', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                final title = widget.post.jobTitle ?? 'Job Opportunity';
                final company = widget.post.jobCompany ?? 'Nearhood';
                // ignore: deprecated_member_use
                Share.share('Check out this job opening on Nearhood: $title at $company in Vadodara!');
              },
            ),
            ListTile(
              leading: Icon(
                _isBookmarked ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded,
                color: const Color(0xFF475569),
              ),
              title: Text(
                _isBookmarked ? 'Remove Bookmark' : 'Save Job',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _isBookmarked = !_isBookmarked);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_isBookmarked ? 'Job saved to bookmarks' : 'Job removed from bookmarks'),
                    backgroundColor: const Color(0xFF2563EB),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Color(0xFFEF4444)),
              title: const Text('Report Listing', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Listing reported. Thank you for keeping Nearhood safe.'),
                    backgroundColor: Color(0xFF10B981),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _applyOrContact() {
    final cleanPoster = widget.post.authorHandle.replaceAll('@', '');
    if (cleanPoster == widget.currentUserHandle.replaceAll('@', '')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This is your own job posting.'),
          backgroundColor: Color(0xFF475569),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalChatScreen(
          currentUserHandle: widget.currentUserHandle,
          partnerHandle: cleanPoster,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.post.jobTitle ?? 'Job Opportunity';
    final company = widget.post.jobCompany ?? 'Verified Employer';
    final location = widget.post.jobLocation ?? (widget.post.areaName ?? 'Vadodara');
    final jobType = widget.post.jobType ?? 'Full-time';
    final isConfidential = company.toLowerCase().contains('confidential');
    final cleanCompany = isConfidential ? 'Confidential Employer' : company;
    final initial = cleanCompany.isNotEmpty ? cleanCompany[0].toUpperCase() : '💼';
    final hasImage = widget.post.imageUrl != null && widget.post.imageUrl!.isNotEmpty;

    final similarPosts = widget.repository.allPosts
        .where((p) => p.id != widget.post.id && p.category == PostCategory.jobs)
        .take(3)
        .toList();

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Job details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF64748B), size: 24),
            onPressed: _showMoreMenu,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Banner Image if present
                  if (hasImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SafeImage(
                        imageUrl: widget.post.imageUrl!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 1. Header Row (Avatar + Title + Company + Location & Badge)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Color(0xFF2563EB),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              cleanCompany,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF94A3B8)),
                                    const SizedBox(width: 3),
                                    Text(
                                      location,
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    jobType,
                                    style: const TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 2. About this opportunity
                  const Text(
                    'About this opportunity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.post.content,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 14,
                      height: 1.55,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 3. Responsibilities
                  const Text(
                    'Responsibilities',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Design and build advanced, high-performance features.\n• Collaborate with engineering teams to define and clean APIs.\n• Own performance, quality, and responsiveness of the application.\n• Mentor junior developers and participate in code reviews.',
                    style: TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 13.5,
                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 4. Requirements
                  const Text(
                    'Requirements',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Professional software development experience.\n• Strong understanding of state management and clean architecture.\n• Experience deploying and maintaining production applications.',
                    style: TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 13.5,
                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 5. Nice to have
                  const Text(
                    'Nice to have',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Experience with automated CI/CD workflows.\n• Familiarity with local ecosystem or community-driven products.',
                    style: TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 13.5,
                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 6. Job Metadata Info Card (Image 2)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        _buildMetaRow(
                          icon: Icons.work_outline_rounded,
                          label: 'Job type',
                          value: jobType,
                        ),
                        const Divider(height: 20, color: Color(0xFFE2E8F0)),
                        _buildMetaRow(
                          icon: Icons.location_on_outlined,
                          label: 'Location',
                          value: '$location (Hybrid flexibility)',
                        ),
                        const Divider(height: 20, color: Color(0xFFE2E8F0)),
                        _buildMetaRow(
                          icon: Icons.business_outlined,
                          label: 'Company',
                          value: cleanCompany,
                        ),
                        const Divider(height: 20, color: Color(0xFFE2E8F0)),
                        _buildMetaRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Posted by',
                          value: '@${widget.post.authorHandle.replaceAll('@', '')}',
                          isLink: true,
                          onTap: () {
                            showOtherUserProfileSheet(
                              context,
                              partnerHandle: widget.post.authorHandle,
                              currentUserHandle: widget.currentUserHandle,
                              repository: widget.repository,
                            );
                          },
                        ),
                        const Divider(height: 20, color: Color(0xFFE2E8F0)),
                        _buildMetaRow(
                          icon: Icons.access_time_rounded,
                          label: 'Posted',
                          value: _formatTimeAgo(widget.post.createdAt),
                        ),
                      ],
                    ),
                  ),

                  // 7. Similar Opportunities Nearby (Image 2)
                  if (similarPosts.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Text(
                      'Similar opportunities nearby',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...similarPosts.map((simPost) {
                      final simCompany = simPost.jobCompany ?? 'Verified Employer';
                      final simTitle = simPost.jobTitle ?? 'Job Opportunity';
                      final simInitial = simCompany.isNotEmpty ? simCompany[0].toUpperCase() : '💼';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              simInitial,
                              style: const TextStyle(
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          title: Text(
                            simTitle,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            simCompany,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => JobDetailScreen(
                                  post: simPost,
                                  repository: widget.repository,
                                  currentUserHandle: widget.currentUserHandle,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),

          // 8. Bottom Sticky Action Bar (Image 2)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Bookmark Outlined Button
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        color: _isBookmarked ? const Color(0xFF2563EB) : const Color(0xFF475569),
                      ),
                      onPressed: () {
                        setState(() => _isBookmarked = !_isBookmarked);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isBookmarked ? 'Saved to bookmarks' : 'Removed from bookmarks'),
                            backgroundColor: const Color(0xFF2563EB),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Apply / Contact Button
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                        foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _applyOrContact,
                      child: const Text(
                        'Apply / Contact',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
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

  Widget _buildMetaRow({
    required IconData icon,
    required String label,
    required String value,
    bool isLink = false,
    VoidCallback? onTap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: const Color(0xFF2563EB)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              InkWell(
                onTap: isLink ? onTap : null,
                child: Text(
                  value,
                  style: TextStyle(
                    color: isLink ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
                    fontSize: 13.5,
                    fontWeight: isLink ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
