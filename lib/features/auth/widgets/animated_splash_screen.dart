import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

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
  late final Animation<double> _wordOpacity;
  late final Animation<double> _wordOffsetY;
  late final Animation<double> _tagOpacity;
  late final Animation<double> _tagOffsetY;

  late final TextStyle _wordStyle;
  late final TextStyle _tagStyle;

  static const int totalDurationMs = 1500;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: totalDurationMs),
    );

    _wordStyle = GoogleFonts.plusJakartaSans(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      letterSpacing: -0.02 * 28,
      height: 1.0,
    );
    _tagStyle = GoogleFonts.plusJakartaSans(
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      color: Colors.white.withValues(alpha: 0.70),
      letterSpacing: 0,
    );

    _streetsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.40, curve: Curves.easeOutQuart),
      ),
    );

    const dropInterval = Interval(
      0.08,
      0.55,
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
      0.45,
      0.82,
      curve: Curves.easeOutCubic,
    );
    _rippleScale = Tween<double>(begin: 0.05, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: rippleInterval),
    );
    _rippleOpacity = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: rippleInterval),
    );

    const wordCurve = Interval(
      0.65,
      0.90,
      curve: Curves.easeOutQuart,
    );
    _wordOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: wordCurve),
    );
    _wordOffsetY = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: wordCurve),
    );

    const tagCurve = Interval(
      0.75,
      1.0,
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

    final sbg = const Color(0xFF320531);
    final sfg = const Color(0xFFFEFEFC);

    return Scaffold(
      backgroundColor: sbg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF320531),
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: FadeTransition(
                opacity: _streetsOpacity,
                child: CustomPaint(
                  painter: _SplashStreetsPainter(
                    strokeColor: sfg.withValues(alpha: 0.12),
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
                        width: 96,
                        height: 96,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _rippleOpacity,
                              builder: (context, child) {
                                final opacity = _rippleOpacity.value;
                                if (opacity <= 0.001) return const SizedBox.shrink();
                                final scale = _rippleScale.value;
                                return Opacity(
                                  opacity: opacity,
                                  child: Transform.scale(
                                    scale: scale,
                                    child: child,
                                  ),
                                );
                              },
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: sfg.withValues(alpha: 0.35),
                                    width: 1.5,
                                  ),
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
                              child: Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.40),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: Image.asset(
                                    'assets/images/app_icon.png',
                                    width: 88,
                                    height: 88,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
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
                          child: Text('Urban Community', style: _wordStyle),
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
                          child: Text('Your City, Your Community', style: _tagStyle),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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


