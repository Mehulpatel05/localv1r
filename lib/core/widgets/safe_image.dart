import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Resilient Image Widget that supports:
/// 1. Base64 data URIs (`data:image/jpeg;base64,...`) and raw Base64 strings.
/// 2. Standard Network URLs (`https://...`, `http://...`).
/// 3. Local File paths (`/data/user/...`, `file://...`).
/// 4. Blur backdrop ambient letterboxing (`enableBlurBackdrop: true`):
///    Keeps 100% of the image uncropped and undistorted inside the exact allocated space.
/// 5. Graceful offline / error fallback without crashing or layout shifts.
class SafeImage extends StatefulWidget {
  final String imageUrl;
  final double? height;
  final double width;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool enableBlurBackdrop;
  final Color? backgroundColor;
  final Alignment alignment;

  const SafeImage({
    super.key,
    required this.imageUrl,
    this.height,
    this.width = double.infinity,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.enableBlurBackdrop = false,
    this.backgroundColor,
    this.alignment = Alignment.center,
  });

  @override
  State<SafeImage> createState() => _SafeImageState();
}

class _SafeImageState extends State<SafeImage> {
  int _retryCounter = 0;

  bool get _isBase64 {
    final url = widget.imageUrl.trim();
    return url.startsWith('data:image/');
  }

  bool get _isLocalFile {
    final url = widget.imageUrl.trim();
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('data:image/')) {
      return false;
    }
    return true;
  }

  Uint8List? _decodeBase64(String src) {
    try {
      String clean = src.trim();
      if (clean.contains(',')) {
        clean = clean.split(',').last;
      }
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }

  Widget _buildCoreImage({required BoxFit fit, required FilterQuality filterQuality, double? overrideHeight, double? overrideWidth}) {
    final trimmedUrl = widget.imageUrl.trim();

    if (_isBase64) {
      final bytes = _decodeBase64(trimmedUrl);
      if (bytes != null && bytes.isNotEmpty) {
        return Image.memory(
          bytes,
          cacheWidth: 800,
          cacheHeight: (widget.height != null && widget.height!.isFinite)
              ? (widget.height! * 2.5).round().clamp(100, 1000)
              : null,
          height: overrideHeight ?? widget.height,
          width: overrideWidth ?? widget.width,
          fit: fit,
          alignment: widget.alignment,
          gaplessPlayback: true,
          filterQuality: filterQuality,
          errorBuilder: (context, error, stackTrace) => _buildErrorFallback(canRetry: false),
        );
      }
      return _buildErrorFallback(canRetry: false);
    }

    if (_isLocalFile) {
      try {
        final filePath = trimmedUrl.replaceFirst('file://', '');
        final dynamicWidth = widget.width.isFinite
            ? (widget.width * 2.5).round().clamp(100, 1440)
            : null;
        final file = File(filePath);
        if (file.existsSync()) {
          return Image.file(
            file,
            cacheWidth: dynamicWidth,
            cacheHeight: (widget.height != null && widget.height!.isFinite)
                ? (widget.height! * 2.5).round().clamp(100, 1440)
                : null,
            height: overrideHeight ?? widget.height,
            width: overrideWidth ?? widget.width,
            fit: fit,
            alignment: widget.alignment,
            gaplessPlayback: true,
            filterQuality: filterQuality,
            errorBuilder: (context, error, stackTrace) => _buildErrorFallback(canRetry: false),
          );
        }
      } catch (_) {}
    }

    final dynamicWidth = widget.width.isFinite
        ? (widget.width * 2.5).round().clamp(100, 1440)
        : null;

    return Image.network(
      trimmedUrl,
      key: ValueKey('$trimmedUrl-$_retryCounter'),
      cacheWidth: dynamicWidth,
      cacheHeight: (widget.height != null && widget.height!.isFinite)
          ? (widget.height! * 2.5).round().clamp(100, 1440)
          : null,
      height: overrideHeight ?? widget.height,
      width: overrideWidth ?? widget.width,
      fit: fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
      filterQuality: filterQuality,
      headers: const {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          height: widget.height ?? 180,
          width: widget.width,
          color: widget.backgroundColor ?? const Color(0xFFF1F5F9),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: const Color(0xFF3B82F6),
                strokeWidth: 2,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorFallback(canRetry: true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = widget.imageUrl.trim();
    if (trimmedUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget content;

    if (widget.enableBlurBackdrop) {
      content = Container(
        height: widget.height,
        width: widget.width,
        color: widget.backgroundColor ?? const Color(0xFF0F172A),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            // 1. Ambient blurred background matching the image colors
            ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Transform.scale(
                  scale: 1.15,
                  child: _buildCoreImage(
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    overrideHeight: widget.height,
                    overrideWidth: widget.width,
                  ),
                ),
              ),
            ),
            // 2. Dark contrast overlay
            Container(
              color: Colors.black.withValues(alpha: 0.38),
            ),
            // 3. Crisp, 100% complete uncropped foreground image
            _buildCoreImage(
              fit: widget.fit == BoxFit.cover ? BoxFit.contain : widget.fit,
              filterQuality: FilterQuality.medium,
              overrideHeight: widget.height,
              overrideWidth: widget.width,
            ),
          ],
        ),
      );
    } else {
      content = Container(
        height: widget.height,
        width: widget.width,
        color: widget.backgroundColor,
        child: _buildCoreImage(
          fit: widget.fit,
          filterQuality: FilterQuality.medium,
        ),
      );
    }

    if (widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }
    return content;
  }

  Widget _buildErrorFallback({required bool canRetry}) {
    return Container(
      height: widget.height ?? 140,
      width: widget.width,
      decoration: BoxDecoration(
        color: const Color(0xFF151D30),
        borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF243049)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, color: Colors.white24, size: 28),
            const SizedBox(height: 6),
            const Text(
              'Image temporarily unavailable',
              style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (canRetry) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () {
                  setState(() {
                    _retryCounter++;
                  });
                },
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 14, color: Color(0xFF60A5FA)),
                      SizedBox(width: 4),
                      Text('Tap to retry', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
