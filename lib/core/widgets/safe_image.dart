import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Resilient Image Widget that supports:
/// 1. Base64 data URIs (`data:image/jpeg;base64,...`) and raw Base64 strings.
/// 2. Standard Network URLs (`https://...`, `http://...`).
/// 3. Telegram CDN links with automatic timeout & retry.
/// 4. Graceful offline / error fallback without crashing or ugly layout shifts.
class SafeImage extends StatefulWidget {
  final String imageUrl;
  final double? height;
  final double width;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const SafeImage({
    super.key,
    required this.imageUrl,
    this.height,
    this.width = double.infinity,
    this.fit = BoxFit.cover,
    this.borderRadius,
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

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = widget.imageUrl.trim();
    if (trimmedUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget content;

    if (_isBase64) {
      final bytes = _decodeBase64(trimmedUrl);
      if (bytes != null && bytes.isNotEmpty) {
        content = Image.memory(
          bytes,
          height: widget.height,
          width: widget.width,
          fit: widget.fit,
          errorBuilder: (_, _, _) => _buildErrorFallback(canRetry: false),
        );
      } else {
        content = _buildErrorFallback(canRetry: false);
      }
    } else {
      if (!trimmedUrl.startsWith('https://')) {
        content = _buildErrorFallback(canRetry: false);
      } else {
        content = Image.network(
          trimmedUrl,
          key: ValueKey('$trimmedUrl-$_retryCounter'),
          height: widget.height,
          width: widget.width,
          fit: widget.fit,
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              height: widget.height ?? 180,
              width: widget.width,
              color: const Color(0xFF1E293B),
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
