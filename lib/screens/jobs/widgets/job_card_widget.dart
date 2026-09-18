import 'package:flutter/material.dart';
import '../../../core/widgets/safe_image.dart';
import '../../../models/post_model.dart';

class JobCardWidget extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;

  const JobCardWidget({
    super.key,
    required this.post,
    required this.onTap,
  });

  // 52x52 5-palette avatar colors
  static const List<Map<String, Color>> _avatarPalettes = [
    {'bg': Color(0xFFEFF6FF), 'text': Color(0xFF2563EB)}, // Blue (G)
    {'bg': Color(0xFFECFDF5), 'text': Color(0xFF059669)}, // Green (S)
    {'bg': Color(0xFFF5F3FF), 'text': Color(0xFF7C3AED)}, // Purple (N)
    {'bg': Color(0xFFFFF7ED), 'text': Color(0xFFEA580C)}, // Orange (B)
    {'bg': Color(0xFFF0FDFA), 'text': Color(0xFF0D9488)}, // Teal (T)
  ];

  Map<String, Color> _getPalette(String key) {
    if (key.isEmpty) return _avatarPalettes[0];
    final hash = key.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return _avatarPalettes[hash % _avatarPalettes.length];
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final title = post.jobTitle ?? 'Job Opportunity';
    final company = post.jobCompany ?? 'Verified Employer';
    final location = post.jobLocation ?? (post.areaName ?? 'Vadodara');
    final jobType = post.jobType ?? 'Full-time';
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    final isConfidential = company.toLowerCase().contains('confidential');
    final isReferral = jobType.toLowerCase().contains('referral') || title.toLowerCase().contains('referral');
    final isHiring = jobType.toLowerCase().contains('hiring') || title.toLowerCase().contains('hiring');
    final isInternship = jobType.toLowerCase().contains('intern');
    final palette = _getPalette(company.isNotEmpty ? company : title);

    final cleanCompany = isConfidential ? 'Confidential Employer' : company;
    final initial = cleanCompany.isNotEmpty ? cleanCompany[0].toUpperCase() : '💼';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top Banner Image (Variant A)
                if (hasImage) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SafeImage(
                      imageUrl: post.imageUrl!,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // 2. Top Special Pill (Referral or Hiring)
                if (isReferral) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_rounded, size: 13, color: Color(0xFF7C3AED)),
                        SizedBox(width: 4),
                        Text(
                          'REFERRAL',
                          style: TextStyle(
                            color: Color(0xFF7C3AED),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (isHiring) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'HIRING',
                      style: TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],

                // 3. Header Row: 52x52 Avatar + Role + Company
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 52x52 Rounded Avatar
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isConfidential ? const Color(0xFFF1F5F9) : palette['bg'],
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: isConfidential
                          ? const Icon(Icons.business_rounded, color: Color(0xFF64748B), size: 26)
                          : Text(
                              initial,
                              style: TextStyle(
                                color: palette['text'],
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                    const SizedBox(width: 14),

                    // Role & Company Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            cleanCompany,
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: isConfidential ? FontStyle.italic : FontStyle.normal,
                              fontWeight: FontWeight.w500,
                              color: isConfidential ? const Color(0xFF64748B) : const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 4. Badges Row: Location + Job Type + Remote
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
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
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    _buildJobTypeBadge(jobType, isInternship, isReferral),
                    if (location.toLowerCase().contains('remote'))
                      _buildRemoteBadge(),
                  ],
                ),

                const SizedBox(height: 10),

                // 5. Description Preview Snippet
                Text(
                  post.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),

                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 10),

                // 6. Footer: Posted by + View Details ->
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Posted by @${post.authorHandle.replaceAll('@', '')} • ${_formatTimeAgo(post.createdAt)}',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      children: const [
                        Text(
                          'View details',
                          style: TextStyle(
                            color: Color(0xFF2563EB),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 13,
                          color: Color(0xFF2563EB),
                        ),
                      ],
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

  Widget _buildJobTypeBadge(String type, bool isInternship, bool isReferral) {
    Color bg = const Color(0xFFEFF6FF);
    Color text = const Color(0xFF2563EB);
    String label = type;

    if (isInternship) {
      bg = const Color(0xFFF5F3FF);
      text = const Color(0xFF7C3AED);
      label = '🎓 Internship';
    } else if (isReferral) {
      bg = const Color(0xFFF3E8FF);
      text = const Color(0xFF9333EA);
      label = 'Referral';
    } else if (type.toLowerCase().contains('part')) {
      bg = const Color(0xFFF8FAFC);
      text = const Color(0xFF475569);
    } else if (type.toLowerCase().contains('freelance')) {
      bg = const Color(0xFFECFDF5);
      text = const Color(0xFF059669);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildRemoteBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.language_rounded, size: 12, color: Color(0xFF16A34A)),
          SizedBox(width: 3),
          Text(
            'Remote',
            style: TextStyle(
              color: Color(0xFF16A34A),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
