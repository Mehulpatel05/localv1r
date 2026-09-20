import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/motion.dart';
import 'safe_image.dart';

/// Full-screen image viewer supporting:
/// - Hero transition animation
/// - Pinch-to-zoom & double-tap to zoom
/// - Swipe-down to dismiss with interactive background opacity fade
/// - Multi-image swipeable gallery
/// - Share action and clean close button
class PostFullScreenViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String heroTagPrefix;
  final String? caption;

  const PostFullScreenViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    required this.heroTagPrefix,
    this.caption,
  });

  @override
  State<PostFullScreenViewer> createState() => _PostFullScreenViewerState();
}

class _PostFullScreenViewerState extends State<PostFullScreenViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late int _currentIndex;
  final Map<int, TransformationController> _transformControllers = {};

  // Swipe down to dismiss state
  double _dragOffsetY = 0.0;
  bool _isDraggingDown = false;
  late final AnimationController _resetAnimController;
  Animation<double>? _resetAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _resetAnimController = AnimationController(
      vsync: this,
      duration: AppMotion.durationStandard,
    )..addListener(() {
        if (_resetAnimation != null) {
          setState(() {
            _dragOffsetY = _resetAnimation!.value;
          });
        }
      });
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    _resetAnimController.dispose();
    super.dispose();
  }

  TransformationController _getController(int index) {
    return _transformControllers.putIfAbsent(
      index,
      () => TransformationController(),
    );
  }

  void _onDoubleTap(int index) {
    final controller = _getController(index);
    final isZoomed = controller.value.getMaxScaleOnAxis() > 1.05;
    if (isZoomed) {
      controller.value = Matrix4.identity();
    } else {
      controller.value = Matrix4.identity()..scaleByDouble(2.5, 2.5, 1.0, 1.0);
    }
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final controller = _getController(_currentIndex);
    final scale = controller.value.getMaxScaleOnAxis();
    // Only allow drag-to-dismiss when not zoomed in
    if (scale <= 1.05) {
      if (details.delta.dy > 0 || _dragOffsetY > 0) {
        setState(() {
          _isDraggingDown = true;
          _dragOffsetY = (_dragOffsetY + details.delta.dy).clamp(0.0, 400.0);
        });
      }
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDraggingDown) return;
    _isDraggingDown = false;

    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffsetY > 110 || velocity > 450) {
      Navigator.pop(context);
    } else {
      // Animate back to resting position
      _resetAnimation = Tween<double>(
        begin: _dragOffsetY,
        end: 0.0,
      ).animate(
        CurvedAnimation(
          parent: _resetAnimController,
          curve: AppMotion.enterCurve,
        ),
      );
      _resetAnimController.forward(from: 0.0);
    }
  }

  void _shareCurrentImage() {
    final url = widget.imageUrls[_currentIndex];
    Share.share(
      widget.caption != null && widget.caption!.isNotEmpty
          ? '${widget.caption}\n$url'
          : url,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageUrls.length;
    final dismissRatio = (_dragOffsetY / 280.0).clamp(0.0, 1.0);
    final backgroundOpacity = (1.0 - (dismissRatio * 0.75)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: backgroundOpacity),
      body: Stack(
        children: [
          // Swipeable Image Content
          GestureDetector(
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            child: Transform.translate(
              offset: Offset(0, _dragOffsetY),
              child: PageView.builder(
                controller: _pageController,
                physics: _dragOffsetY > 0
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                itemCount: total,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                  HapticFeedback.selectionClick();
                },
                itemBuilder: (context, index) {
                  final url = widget.imageUrls[index];
                  final controller = _getController(index);

                  return GestureDetector(
                    onDoubleTap: () => _onDoubleTap(index),
                    child: Center(
                      child: Hero(
                        tag: '${widget.heroTagPrefix}_$index',
                        child: InteractiveViewer(
                          transformationController: controller,
                          minScale: 1.0,
                          maxScale: 5.0,
                          panEnabled: true,
                          scaleEnabled: true,
                          child: SafeImage(
                            imageUrl: url,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Top Header Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 6,
                left: 12,
                right: 12,
                bottom: 10,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  // Close button
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 26),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  // Image Counter (if multiple)
                  if (total > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / $total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  const Spacer(),
                  // Share button
                  IconButton(
                    icon: const Icon(Icons.share_rounded,
                        color: Colors.white, size: 22),
                    onPressed: _shareCurrentImage,
                  ),
                ],
              ),
            ),
          ),

          // Optional caption at bottom
          if (widget.caption != null && widget.caption!.trim().isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 14,
                  bottom: MediaQuery.of(context).padding.bottom + 14,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  widget.caption!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
