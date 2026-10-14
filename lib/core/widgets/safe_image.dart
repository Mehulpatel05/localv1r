import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/app_image_cache_service.dart';
import '../../theme/app_colors.dart';

class SafeImage extends StatefulWidget {
  final String imageUrl;
  final double? height;
  final double width;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool enableBlurBackdrop;
  final Color? backgroundColor;
  final Alignment alignment;
  final Widget? placeholder;
  final Widget? errorWidget;

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
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<SafeImage> createState() => _SafeImageState();
}

class _SafeImageState extends State<SafeImage> {
  File? _diskFile;
  Uint8List? _memoryBytes;
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

    if (_isBase64) {
      _memoryBytes = _decodeBase64(trimmedUrl);
      _diskFile = null;
      _hasError = _memoryBytes == null;
      return;
    }

    if (_isLocalFile) {
      final filePath = trimmedUrl.replaceFirst('file://', '');
      final f = File(filePath);
      if (f.existsSync()) {
        _diskFile = f;
        _memoryBytes = null;
        _hasError = false;
      } else {
        _diskFile = null;
        _hasError = true;
      }
      return;
    }

    final inRam = AppImageCacheService.instance.getFromMemory(trimmedUrl);
    if (inRam != null) {
      _memoryBytes = inRam;
      _diskFile = null;
      _hasError = false;
      return;
    }

    final onDisk = AppImageCacheService.instance.getFromDiskSync(trimmedUrl);
    if (onDisk != null) {
      _diskFile = onDisk;
      _memoryBytes = null;
      _hasError = false;
      return;
    }

    _hasError = false;
    AppImageCacheService.instance.getOrFetchImageFile(trimmedUrl).then((file) {
      if (mounted && file != null && file.existsSync()) {
        setState(() {
          _diskFile = file;
          _hasError = false;
        });
      }
    }).catchError((_) {});
  }

  void _retryLoading() {
    final trimmedUrl = widget.imageUrl.trim();
    AppImageCacheService.instance.evict(trimmedUrl);
    setState(() {
      _retryCounter++;
      _hasError = false;
    });
    AppImageCacheService.instance.getOrFetchImageFile(trimmedUrl).then((file) {
      if (mounted && file != null && file.existsSync()) {
        setState(() {
          _diskFile = file;
          _hasError = false;
        });
      }
    }).catchError((_) {});
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
        errorBuilder: (context, error, stackTrace) => widget.errorWidget ?? _buildErrorFallback(),
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
        errorBuilder: (context, error, stackTrace) => widget.errorWidget ?? _buildErrorFallback(),
      );
    }

    if (_hasError) {
      return widget.errorWidget ?? _buildErrorFallback();
    }

    final normalized = AppImageCacheService.normalizeImageUrl(widget.imageUrl);
    return Image.network(
      normalized,
      key: ValueKey('$normalized-$_retryCounter'),
      height: targetHeight,
      width: targetWidth,
      fit: fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
      filterQuality: filterQuality,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return widget.placeholder ?? _buildPlaceholderContainer();
      },
      errorBuilder: (context, error, stackTrace) => widget.errorWidget ?? _buildErrorFallback(),
    );
  }

  Widget _buildPlaceholderContainer() {
    final baseColor = widget.backgroundColor ?? AppColors.chipBg;
    return Container(
      height: widget.height ?? 200,
      width: widget.width,
      color: baseColor,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: AppColors.textMuted.withValues(alpha: 0.5),
          size: 28,
        ),
      ),
    );
  }

  Widget _buildErrorFallback() {
    final baseColor = widget.backgroundColor ?? AppColors.chipBg;

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
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  'Tap to retry',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
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
            Container(
              color: Colors.black.withValues(alpha: 0.35),
            ),
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
