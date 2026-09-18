import 'package:flutter/material.dart';
import '../../../core/widgets/safe_image.dart';
import '../../../models/post_model.dart';

/// Reusable 2-Column Product Card Widget matching Nearhood Buy & Sell design (Image 3)
class ShopCardWidget extends StatefulWidget {
  final Post post;
  final VoidCallback onTap;

  const ShopCardWidget({
    super.key,
    required this.post,
    required this.onTap,
  });

  @override
  State<ShopCardWidget> createState() => _ShopCardWidgetState();
}

class _ShopCardWidgetState extends State<ShopCardWidget> {
  bool _isFavorite = false;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    final title = post.shopTitle ?? post.content;
    final rawPrice = post.shopPrice ?? '';
    
    // Format price with INR ₹ symbol
    String formattedPrice = 'Price on request';
    if (rawPrice.isNotEmpty) {
      if (rawPrice.startsWith('₹')) {
        formattedPrice = rawPrice;
      } else {
        // Format thousands if numeric
        final numVal = int.tryParse(rawPrice.replaceAll(',', '').replaceAll(' ', ''));
        if (numVal != null) {
          formattedPrice = '₹${_formatCurrency(numVal)}';
        } else {
          formattedPrice = '₹$rawPrice';
        }
      }
    }

    final photoCount = post.mediaUrls.isNotEmpty
        ? post.mediaUrls.length
        : (hasImage ? 1 : 0);

    final locationText = post.areaName ?? post.areaId ?? 'Vadodara';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image Section (Top half) ──────────────────────────
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                    child: Container(
                      height: 140,
                      width: double.infinity,
                      color: const Color(0xFFF1F5F9),
                      child: hasImage
                          ? SafeImage(
                              imageUrl: post.imageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 140,
                            )
                          : _buildFallbackIllustration(title, post.shopCategory),
                    ),
                  ),

                  // Photo Count Badge (Top-Right)
                  if (photoCount > 1)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 11,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '1/$photoCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Optional Heart favorite button (Top-Left)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isFavorite = !_isFavorite;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: _isFavorite ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Details Section (Bottom half) ──────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Price in Emerald Green
                    Text(
                      formattedPrice,
                      style: const TextStyle(
                        color: Color(0xFF00B074), // Emerald green
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),

                    // Product Title
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Location Line
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 12.5,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 2.5),
                        Expanded(
                          child: Text(
                            locationText,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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

  Widget _buildFallbackIllustration(String title, String? category) {
    IconData iconData = Icons.shopping_bag_outlined;
    Color iconColor = const Color(0xFF00B074);
    Color bgColor = const Color(0xFFE6F7F0);

    final lower = '${title.toLowerCase()} ${category?.toLowerCase() ?? ''}';
    if (lower.contains('laptop') || lower.contains('phone') || lower.contains('electronics') || lower.contains('tv')) {
      iconData = Icons.devices_other_rounded;
      iconColor = const Color(0xFF3B82F6);
      bgColor = const Color(0xFFEFF6FF);
    } else if (lower.contains('sofa') || lower.contains('table') || lower.contains('furniture') || lower.contains('bed')) {
      iconData = Icons.chair_rounded;
      iconColor = const Color(0xFFD97706);
      bgColor = const Color(0xFFFEF3C7);
    } else if (lower.contains('car') || lower.contains('bike') || lower.contains('vehicle')) {
      iconData = Icons.directions_car_rounded;
      iconColor = const Color(0xFF6366F1);
      bgColor = const Color(0xFFEEF2FF);
    } else if (lower.contains('book')) {
      iconData = Icons.menu_book_rounded;
      iconColor = const Color(0xFF059669);
      bgColor = const Color(0xFFECFDF5);
    } else if (lower.contains('jacket') || lower.contains('clothes') || lower.contains('fashion') || lower.contains('shoes')) {
      iconData = Icons.checkroom_rounded;
      iconColor = const Color(0xFFEC4899);
      bgColor = const Color(0xFFFDF2F8);
    }

    return Container(
      color: bgColor,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: iconColor.withValues(alpha: 0.15),
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(
            iconData,
            size: 28,
            color: iconColor,
          ),
        ),
      ),
    );
  }

  String _formatCurrency(int amount) {
    final str = amount.toString();
    if (str.length <= 3) return str;
    
    // Indian Numbering format (e.g. 45,000 or 1,50,000)
    final lastThree = str.substring(str.length - 3);
    final otherNumbers = str.substring(0, str.length - 3);
    final formattedOther = otherNumbers.replaceAllMapped(
      RegExp(r'(\d+?)(?=(\d\d)+$)'),
      (match) => '${match[1]},',
    );
    return '$formattedOther,$lastThree';
  }
}
