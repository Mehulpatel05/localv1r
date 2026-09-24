import 'package:flutter/material.dart';
import 'multi_image_gallery_viewer.dart';
import '../../../services/r2_storage_service.dart';

class ImageGroupBubble extends StatelessWidget {
  final List<String> mediaUrls;
  final String? caption;
  final String timeStr;
  final bool isMe;
  final String messageId;
  final BorderRadius bubbleRadius;
  final bool isRead;
  final String status;

  const ImageGroupBubble({
    super.key,
    required this.mediaUrls,
    this.caption,
    required this.timeStr,
    required this.isMe,
    required this.messageId,
    required this.bubbleRadius,
    this.isRead = false,
    this.status = 'sent',
  });

  void _openGallery(BuildContext context, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiImageGalleryViewer(
          imageUrls: mediaUrls,
          initialIndex: initialIndex,
          caption: caption,
          heroTagPrefix: messageId,
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    int index, {
    double? width,
    double? height,
    BorderRadius? borderRadius,
    bool isLastWithOverlay = false,
    int extraCount = 0,
  }) {
    final url = mediaUrls[index];

    return Expanded(
      child: GestureDetector(
        onTap: () => _openGallery(context, index),
        child: ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.circular(6),
          child: Container(
            height: height,
            width: width,
            color: isMe ? Colors.white10 : Colors.black12,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: '${messageId}_$index',
                  child: Image.network(
                    url,
                    cacheWidth: 400,
                    cacheHeight: 400,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: isMe ? Colors.white12 : Colors.black12,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                    errorBuilder: (_, _, _) => Container(
                      color: isMe ? Colors.white12 : Colors.black12,
                      child: const Center(
                        child: Icon(Icons.broken_image_rounded,
                            color: Colors.black38),
                      ),
                    ),
                  ),
                ),
                if (R2StorageService.isVideoFile(url))
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26,
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                if (isLastWithOverlay && extraCount > 0)
                  Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    alignment: Alignment.center,
                    child: Text(
                      '+$extraCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollageLayout(BuildContext context) {
    final count = mediaUrls.length;

    if (count == 1) {
      // 1 Image (Medium compact size)
      return GestureDetector(
        onTap: () => _openGallery(context, 0),
        child: ClipRRect(
          borderRadius: caption != null && caption!.isNotEmpty
              ? BorderRadius.only(
                  topLeft: bubbleRadius.topLeft,
                  topRight: bubbleRadius.topRight,
                  bottomLeft: const Radius.circular(4),
                  bottomRight: const Radius.circular(4),
                )
              : bubbleRadius,
          child: Container(
            constraints: const BoxConstraints(
              maxHeight: 200,
              minHeight: 120,
              minWidth: 140,
            ),
            child: Hero(
              tag: '${messageId}_0',
              child: Image.network(
                mediaUrls[0],
                cacheWidth: 500,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 160,
                    color: isMe ? Colors.white12 : Colors.black12,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (_, _, _) => Container(
                  height: 120,
                  color: isMe ? Colors.white12 : Colors.black12,
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded, color: Colors.black38),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else if (count == 2) {
      // 2 Images: Side by Side (Medium compact size)
      return SizedBox(
        height: 130,
        child: Row(
          children: [
            _buildTile(context, 0, height: 130),
            const SizedBox(width: 4),
            _buildTile(context, 1, height: 130),
          ],
        ),
      );
    } else if (count == 3) {
      // 3 Images: 1 Big Left + 2 Stacked Right (Medium compact size)
      return SizedBox(
        height: 160,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: () => _openGallery(context, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 160,
                    child: Hero(
                      tag: '${messageId}_0',
                      child: Image.network(
                        mediaUrls[0],
                        cacheWidth: 500,
                        cacheHeight: 400,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  _buildTile(context, 1, height: 78),
                  const SizedBox(height: 4),
                  _buildTile(context, 2, height: 78),
                ],
              ),
            ),
          ],
        ),
      );
    } else if (count == 4) {
      // 4 Images: 2x2 Grid (Medium compact size)
      return Column(
        children: [
          SizedBox(
            height: 85,
            child: Row(
              children: [
                _buildTile(context, 0, height: 85),
                const SizedBox(width: 4),
                _buildTile(context, 1, height: 85),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 85,
            child: Row(
              children: [
                _buildTile(context, 2, height: 85),
                const SizedBox(width: 4),
                _buildTile(context, 3, height: 85),
              ],
            ),
          ),
        ],
      );
    } else {
      // 5+ Images: 2x2 Grid with +N on 4th tile (Medium compact size)
      final extraCount = count - 3; // Total remaining images
      return Column(
        children: [
          SizedBox(
            height: 85,
            child: Row(
              children: [
                _buildTile(context, 0, height: 85),
                const SizedBox(width: 4),
                _buildTile(context, 1, height: 85),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 85,
            child: Row(
              children: [
                _buildTile(context, 2, height: 85),
                const SizedBox(width: 4),
                _buildTile(
                  context,
                  3,
                  height: 85,
                  isLastWithOverlay: true,
                  extraCount: extraCount,
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildStatusIcon({Color? readColor, Color? defaultColor}) {
    if (!isMe) return const SizedBox.shrink();
    if (isRead || status == 'read') {
      return Icon(
        Icons.done_all_rounded,
        size: 14,
        color: readColor ?? const Color(0xFF60A5FA),
      );
    } else if (status == 'delivered') {
      return Icon(
        Icons.done_all_rounded,
        size: 14,
        color: defaultColor ?? Colors.white70,
      );
    } else {
      return Icon(
        Icons.done_rounded,
        size: 14,
        color: defaultColor ?? Colors.white70,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCaption = caption != null && caption!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(3),
              child: ClipRRect(
                borderRadius: bubbleRadius,
                child: _buildCollageLayout(context),
              ),
            ),
            if (!hasCaption && timeStr.isNotEmpty)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 3),
                        _buildStatusIcon(
                          readColor: const Color(0xFF60A5FA),
                          defaultColor: Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (hasCaption)
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 6, 13, 6),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  caption!,
                  style: TextStyle(
                    color: isMe ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 14.5,
                    height: 1.35,
                  ),
                ),
                if (timeStr.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.75)
                              : const Color(0xFF94A3B8),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 3),
                        _buildStatusIcon(
                          readColor: const Color(0xFF93C5FD),
                          defaultColor: Colors.white.withValues(alpha: 0.75),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
