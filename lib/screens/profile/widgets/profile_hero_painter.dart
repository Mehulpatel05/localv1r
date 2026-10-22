import 'package:flutter/material.dart';

class ProfileHeaderBackgroundPainter extends CustomPainter {
  const ProfileHeaderBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF250921),
          Color(0xFF3A0F34),
          Color(0xFF4C1544),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    final darkCurvePaint = Paint()
      ..color = const Color(0xFF1E071B).withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    final lightCurvePaint = Paint()
      ..color = const Color(0xFF6B2562).withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    final path1 = Path()
      ..moveTo(w * 0.4, 0)
      ..cubicTo(w * 0.55, h * 0.25, w * 0.85, h * 0.45, w, h * 0.4)
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(path1, darkCurvePaint);

    final path2 = Path()
      ..moveTo(0, h * 0.55)
      ..cubicTo(w * 0.25, h * 0.45, w * 0.45, h * 0.75, w * 0.6, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path2, lightCurvePaint);

    final circlePaint = Paint()
      ..color = const Color(0xFF6B2562).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(Offset(w * 0.85, h * 0.3), 85, circlePaint);
    canvas.drawCircle(Offset(w * 0.85, h * 0.3), 150, circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ProfileHeroIllustrationPainter extends CustomPainter {
  const ProfileHeroIllustrationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const ProfileHeaderBackgroundPainter().paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ProfileBackgroundPatternPainter extends CustomPainter {
  final bool isDark;

  const ProfileBackgroundPatternPainter({this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF10191A) : const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
  }

  @override
  bool shouldRepaint(covariant ProfileBackgroundPatternPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
