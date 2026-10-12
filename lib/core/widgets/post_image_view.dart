import 'package:flutter/material.dart';
import 'safe_image.dart';
import 'post_full_screen_viewer.dart';
import 'universal_media_view.dart';
import '../../services/r2_storage_service.dart';
import '../../theme/app_colors.dart';

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

    final placeholderColor = AppColors.chipBg;

    Widget imageCard = ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        width: width,
        color: placeholderColor,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Hero(
              tag: '${tagPrefix}_$initialIndex',
              child: SafeImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                alignment: Alignment.center,
                backgroundColor: placeholderColor,
              ),
            ),
            ?overlay,
            if (count > 1)
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827).withValues(alpha: 0.72),
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
