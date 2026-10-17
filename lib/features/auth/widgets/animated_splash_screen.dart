import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_colors.dart';

class AnimatedSplashScreen extends StatefulWidget {
  final VoidCallback? onAnimationComplete;
  final bool? isDarkMode;

  const AnimatedSplashScreen({
    super.key,
    this.onAnimationComplete,
    this.isDarkMode,
  });

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _streetsOpacity;
  late final Animation<double> _pinTranslateY;
  late final Animation<double> _pinScaleX;
  late final Animation<double> _pinScaleY;
  late final Animation<double> _pinOpacity;
  late final Animation<double> _rippleScale;
  late final Animation<double> _rippleOpacity;
  late final Animation<double> _node1Scale;
  late final Animation<double> _node2Scale;
  late final Animation<double> _node3Scale;
  late final Animation<double> _triangleProgress;
  late final Animation<double> _wordOpacity;
  late final Animation<double> _wordOffsetY;
  late final Animation<double> _tagOpacity;
  late final Animation<double> _tagOffsetY;

  late final TextStyle _wordStyleDark;
  late final TextStyle _wordStyleLight;
  late final TextStyle _tagStyleDark;
  late final TextStyle _tagStyleLight;

  static const int totalDurationMs = 1500;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: totalDurationMs),
    );

    _wordStyleDark = GoogleFonts.plusJakartaSans(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      letterSpacing: -0.03 * 34,
      height: 1.0,
    );
    _wordStyleLight = GoogleFonts.plusJakartaSans(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      letterSpacing: -0.03 * 34,
      height: 1.0,
    );
    _tagStyleDark = GoogleFonts.plusJakartaSans(
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      color: Colors.white.withValues(alpha: 0.70),
      letterSpacing: 0,
    );
    _tagStyleLight = GoogleFonts.plusJakartaSans(
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      color: AppColors.textMuted,
      letterSpacing: 0,
    );

    _streetsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 750 / totalDurationMs,
            curve: Curves.easeOutQuart),
      ),
    );

    const dropInterval = Interval(
      150 / totalDurationMs,
      1100 / totalDurationMs,
      curve: Curves.linear,
    );

    _pinTranslateY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: -220.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInQuart)),
        weight: 550,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 80,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -8.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 120,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -8.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 90,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: dropInterval));

    _pinScaleX = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 550,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.14)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 80,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.14, end: 0.97)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 120,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.97, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 90,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: dropInterval));

    _pinScaleY = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 550,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.84)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 80,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.84, end: 1.04)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 120,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.04, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 90,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: dropInterval));

    _pinOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 120,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 720,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: dropInterval));

    const rippleInterval = Interval(
      850 / totalDurationMs,
      1650 / totalDurationMs,
      curve: Curves.easeOutCubic,
    );
    _rippleScale = Tween<double>(begin: 0.05, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: rippleInterval),
    );
    _rippleOpacity = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: rippleInterval),
    );

    const popCurve = Cubic(0.2, 0.9, 0.3, 1.45);
    _node1Scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(950 / totalDurationMs, 1300 / totalDurationMs,
            curve: popCurve),
      ),
    );
    _node2Scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(1050 / totalDurationMs, 1400 / totalDurationMs,
            curve: popCurve),
      ),
    );
    _node3Scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(1150 / totalDurationMs, 1500 / totalDurationMs,
            curve: popCurve),
      ),
    );

    _triangleProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(1050 / totalDurationMs, 1650 / totalDurationMs,
            curve: Curves.easeOutCubic),
      ),
    );

    const wordCurve = Interval(
      1250 / totalDurationMs,
      1850 / totalDurationMs,
      curve: Curves.easeOutQuart,
    );
    _wordOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: wordCurve),
    );
    _wordOffsetY = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: wordCurve),
    );

    const tagCurve = Interval(
      1450 / totalDurationMs,
      2050 / totalDurationMs,
      curve: Curves.easeOutQuart,
    );
    _tagOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: tagCurve),
    );
    _tagOffsetY = Tween<double>(begin: 12.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: tagCurve),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete?.call();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations && !_controller.isCompleted) {
      _controller.value = 1.0;
    }

    final isDark = widget.isDarkMode ??
        (Theme.of(context).brightness == Brightness.dark);
    final sbg = isDark ? Colors.black : AppColors.background;
    final sfg = isDark ? Colors.white : AppColors.primary;
    final wordStyle = isDark ? _wordStyleDark : _wordStyleLight;
    final tagStyle = isDark ? _tagStyleDark : _tagStyleLight;

    return Scaffold(
      backgroundColor: sbg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: _streetsOpacity,
              child: Image.asset(
                'assets/images/nearhood_splash_background.webp',
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),
          ),
          RepaintBoundary(
            child: FadeTransition(
              opacity: _streetsOpacity,
              child: CustomPaint(
                painter: _SplashStreetsPainter(
                  strokeColor: sfg.withValues(alpha: 0.09),
                ),
              ),
            ),
          ),
          RepaintBoundary(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 86,
                      height: 108,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: [
                          AnimatedBuilder(
                            animation: _rippleOpacity,
                            builder: (context, child) {
                              final opacity = _rippleOpacity.value;
                              if (opacity <= 0.001) return const SizedBox.shrink();
                              final scale = _rippleScale.value;
                              return Positioned(
                                bottom: -24,
                                child: Opacity(
                                  opacity: opacity,
                                  child: Transform.scale(
                                    scaleX: scale * 1.0,
                                    scaleY: scale * 0.32,
                                    alignment: Alignment.center,
                                    child: child,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: sfg, width: 1.5),
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _controller,
                            builder: (context, child) {
                              final opacity = _pinOpacity.value;
                              if (opacity <= 0.0) return const SizedBox.shrink();
                              return Transform.translate(
                                offset: Offset(0.0, _pinTranslateY.value),
                                child: Transform.scale(
                                  scaleX: _pinScaleX.value,
                                  scaleY: _pinScaleY.value,
                                  alignment: Alignment.bottomCenter,
                                  child: opacity < 1.0
                                      ? Opacity(opacity: opacity, child: child)
                                      : child,
                                ),
                              );
                            },
                            child: CustomPaint(
                              size: const Size(86, 108),
                              painter: _SplashPinPainter(
                                pinColor: sfg,
                                innerColor: sbg,
                                node1Scale: 0,
                                node2Scale: 0,
                                node3Scale: 0,
                                triangleProgress: 0,
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) {
                              return CustomPaint(
                                size: const Size(86, 108),
                                painter: _SplashPinPainter(
                                  pinColor: Colors.transparent,
                                  innerColor: sbg,
                                  node1Scale: _node1Scale.value,
                                  node2Scale: _node2Scale.value,
                                  node3Scale: _node3Scale.value,
                                  triangleProgress: _triangleProgress.value,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FadeTransition(
                      opacity: _wordOpacity,
                      child: AnimatedBuilder(
                        animation: _wordOffsetY,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(0, _wordOffsetY.value),
                          child: child,
                        ),
                        child: Text('nearhood', style: wordStyle),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FadeTransition(
                      opacity: _tagOpacity,
                      child: AnimatedBuilder(
                        animation: _tagOffsetY,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(0, _tagOffsetY.value),
                          child: child,
                        ),
                        child: Text('one app. every local need.', style: tagStyle),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashStreetsPainter extends CustomPainter {
  final Color strokeColor;

  const _SplashStreetsPainter({required this.strokeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / 330.0 > size.height / 620.0)
        ? size.width / 330.0
        : size.height / 620.0;
    final dx = (size.width - 330.0 * scale) / 2.0;
    final dy = (size.height - 620.0 * scale) / 2.0;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);

    final thickPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final thinPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final p1 = Path()
      ..moveTo(-20, 130)
      ..cubicTo(70, 100, 130, 190, 210, 160)
      ..cubicTo(290, 130, 320, 100, 360, 130);
    canvas.drawPath(p1, thickPaint);

    final p2 = Path()
      ..moveTo(-20, 430)
      ..cubicTo(50, 400, 120, 460, 200, 420)
      ..cubicTo(280, 380, 300, 380, 360, 440);
    canvas.drawPath(p2, thickPaint);

    final p3 = Path()
      ..moveTo(60, -20)
      ..cubicTo(80, 150, 50, 330, 100, 470)
      ..cubicTo(150, 610, 130, 600, 120, 650);
    canvas.drawPath(p3, thickPaint);

    final p4 = Path()
      ..moveTo(260, -20)
      ..cubicTo(240, 140, 290, 300, 260, 450)
      ..cubicTo(230, 600, 280, 600, 290, 650);
    canvas.drawPath(p4, thickPaint);

    final t1 = Path()
      ..moveTo(-20, 290)
      ..lineTo(360, 270);
    canvas.drawPath(t1, thinPaint);

    final t2 = Path()
      ..moveTo(170, -20)
      ..lineTo(185, 650);
    canvas.drawPath(t2, thinPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SplashStreetsPainter oldDelegate) =>
      oldDelegate.strokeColor != strokeColor;
}

class _SplashPinPainter extends CustomPainter {
  final Color pinColor;
  final Color innerColor;
  final double node1Scale;
  final double node2Scale;
  final double node3Scale;
  final double triangleProgress;

  const _SplashPinPainter({
    required this.pinColor,
    required this.innerColor,
    required this.node1Scale,
    required this.node2Scale,
    required this.node3Scale,
    required this.triangleProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 40.0;
    final sy = size.height / 50.0;

    final pinPaint = Paint()
      ..color = pinColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final pinPath = Path()
      ..moveTo(20.0 * sx, 1.0 * sy)
      ..cubicTo(9.5 * sx, 1.0 * sy, 1.0 * sx, 9.3 * sy, 1.0 * sx, 19.5 * sy)
      ..cubicTo(1.0 * sx, 33.0 * sy, 20.0 * sx, 49.0 * sy, 20.0 * sx, 49.0 * sy)
      ..cubicTo(20.0 * sx, 49.0 * sy, 39.0 * sx, 33.0 * sy, 39.0 * sx, 19.5 * sy)
      ..cubicTo(39.0 * sx, 9.3 * sy, 30.5 * sx, 1.0 * sy, 20.0 * sx, 1.0 * sy)
      ..close();

    canvas.drawPath(pinPath, pinPaint);

    if (triangleProgress > 0.001) {
      final trianglePath = Path()
        ..moveTo(13.0 * sx, 15.0 * sy)
        ..lineTo(27.0 * sx, 15.0 * sy)
        ..lineTo(20.0 * sx, 28.0 * sy)
        ..close();

      final triPaint = Paint()
        ..color = innerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 * sx
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      if (triangleProgress >= 0.999) {
        canvas.drawPath(trianglePath, triPaint);
      } else {
        for (final metric in trianglePath.computeMetrics()) {
          final extractLength = metric.length * triangleProgress;
          final subPath = metric.extractPath(0.0, extractLength);
          canvas.drawPath(subPath, triPaint);
        }
      }
    }

    final nodePaint = Paint()
      ..color = innerColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final baseRadius = 3.2 * sx;

    if (node1Scale > 0.001) {
      canvas.drawCircle(
        Offset(13.0 * sx, 15.0 * sy),
        baseRadius * node1Scale,
        nodePaint,
      );
    }

    if (node2Scale > 0.001) {
      canvas.drawCircle(
        Offset(27.0 * sx, 15.0 * sy),
        baseRadius * node2Scale,
        nodePaint,
      );
    }

    if (node3Scale > 0.001) {
      canvas.drawCircle(
        Offset(20.0 * sx, 28.0 * sy),
        baseRadius * node3Scale,
        nodePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashPinPainter oldDelegate) {
    return oldDelegate.pinColor != pinColor ||
        oldDelegate.innerColor != innerColor ||
        oldDelegate.node1Scale != node1Scale ||
        oldDelegate.node2Scale != node2Scale ||
        oldDelegate.node3Scale != node3Scale ||
        oldDelegate.triangleProgress != triangleProgress;
  }
}
