import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class SlidingCategoryTabBar extends StatefulWidget {
  final List<String> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool isScrollable;

  const SlidingCategoryTabBar({
    super.key,
    required this.categories,
    required this.selectedIndex,
    required this.onSelected,
    this.isScrollable = false,
  });

  @override
  State<SlidingCategoryTabBar> createState() => _SlidingCategoryTabBarState();
}

class _SlidingCategoryTabBarState extends State<SlidingCategoryTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ScrollController? _scrollController;

  int? _pressedIndex;
  double _startLeft = 0.0;
  double _startRight = 0.0;
  double _targetLeft = 0.0;
  double _targetRight = 0.0;
  double _lastTabWidth = 0.0;
  int _prevIndex = 0;

  static const Curve _leadCurve = Curves.easeOutCubic;
  static const Curve _trailCurve = Curves.easeInOutCubic;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    if (widget.isScrollable) {
      _scrollController = ScrollController();
    }

    final maxIndex = widget.categories.isEmpty ? 0 : widget.categories.length - 1;
    final int initialIndex = widget.selectedIndex.clamp(0, maxIndex);
    _prevIndex = initialIndex;
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant SlidingCategoryTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex != _prevIndex) {
      _animateToTab(widget.selectedIndex, _lastTabWidth);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController?.dispose();
    super.dispose();
  }

  void _animateToTab(int newIndex, double tabWidth, {List<double>? customOffsets, List<double>? customWidths}) {
    if (newIndex < 0 || newIndex >= widget.categories.length) return;

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    _startLeft = _getCurrentLeft();
    _startRight = _getCurrentRight();

    if (customOffsets != null && customWidths != null && newIndex < customOffsets.length) {
      _targetLeft = customOffsets[newIndex];
      _targetRight = customOffsets[newIndex] + customWidths[newIndex];
    } else {
      _targetLeft = newIndex * tabWidth;
      _targetRight = (newIndex + 1) * tabWidth;
    }
    _prevIndex = newIndex;

    if (widget.isScrollable && _scrollController != null && _scrollController!.hasClients) {
      final tabCenter = (_targetLeft + _targetRight) / 2 + 3.0;
      final viewportWidth = _scrollController!.position.viewportDimension;
      final maxScroll = _scrollController!.position.maxScrollExtent;
      final targetScroll = (tabCenter - viewportWidth / 2).clamp(0.0, maxScroll);
      _scrollController!.animateTo(
        targetScroll,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

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

    final movingRight = _targetLeft >= _startLeft;
    final curve = movingRight ? _trailCurve : _leadCurve;
    final u = curve.transform(t);
    return _startLeft + (_targetLeft - _startLeft) * u;
  }

  double _getCurrentRight() {
    final t = _controller.value;
    if (t >= 1.0) return _targetRight;
    if (t <= 0.0) return _startRight;

    final movingRight = _targetRight >= _startRight;
    final curve = movingRight ? _leadCurve : _trailCurve;
    final u = curve.transform(t);
    return _startRight + (_targetRight - _startRight) * u;
  }

  List<double> _calculateTabWidths() {
    final widths = <double>[];
    for (final cat in widget.categories) {
      final painter = TextPainter(
        text: TextSpan(
          text: cat,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      widths.add(math.max(54.0, painter.width + 30.0));
    }
    return widths;
  }

  List<double> _calculateOffsets(List<double> widths) {
    final offsets = <double>[];
    double current = 0.0;
    for (final w in widths) {
      offsets.add(current);
      current += w;
    }
    return offsets;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty) return const SizedBox.shrink();

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    if (widget.isScrollable) {
      final tabWidths = _calculateTabWidths();
      final tabOffsets = _calculateOffsets(tabWidths);
      final innerWidth = tabWidths.fold<double>(0.0, (sum, w) => sum + w);

      if (_targetRight == 0.0 && widget.selectedIndex < tabOffsets.length) {
        _startLeft = tabOffsets[widget.selectedIndex];
        _startRight = tabOffsets[widget.selectedIndex] + tabWidths[widget.selectedIndex];
        _targetLeft = _startLeft;
        _targetRight = _startRight;
      }

      final tabRow = Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(widget.categories.length, (index) {
          final isSelected = index == widget.selectedIndex;
          final category = widget.categories[index];
          final currentWidth = tabWidths[index];

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressedIndex = index),
            onTapUp: (_) => setState(() => _pressedIndex = null),
            onTapCancel: () => setState(() => _pressedIndex = null),
            onTap: () {
              if (widget.selectedIndex != index) {
                _animateToTab(index, 0.0, customOffsets: tabOffsets, customWidths: tabWidths);
                widget.onSelected(index);
              }
            },
            child: AnimatedScale(
              scale: _pressedIndex == index ? 0.95 : 1.0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
              child: Container(
                width: currentWidth,
                height: 36,
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                    child: Text(
                      category,
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      );

      final barContent = Container(
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
            final left = rawLeft.clamp(0.0, innerWidth);
            final right = rawRight.clamp(0.0, innerWidth);
            final width = math.max(1.0, right - left);

            final t = _controller.value;
            final isAnimating = _controller.isAnimating && t > 0.0 && t < 1.0;
            final squish = isAnimating ? math.sin(t * math.pi) * 0.08 : 0.0;
            final scaleY = (1.0 - squish).clamp(0.88, 1.0);

            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: left,
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: Transform.scale(
                    scaleY: scaleY,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ?child,
              ],
            );
          },
        ),
      );

      return SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: barContent,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final innerWidth = math.max(0.0, totalWidth - 6.0);
        final tabCount = widget.categories.length;
        final tabWidth = tabCount > 0 ? innerWidth / tabCount : 0.0;

        if (_targetRight == 0.0 && tabWidth > 0.0) {
          _startLeft = widget.selectedIndex * tabWidth;
          _startRight = (widget.selectedIndex + 1) * tabWidth;
          _targetLeft = _startLeft;
          _targetRight = _startRight;
        } else if (_lastTabWidth > 0.0 && _lastTabWidth != tabWidth) {
          final scaleRatio = tabWidth / _lastTabWidth;
          _startLeft *= scaleRatio;
          _startRight *= scaleRatio;
          _targetLeft = widget.selectedIndex * tabWidth;
          _targetRight = (widget.selectedIndex + 1) * tabWidth;
        }
        _lastTabWidth = tabWidth;

        final tabRow = Row(
          children: List.generate(widget.categories.length, (index) {
            final isSelected = index == widget.selectedIndex;
            final category = widget.categories[index];

            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => setState(() => _pressedIndex = index),
                onTapUp: (_) => setState(() => _pressedIndex = null),
                onTapCancel: () => setState(() => _pressedIndex = null),
                onTap: () {
                  if (widget.selectedIndex != index) {
                    _animateToTab(index, tabWidth);
                    widget.onSelected(index);
                  }
                },
                child: AnimatedScale(
                  scale: _pressedIndex == index ? 0.95 : 1.0,
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AnimatedDefaultTextStyle(
                        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                        child: Text(
                          category,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );

        return Container(
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
              final left = rawLeft.clamp(0.0, innerWidth);
              final right = rawRight.clamp(0.0, innerWidth);
              final width = math.max(1.0, right - left);

              final t = _controller.value;
              final isAnimating = _controller.isAnimating && t > 0.0 && t < 1.0;
              final squish = isAnimating ? math.sin(t * math.pi) * 0.08 : 0.0;
              final scaleY = (1.0 - squish).clamp(0.88, 1.0);

              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: left,
                    top: 0,
                    bottom: 0,
                    width: width,
                    child: Transform.scale(
                      scaleY: scaleY,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ?child,
                ],
              );
            },
          ),
        );
      },
    );
  }
}
