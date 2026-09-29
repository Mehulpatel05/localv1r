import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/app_image_cache_service.dart';

/// 🚀 High-Performance Resilient Image Widget
///
/// Features:
/// 1. Instant 0ms RAM & Disk cache rendering (Zero network requests for already-seen images).
/// 2. Crystal clear high visual quality (Gapless playback, no pixelation or blur degradation).
/// 3. Resilient fallback & retry for flaky networks.
/// 4. Blur backdrop letterboxing (Single-pass shared memory decode, 0 duplicate downloads).
/// 5. Base64, Local File, and Network URL support.
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
  File? _diskFile;
  Uint8List? _memoryBytes;
  bool _isLoading = false;
  bool _hasError = false;
  int _retryCounter = 0;

  @override
  void initState() {
    super.initState();
    _resolveImageSource();
  }

  @override
  void didUpdateWidget(SafeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl.trim() != widget.imageUrl.trim()) {
      _resolveImageSource();
    }
  }

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

  void _resolveImageSource() {
    final trimmedUrl = widget.imageUrl.trim();
    if (trimmedUrl.isEmpty) return;

    // 1. Base64
    if (_isBase64) {
      _memoryBytes = _decodeBase64(trimmedUrl);
      _diskFile = null;
      _isLoading = false;
      _hasError = _memoryBytes == null;
      return;
    }

    // 2. Local File
    if (_isLocalFile) {
      final filePath = trimmedUrl.replaceFirst('file://', '');
      final f = File(filePath);
      if (f.existsSync()) {
        _diskFile = f;
        _memoryBytes = null;
        _isLoading = false;
        _hasError = false;
      } else {
        _diskFile = null;
        _hasError = true;
      }
      return;
    }

    // 3. Check Synchronous RAM Cache (0ms)
    final inRam = AppImageCacheService.instance.getFromMemory(trimmedUrl);
    if (inRam != null) {
      _memoryBytes = inRam;
      _diskFile = null;
      _isLoading = false;
      _hasError = false;
      return;
    }

    // 4. Check Synchronous Disk Cache (1-2ms)
    final onDisk = AppImageCacheService.instance.getFromDiskSync(trimmedUrl);
    if (onDisk != null) {
      _diskFile = onDisk;
      _memoryBytes = null;
      _isLoading = false;
      _hasError = false;
      return;
    }

    // 5. Asynchronous Fetch & Store
    _isLoading = true;
    _hasError = false;
    AppImageCacheService.instance.getOrFetchImageFile(trimmedUrl).then((file) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (file != null && file.existsSync()) {
            _diskFile = file;
            _hasError = false;
          } else {
            _hasError = true;
          }
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    });
  }

  void _retryLoading() {
    setState(() {
      _retryCounter++;
      _isLoading = true;
      _hasError = false;
    });
    final trimmedUrl = widget.imageUrl.trim();
    AppImageCacheService.instance.getOrFetchImageFile(trimmedUrl).then((file) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (file != null && file.existsSync()) {
            _diskFile = file;
            _hasError = false;
          } else {
            _hasError = true;
          }
        });
      }
    });
  }

  Widget _buildCoreImage({
    required BoxFit fit,
    required FilterQuality filterQuality,
    double? overrideHeight,
    double? overrideWidth,
  }) {
    final targetHeight = overrideHeight ?? widget.height;
    final targetWidth = overrideWidth ?? widget.width;

    if (_memoryBytes != null && _memoryBytes!.isNotEmpty) {
      return Image.memory(
        _memoryBytes!,
        height: targetHeight,
        width: targetWidth,
        fit: fit,
        alignment: widget.alignment,
        gaplessPlayback: true,
        filterQuality: filterQuality,
        errorBuilder: (context, error, stackTrace) => _buildErrorFallback(),
      );
    }

    if (_diskFile != null && _diskFile!.existsSync()) {
      return Image.file(
        _diskFile!,
        key: ValueKey('${_diskFile!.path}-$_retryCounter'),
        height: targetHeight,
        width: targetWidth,
        fit: fit,
        alignment: widget.alignment,
        gaplessPlayback: true,
        filterQuality: filterQuality,
        errorBuilder: (context, error, stackTrace) => _buildErrorFallback(),
      );
    }

    if (_isLoading) {
      return _buildPlaceholderContainer();
    }

    if (_hasError) {
      return _buildErrorFallback();
    }

    // Direct network fallback if asynchronous disk read has not populated yet
    final trimmedUrl = widget.imageUrl.trim();
    return Image.network(
      trimmedUrl,
      key: ValueKey('$trimmedUrl-$_retryCounter'),
      height: targetHeight,
      width: targetWidth,
      fit: fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
      filterQuality: filterQuality,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildPlaceholderContainer();
      },
      errorBuilder: (context, error, stackTrace) => _buildErrorFallback(),
    );
  }

  Widget _buildPlaceholderContainer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = widget.backgroundColor ?? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9));
    return Container(
      height: widget.height ?? 200,
      width: widget.width,
      color: baseColor,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          size: 28,
        ),
      ),
    );
  }

  Widget _buildErrorFallback() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = widget.backgroundColor ?? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9));

    return Container(
      height: widget.height ?? 200,
      width: widget.width,
      color: baseColor,
      child: Center(
        child: InkWell(
          onTap: _retryLoading,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Text(
                  'Tap to retry',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
            // 2. Subtle dark contrast overlay
            Container(
              color: Colors.black.withValues(alpha: 0.35),
            ),
            // 3. Crisp, 100% complete uncropped foreground image
            _buildCoreImage(
              fit: widget.fit,
              filterQuality: FilterQuality.high,
              overrideHeight: widget.height,
              overrideWidth: widget.width,
            ),
          ],
        ),
      );
    } else {
      content = _buildCoreImage(
        fit: widget.fit,
        filterQuality: FilterQuality.high,
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
}
