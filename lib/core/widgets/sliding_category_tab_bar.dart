import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class SlidingCategoryTabBar extends StatefulWidget {
  final List<String> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const SlidingCategoryTabBar({
    super.key,
    required this.categories,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  State<SlidingCategoryTabBar> createState() => _SlidingCategoryTabBarState();
}

class _SlidingCategoryTabBarState extends State<SlidingCategoryTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final ScrollController _scrollController;
  late List<double> _tabWidths;
  late List<double> _tabLefts;

  int? _pressedIndex;
  double _startLeft = 0.0;
  double _startRight = 0.0;
  double _targetLeft = 0.0;
  double _targetRight = 0.0;
  int _prevIndex = 0;

  static const Curve _springCurve = Cubic(0.34, 1.56, 0.64, 1.0);

  @override
  void initState() {
    super.initState();
    _calculateTabPositions();
    _scrollController = ScrollController();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    final maxIndex = widget.categories.isEmpty ? 0 : widget.categories.length - 1;
    final int initialIndex = widget.selectedIndex.clamp(0, maxIndex);
    _prevIndex = initialIndex;
    if (_tabLefts.isNotEmpty) {
      _startLeft = _tabLefts[initialIndex];
      _startRight = _tabLefts[initialIndex] + _tabWidths[initialIndex];
      _targetLeft = _startLeft;
      _targetRight = _startRight;
    }
    _controller.value = 1.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToSelectedTab(initialIndex, animate: false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant SlidingCategoryTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.categories != oldWidget.categories) {
      _calculateTabPositions();
    }
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex != _prevIndex) {
      _animateToTab(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _calculateTabPositions() {
    const textStyle = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    );
    _tabWidths = [];
    _tabLefts = [];
    double currentX = 0.0;

    for (final category in widget.categories) {
      final painter = TextPainter(
        text: TextSpan(text: category, style: textStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final width = (painter.width + 32.0).ceilToDouble();
      _tabWidths.add(width);
      _tabLefts.add(currentX);
      currentX += width;
    }
  }

  void _animateToTab(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.categories.length) return;

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    _startLeft = _getCurrentLeft();
    _startRight = _getCurrentRight();

    _targetLeft = _tabLefts[newIndex];
    _targetRight = _tabLefts[newIndex] + _tabWidths[newIndex];
    _prevIndex = newIndex;

    _scrollToSelectedTab(newIndex, animate: !reduceMotion);

    if (reduceMotion) {
      _startLeft = _targetLeft;
      _startRight = _targetRight;
      _controller.value = 1.0;
      setState(() {});
      return;
    }

    _controller.forward(from: 0.0);
  }

  double _getCurrentLeft() {
    final t = _controller.value;
    if (t >= 1.0) return _targetLeft;
    if (t <= 0.0) return _startLeft;

    final u = _springCurve.transform(t);
    final dist = _targetLeft - _startLeft;
    final dir = dist > 0 ? 1.0 : (dist < 0 ? -1.0 : 0.0);
    final stretchAmount = (dist.abs() * 0.20).clamp(6.0, 22.0);
    final stretch = math.sin(t * math.pi) * stretchAmount;

    if (dir < 0) {
      return (ui.lerpDouble(_startLeft, _targetLeft, u) ?? _targetLeft) - stretch;
    }
    return ui.lerpDouble(_startLeft, _targetLeft, u) ?? _targetLeft;
  }

  double _getCurrentRight() {
    final t = _controller.value;
    if (t >= 1.0) return _targetRight;
    if (t <= 0.0) return _startRight;

    final u = _springCurve.transform(t);
    final dist = _targetLeft - _startLeft;
    final dir = dist > 0 ? 1.0 : (dist < 0 ? -1.0 : 0.0);
    final stretchAmount = (dist.abs() * 0.20).clamp(6.0, 22.0);
    final stretch = math.sin(t * math.pi) * stretchAmount;

    if (dir > 0) {
      return (ui.lerpDouble(_startRight, _targetRight, u) ?? _targetRight) + stretch;
    }
    return ui.lerpDouble(_startRight, _targetRight, u) ?? _targetRight;
  }

  void _scrollToSelectedTab(int index, {required bool animate}) {
    if (!_scrollController.hasClients || index < 0 || index >= _tabLefts.length) return;

    final tabLeft = _tabLefts[index];
    final tabWidth = _tabWidths[index];
    final viewportWidth = _scrollController.position.viewportDimension;
    final totalWidth = _tabLefts.last + _tabWidths.last + 6.0;

    if (totalWidth <= viewportWidth) return;

    final targetOffset = (16.0 + 3.0 + tabLeft + (tabWidth / 2.0)) - (viewportWidth / 2.0);
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if (!animate) {
      _scrollController.jumpTo(clampedOffset);
    } else {
      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty) return const SizedBox.shrink();

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final maxBoundsRight = _tabLefts.last + _tabWidths.last;

    final tabRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.categories.length, (index) {
        final isSelected = index == widget.selectedIndex;
        final category = widget.categories[index];
        final width = _tabWidths[index];

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressedIndex = index),
          onTapUp: (_) => setState(() => _pressedIndex = null),
          onTapCancel: () => setState(() => _pressedIndex = null),
          onTap: () {
            if (widget.selectedIndex != index) {
              _animateToTab(index);
              widget.onSelected(index);
            }
          },
          child: AnimatedScale(
            scale: _pressedIndex == index ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
            child: SizedBox(
              width: width,
              height: 36,
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                  child: Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );

    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 42,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.divider, width: 1.0),
        ),
        padding: const EdgeInsets.all(3),
        child: AnimatedBuilder(
          animation: _controller,
          child: tabRow,
          builder: (context, child) {
            final rawLeft = _getCurrentLeft();
            final rawRight = _getCurrentRight();
            final left = rawLeft.clamp(0.0, maxBoundsRight);
            final right = rawRight.clamp(0.0, maxBoundsRight);
            final width = math.max(1.0, right - left);

            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.28),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                ?child,
              ],
            );
          },
        ),
      ),
    );
  }
}
