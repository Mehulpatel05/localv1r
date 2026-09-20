import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_native_splash/flutter_native_splash.dart';

/// Kinetic Animated Splash Screen for Nearhood replicating the exact
/// HTML/CSS timeline with hardware-accelerated 60/120 FPS buttery smoothness:
/// - 0.00s–0.55s: Streets vector background fades in.
/// - 0.12s–0.78s: Map pin drops from above with squash and rebound bounce.
/// - 0.65s–1.25s: Perspective elliptical ripple pulse emanates from pin tip.
/// - 0.70s–1.00s: Three network nodes sequentially pop in with cubic-bezier elastic overshoot.
/// - 0.75s–1.20s: Inverted triangle stroke path connects the nodes.
/// - 0.90s–1.35s: Wordmark "nearhood" slides up and fades in.
/// - 1.05s–1.50s: Tagline "one app. every local need." slides up and fades in.
/// - 1.60s: Triggers [onAnimationComplete] for soft cross-fade to Main/Login.
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

  // GPU-composited animations (run on compositor thread, not UI thread)
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

  // Cached text styles to avoid allocations on each frame
  late final TextStyle _wordStyleDark;
  late final TextStyle _wordStyleLight;
  late final TextStyle _tagStyleDark;
  late final TextStyle _tagStyleLight;

  static const int totalDurationMs = 2500; // Cinematic, luxurious, ultra-smooth

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: totalDurationMs),
    );

    // Pre-cache GoogleFonts styles once
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
      color: Colors.black,
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
      color: Colors.black.withValues(alpha: 0.70),
      letterSpacing: 0,
    );

    // 1. Streets Fade: 0.0s to 0.75s — easeOutQuart
    _streetsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 750 / totalDurationMs,
            curve: Curves.easeOutQuart),
      ),
    );

    // 2. Drop sequence: 0.15s to 1.10s
    const dropInterval = Interval(
      150 / totalDurationMs,
      1100 / totalDurationMs,
      curve: Curves.linear,
    );

    // Drop TranslateY
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

    // Drop ScaleX
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

    // Drop ScaleY
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

    // Drop Opacity
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

    // 3. Tip Ripple Pulse: 0.85s to 1.65s
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

    // 4. Three Nodes Pop — elastic overshoot
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

    // 5. Triangle path draw: 1.05s to 1.65s
    _triangleProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(1050 / totalDurationMs, 1650 / totalDurationMs,
            curve: Curves.easeOutCubic),
      ),
    );

    // 6. Wordmark: 1.25s to 1.85s
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

    // 7. Tagline: 1.45s to 2.05s
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

    // Remove native splash and start kinetic animation on very first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
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
    final sbg = isDark ? Colors.black : Colors.white;
    final sfg = isDark ? Colors.white : Colors.black;
    final wordStyle = isDark ? _wordStyleDark : _wordStyleLight;
    final tagStyle = isDark ? _tagStyleDark : _tagStyleLight;

    return Scaffold(
      backgroundColor: sbg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Street Map Background — FadeTransition runs on compositor (GPU) thread
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

          // 2. Center Branding
          RepaintBoundary(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pin Mark Wrap
                    SizedBox(
                      width: 86,
                      height: 108,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: [
                          // Ripple Ring — clipped to save GPU overdraw when invisible
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

                          // Map Pin — all transforms batched in single AnimatedBuilder
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
                                node1Scale: 0, // driven by AnimatedBuilder below
                                node2Scale: 0,
                                node3Scale: 0,
                                triangleProgress: 0,
                              ),
                            ),
                          ),

                          // Nodes & Triangle — separate AnimatedBuilder so pin drop
                          // doesn't force nodes to re-layout unnecessarily
                          AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) {
                              return CustomPaint(
                                size: const Size(86, 108),
                                painter: _SplashPinPainter(
                                  pinColor: Colors.transparent, // pin drawn above
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

                    // Wordmark — FadeTransition + SlideTransition are GPU-composited
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

                    // Tagline — same pattern
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

/// CustomPainter rendering the exact streets SVG paths from HTML
/// (viewBox="0 0 330 620" preserveAspectRatio="xMidYMid slice")
class _SplashStreetsPainter extends CustomPainter {
  final Color strokeColor;

  const _SplashStreetsPainter({required this.strokeColor});

  @override
  void paint(Canvas canvas, Size size) {
    // PreserveAspect slice over 330x620
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

    // Curved thick road 1: M-20 130 C70 100 130 190 210 160 S320 100 360 130
    final p1 = Path()
      ..moveTo(-20, 130)
      ..cubicTo(70, 100, 130, 190, 210, 160)
      ..cubicTo(290, 130, 320, 100, 360, 130);
    canvas.drawPath(p1, thickPaint);

    // Curved thick road 2: M-20 430 C50 400 120 460 200 420 S300 380 360 440
    final p2 = Path()
      ..moveTo(-20, 430)
      ..cubicTo(50, 400, 120, 460, 200, 420)
      ..cubicTo(280, 380, 300, 380, 360, 440);
    canvas.drawPath(p2, thickPaint);

    // Curved thick road 3: M60 -20 C80 150 50 330 100 470 S130 600 120 650
    final p3 = Path()
      ..moveTo(60, -20)
      ..cubicTo(80, 150, 50, 330, 100, 470)
      ..cubicTo(150, 610, 130, 600, 120, 650);
    canvas.drawPath(p3, thickPaint);

    // Curved thick road 4: M260 -20 C240 140 290 300 260 450 S280 600 290 650
    final p4 = Path()
      ..moveTo(260, -20)
      ..cubicTo(240, 140, 290, 300, 260, 450)
      ..cubicTo(230, 600, 280, 600, 290, 650);
    canvas.drawPath(p4, thickPaint);

    // Thin straight road 1: M-20 290 L360 270
    final t1 = Path()
      ..moveTo(-20, 290)
      ..lineTo(360, 270);
    canvas.drawPath(t1, thinPaint);

    // Thin straight road 2: M170 -20 L185 650
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

/// CustomPainter rendering the pin silhouette, popping nodes, and
/// progressively drawn connecting triangle stroke.
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
    // Canonical SVG viewBox: 0 0 40 50
    final sx = size.width / 40.0;
    final sy = size.height / 50.0;

    // 1. Draw Map Pin Body: M20 1 C9.5 1 1 9.3 1 19.5 C1 33 20 49 20 49 s19 -16 19 -29.5 C39 9.3 30.5 1 20 1 Z
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

    // 2. Triangle Lines: M13 15 H27 L20 28 Z (drawn with stroke-dashoffset equivalent)
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

    // 3. Three Nodes: (13,15), (27,15), (20,28), r: 3.2
    final nodePaint = Paint()
      ..color = innerColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final baseRadius = 3.2 * sx;

    // Node 1 (left)
    if (node1Scale > 0.001) {
      canvas.drawCircle(
        Offset(13.0 * sx, 15.0 * sy),
        baseRadius * node1Scale,
        nodePaint,
      );
    }

    // Node 2 (right)
    if (node2Scale > 0.001) {
      canvas.drawCircle(
        Offset(27.0 * sx, 15.0 * sy),
        baseRadius * node2Scale,
        nodePaint,
      );
    }

    // Node 3 (bottom)
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
        oldDelegate.triangleProgress != triangleP