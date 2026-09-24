import 'package:flutter/material.dart';
import '../../../core/widgets/safe_image.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../models/post_model.dart';
import '../../../services/telegram_storage_service.dart';

class ServiceCardWidget extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;

  const ServiceCardWidget({
    super.key,
    required this.post,
    required this.onTap,
  });

  Map<String, dynamic> _getCategoryStyle(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('electr')) {
      return {'icon': Icons.bolt_rounded, 'color': const Color(0xFFD97706), 'bg': const Color(0xFFFEF3C7), 'iconData': '⚡'};
    } else if (cat.contains('plumb')) {
      return {'icon': Icons.build_rounded, 'color': const Color(0xFF2563EB), 'bg': const Color(0xFFEFF6FF), 'iconData': '🔧'};
    } else if (cat.contains('clean')) {
      return {'icon': Icons.cleaning_services_rounded, 'color': const Color(0xFF059669), 'bg': const Color(0xFFECFDF5), 'iconData': '🧹'};
    } else if (cat.contains('tutor')) {
      return {'icon': Icons.menu_book_rounded, 'color': const Color(0xFF7C3AED), 'bg': const Color(0xFFF5F3FF), 'iconData': '📚'};
    } else if (cat.contains('driver')) {
      return {'icon': Icons.directions_car_rounded, 'color': const Color(0xFF475569), 'bg': const Color(0xFFF1F5F9), 'iconData': '🚗'};
    } else if (cat.contains('cook')) {
      return {'icon': Icons.restaurant_rounded, 'color': const Color(0xFFEA580C), 'bg': const Color(0xFFFFF7ED), 'iconData': '🍳'};
    } else if (cat.contains('it') || cat.contains('computer')) {
      return {'icon': Icons.laptop_chromebook_rounded, 'color': const Color(0xFF0284C7), 'bg': const Color(0xFFE0F2FE), 'iconData': '💻'};
    } else if (cat.contains('home')) {
      return {'icon': Icons.home_rounded, 'color': const Color(0xFF4F46E5), 'bg': const Color(0xFFEEF2FF), 'iconData': '🏠'};
    }
    return {'icon': Icons.handyman_rounded, 'color': const Color(0xFF64748B), 'bg': const Color(0xFFF8FAFC), 'iconData': '🛠️'};
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    final title = post.serviceTitle?.isNotEmpty == true ? post.serviceTitle! : post.content;
    final price = post.servicePrice?.isNotEmpty == true ? post.servicePrice! : 'Starting at ₹299';
    final category = post.serviceCategoryText ?? 'Service';
    final location = post.areaName ?? 'Vadodara';
    final authorHandle = post.authorHandle.replaceAll('@', '');
    final style = _getCategoryStyle(category);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Image / Category Vector Banner (Image 1 & 4)
              Expanded(
                flex: 10,
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
                              color: style['bg'] as Color,
                              child: Center(
                                child: Icon(
                                  style['icon'] as IconData,
                                  color: (style['color'] as Color).withValues(alpha: 0.35),
                                  size: 48,
                                ),
                              ),
                            ),
                    ),

                    // Top Left Soft-Tint Category Badge (Image 4 Group 2)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(style['icon'] as IconData, size: 11.5, color: style['color'] as Color),
                            const SizedBox(width: 3.5),
                            Text(
                              category,
                              style: TextStyle(
                                color: style['color'] as Color,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                    // Top Right Video Indicator Badge
                    if (hasImage && TelegramStorageService.isVideoFile(post.imageUrl!))
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.videocam_rounded, color: Colors.white, size: 12),
                              SizedBox(width: 3),
                              Text(
                                'Video',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 2. Card Content Details (Image 1 & 4)
              Expanded(
                flex: 10,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Price & Title
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            price,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? const Color(0xFFEDEDED) : const Color(0xFF1E293B),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),

                      // Location & Author Row
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 11.5, color: Color(0xFF94A3B8)),
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
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              UserAvatar(
                                handle: authorHandle,
                                size: 16,
                                fontSize: 8,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '@$authorHandle',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
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
