import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/motion.dart';
import 'package:share_plus/share_plus.dart';

class MultiImageGalleryViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String? caption;
  final String heroTagPrefix;

  const MultiImageGalleryViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.caption,
    required this.heroTagPrefix,
  });

  @override
  State<MultiImageGalleryViewer> createState() => _MultiImageGalleryViewerState();
}

class _MultiImageGalleryViewerState extends State<MultiImageGalleryViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _showUi = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleUi() {
    setState(() => _showUi = !_showUi);
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable Image PageView
          GestureDetector(
            onTap: _toggleUi,
            child: PageView.builder(
              controller: _pageController,
              itemCount: total,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                HapticFeedback.selectionClick();
              },
              itemBuilder: (context, index) {
                final url = widget.imageUrls[index];
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: Hero(
                      tag: '${widget.heroTagPrefix}_$index',
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white70,
                              strokeWidth: 2,
                            ),
                          );
                        },
                        errorBuilder: (_, _, _) => const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_rounded,
                                color: Colors.white38, size: 48),
                            SizedBox(height: 8),
                            Text(
                              'Could not load image',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Top Header Bar
          AnimatedPositioned(
            duration: AppMotion.durationStandard,
            curve: AppMotion.interactiveCurve,
            top: _showUi ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 4,
                bottom: 8,
                left: 8,
                right: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_currentIndex + 1} of $total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, color: Colors.white),
                    onPressed: _shareCurrentImage,
                  ),
                ],
              ),
            ),
          ),

          // Bottom Caption Bar
          if (widget.caption != null && widget.caption!.isNotEmpty)
            AnimatedPositioned(
              duration: AppMotion.durationStandard,
              curve: AppMotion.interactiveCurve,
              bottom: _showUi ? 0 : -120,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  widget.caption!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
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
