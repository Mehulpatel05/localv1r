import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'safe_image.dart';
import 'post_full_screen_viewer.dart';
import 'universal_media_view.dart';
import '../../services/r2_storage_service.dart';

/// Reusable Post Image & Video View Widget
///
/// Ensures both portrait/tall images (e.g. 720x1570 screenshots), videos, and landscape images
/// appear 100% uncropped inside a consistent-sized card container.
///
/// Features:
/// 1. Container dimensions stay bounded and predictable across all devices.
/// 2. Foreground image uses `BoxFit.contain` so zero content or text is cropped.
/// 3. Ambient blurred letterbox backdrop fills empty left/right (or top/bottom) space
///    with the colors of the image, darkened with a subtle 0.32 contrast layer.
/// 4. Shared image decode stream cache (no duplicate network requests).
/// 5. On tap, opens full-screen Hero viewer with pinch-to-zoom, double-tap zoom,
///    and swipe-down to dismiss.
class PostImageView extends StatelessWidget {
  final String imageUrl;
  final List<String>? allImages;
  final int initialIndex;
  final double? height;
  final double width;
  final BorderRadius? borderRadius;
  final String? heroTagPrefix;
  final String? caption;
  final bool enableFullScreen;
  final Widget? overlay;

  const PostImageView({
    super.key,
    required this.imageUrl,
    this.allImages,
    this.initialIndex = 0,
    this.height = 260,
    this.width = double.infinity,
    this.borderRadius,
    this.heroTagPrefix,
    this.caption,
    this.enableFullScreen = true,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    final images = (allImages != null && allImages!.isNotEmpty)
        ? allImages!
        : [imageUrl];
    final tagPrefix = heroTagPrefix ?? 'post_img_${imageUrl.hashCode}';
    final radius = borderRadius ?? BorderRadius.circular(14);
    final count = images.length;

    if (R2StorageService.isVideoFile(imageUrl)) {
      return UniversalMediaView(
        url: imageUrl,
        height: height,
        width: width,
        borderRadius: radius,
        showControls: true,
        autoPlay: false,
        isMuted: true,
      );
    }

    Widget imageCard = ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        width: width,
        color: const Color(0xFF0F172A),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            // ── Layer 1: Ambient Blurred Backdrop ────────────────────────────
            ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Transform.scale(
                  scale: 1.20,
                  child: SafeImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    alignment: Alignment.center,
                    backgroundColor: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ),

            // ── Layer 2: Subtle Dark Contrast Tint ───────────────────────────
            Container(
              color: Colors.black.withValues(alpha: 0.32),
            ),

            // ── Layer 3: Crisp, Complete Uncropped Image ─────────────────────
            Hero(
              tag: '${tagPrefix}_$initialIndex',
              child: SafeImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                alignment: Alignment.center,
                backgroundColor: Colors.transparent,
              ),
            ),

            // ── Layer 4: Optional Custom Overlay ────────────────────────────
            ?overlay,

            // ── Layer 5: Multi-Image Counter Pill ────────────────────────────
            if (count > 1)
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.collections_rounded,
                          color: Colors.white, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        '1/$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
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
    );

    if (!enableFullScreen) {
      return imageCard;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.transparent,
            pageBuilder: (_, _, _) => PostFullScreenViewer(
              imageUrls: images,
              initialIndex: initialIndex,
              heroTagPrefix: tagPrefix,
              caption: caption,
            ),
            transitionsBuilder: (_, animation, _, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: imageCard,
    );
  }
}
