import 'package:flutter/material.dart';
import '../../../core/widgets/safe_image.dart';
import '../../../models/post_model.dart';

class RoomCardWidget extends StatefulWidget {
  final Post post;
  final VoidCallback onTap;

  const RoomCardWidget({
    super.key,
    required this.post,
    required this.onTap,
  });

  @override
  State<RoomCardWidget> createState() => _RoomCardWidgetState();
}

class _RoomCardWidgetState extends State<RoomCardWidget> {
  bool _isFavorited = false;

  String _formatRent(String? rent) {
    if (rent == null || rent.isEmpty) return '₹8,000';
    final clean = rent.replaceAll('₹', '').replaceAll('/month', '').replaceAll('/mo', '').trim();
    return '₹$clean';
  }

  String _inferType(Post post) {
    final text = '${post.roomTitle ?? ""} ${post.content}'.toLowerCase();
    if (text.contains('1 bhk') || text.contains('1bhk')) return '1 BHK';
    if (text.contains('2 bhk') || text.contains('2bhk')) return '2 BHK';
    if (text.contains('pg') || text.contains('paying guest')) return 'PG';
    if (text.contains('flatmate') || text.contains('roommate')) return 'Flatmate';
    if (text.contains('studio')) return 'Studio';
    return '1 BHK';
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    final mediaCount = (post.mediaUrls?.isNotEmpty == true) ? post.mediaUrls!.length : (hasImage ? 1 : 0);
    final rentStr = _formatRent(post.roomRent);
    final title = post.roomTitle?.isNotEmpty == true ? post.roomTitle! : post.content;
    final location = post.areaName ?? (post.roomArea ?? 'Vadodara');
    final typeBadge = _inferType(post);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Image Stack (Matching Image 3)
              Expanded(
                flex: 11,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      child: hasImage
                          ? SafeImage(
                              imageUrl: post.imageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : Container(
                              color: const Color(0xFFF1F5F9),
                              child: const Center(
                                child: Icon(Icons.apartment_rounded, color: Color(0xFF94A3B8), size: 36),
                              ),
                            ),
                    ),

                    // Gradient Overlay for price readability
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.75),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Top Left Type Badge (e.g. 1 BHK, PG, Flatmate)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          typeBadge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    // Top Right Media Counter Badge (if multiple photos) & Heart Favorite Icon
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (mediaCount > 1) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '1/$mediaCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          GestureDetector(
                            onTap: () {
                              setState(() => _isFavorited = !_isFavorited);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                color: _isFavorited ? const Color(0xFFEF4444) : Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom Left Price on image
                    Positioned(
                      bottom: 6,
                      left: 8,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            rentStr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text(
                            '/month',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Card Details Section (Image 3)
              Expanded(
                flex: 9,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Available nearby',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
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
