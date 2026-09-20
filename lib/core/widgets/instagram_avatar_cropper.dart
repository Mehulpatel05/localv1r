import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Instagram-Grade Profile Picture "Move and Scale" Interactive Cropper
/// Allows users to pinch to zoom, drag, and position their photo inside
/// a circular frame with rule-of-thirds grid lines, exactly like Instagram.
class InstagramAvatarCropper extends StatefulWidget {
  final File imageFile;

  const InstagramAvatarCropper({
    super.key,
    required this.imageFile,
  });

  /// Helper method to open the cropper screen and return the cropped 1080x1080 image file.
  static Future<File?> cropImage(BuildContext context, {required File imageFile}) async {
    return Navigator.of(context).push<File?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => InstagramAvatarCropper(imageFile: imageFile),
      ),
    );
  }

  @override
  State<InstagramAvatarCropper> createState() => _InstagramAvatarCropperState();
}

class _InstagramAvatarCropperState extends State<InstagramAvatarCropper> {
  final GlobalKey _cropKey = GlobalKey();
  final TransformationController _transformationController = TransformationController();

  bool _isProcessing = false;
  bool _isInteracting = false;
  final bool _imageLoaded = true;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetTransform() {
    _transformationController.value = Matrix4.identity();
  }

  Future<void> _onDone() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // Ensure layout is settled
      await Future.delayed(const Duration(milliseconds: 30));

      final boundary = _cropKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) Navigator.of(context).pop(widget.imageFile);
        return;
      }

      // Render crisp, high-performance 512x512 square image (fast encode & upload)
      final double cropWidgetSize = boundary.size.width;
      final double pixelRatio = (512.0 / cropWidgetSize).clamp(1.0, 2.0);

      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        if (mounted) Navigator.of(context).pop(widget.imageFile);
        return;
      }

      final pngBytes = byteData.buffer.asUint8List();
      final tempPath = '${Directory.systemTemp.path}/instagram_avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      final croppedFile = File(tempPath);
      await croppedFile.writeAsBytes(pngBytes, flush: false);

      if (mounted) {
        Navigator.of(context).pop(croppedFile);
      }
    } catch (e) {
      debugPrint('[InstagramCropper] Error saving crop: $e');
      if (mounted) {
        Navigator.of(context).pop(widget.imageFile);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final double cropSize = (screenSize.width - 48).clamp(260.0, 360.0);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
          tooltip: 'Cancel',
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(null),
        ),
        centerTitle: true,
        title: const Text(
          'Move and Scale',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton(
              onPressed: (_isProcessing || !_imageLoaded) ? null : _onDone,
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF3897F0),
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Done',
                      style: TextStyle(
                        color: Color(0xFF3897F0),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),

            // Interactive Viewport with Circular Mask & Grid
            Center(
              child: SizedBox(
                width: cropSize,
                height: cropSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 1. The Capturable Image Area (Exact 1:1 square captured by RepaintBoundary)
                    RepaintBoundary(
                      key: _cropKey,
                      child: Container(
                        width: cropSize,
                        height: cropSize,
                        color: const Color(0xFF000000),
                        child: _imageLoaded
                            ? ClipRect(
                                child: InteractiveViewer(
                                  transformationController: _transformationController,
                                  minScale: 1.0,
                                  maxScale: 4.5,
                                  panEnabled: true,
                                  scaleEnabled: true,
                                  clipBehavior: Clip.none,
                                  onInteractionStart: (_) {
                                    if (!_isInteracting) {
                                      setState(() => _isInteracting = true);
                                    }
                                  },
                                  onInteractionEnd: (_) {
                                    if (_isInteracting) {
                                      setState(() => _isInteracting = false);
                                    }
                                  },
                                  child: Image.file(
                                    widget.imageFile,
                                    width: cropSize,
                                    height: cropSize,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.center,
                                  ),
                                ),
                              )
                            : const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF3897F0),
                                  strokeWidth: 2,
                                ),
                              ),
                      ),
                    ),

                    // 2. Instagram Dark Dimming Overlay with Circular Cutout
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _InstagramCropOverlayPainter(
                            cropSize: cropSize,
                            showGrid: _isInteracting,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Bottom Instructions & Controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.pinch_rounded,
                        color: Colors.white.withValues(alpha: 0.6),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Pinch to zoom • Drag to position',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: _resetTransform,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter that draws the Instagram-style outer dimmed mask,
/// circular white border guide, and 3x3 rule-of-thirds grid inside the circle.
class _InstagramCropOverlayPainter extends CustomPainter {
  final double cropSize;
  final bool showGrid;

  _InstagramCropOverlayPainter({
    required this.cropSize,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Draw dark mask outside the circle
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final maskPath = Path.combine(PathOperation.difference, backgroundPath, circlePath);

    final maskPaint = Paint()
      ..color = const Color(0x99000000)
      ..style = PaintingStyle.fill;
    canvas.drawPath(maskPath, maskPaint);

    // 2. Draw white circular border ring
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius - 0.75, borderPaint);

    // 3. Draw Rule-of-Thirds Grid inside circle when interacting
    if (showGrid) {
      canvas.save();
      canvas.clipPath(circlePath);

      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      final oneThird = size.width / 3;
      final twoThirds = (size.width / 3) * 2;

      // Vertical grid lines
      canvas.drawLine(Offset(oneThird, 0), Offset(oneThird, size.height), gridPaint);
      canvas.drawLine(Offset(twoThirds, 0), Offset(twoThirds, size.height), gridPaint);

      // Horizontal grid lines
      canvas.drawLine(Offset(0, oneThird), Offset(size.width, oneThird), gridPaint);
      canvas.drawLine(Offset(0, twoThirds), Offset(size.width, twoThirds), gridPaint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _InstagramCropOverlayPainter oldDelegate) {
    return oldDelegate.cropSize != cropSize || oldDelegate.showGrid != showGrid;
  }
}
