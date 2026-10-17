import 'package:flutter/material.dart';

class StreetPainter extends CustomPainter {
  final Color strokeColor;
  final bool isOtp;

  const StreetPainter({
    required this.strokeColor,
    this.isOtp = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double baseWidth = 400.0;
    final double baseHeight = isOtp ? 210.0 : 310.0;

    final sx = size.width / baseWidth;
    final sy = size.height / baseHeight;

    final dotPaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    for (double dx = 14.0 * sx; dx < size.width; dx += 24.0 * sx) {
      for (double dy = 14.0 * sy; dy < size.height; dy += 24.0 * sy) {
        canvas.drawCircle(Offset(dx, dy), 1.1 * sx, dotPaint);
      }
    }

    final ringPaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * sx;

    final roadPaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * sx
      ..strokeCap = StrokeCap.round;

    final broadRoadPaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.5 * sx
      ..strokeCap = StrokeCap.round;

    final dashedPaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * sx;

    final center1 = Offset(330 * sx, 80 * sy);
    canvas.drawCircle(center1, 90 * sx, ringPaint);
    canvas.drawCircle(center1, 160 * sx, ringPaint);
    canvas.drawCircle(center1, 240 * sx, ringPaint);
    canvas.drawCircle(center1, 330 * sx, ringPaint);

    final center2 = Offset(-40 * sx, 280 * sy);
    canvas.drawCircle(center2, 120 * sx, ringPaint);
    canvas.drawCircle(center2, 210 * sx, ringPaint);

    final p1 = Path()
      ..moveTo(-30 * sx, 80 * sy)
      ..cubicTo(70 * sx, 50 * sy, 170 * sx, 140 * sy, 270 * sx, 110 * sy)
      ..cubicTo(350 * sx, 80 * sy, 380 * sx, 60 * sy, 440 * sx, 95 * sy);
    canvas.drawPath(p1, broadRoadPaint);

    final p2 = Path()
      ..moveTo(-20 * sx, 230 * sy)
      ..cubicTo(80 * sx, 200 * sy, 180 * sx, 250 * sy, 260 * sx, 220 * sy)
      ..cubicTo(340 * sx, 190 * sy, 380 * sx, 210 * sy, 440 * sx, 240 * sy);
    canvas.drawPath(p2, roadPaint);

    final p3 = Path()
      ..moveTo(130 * sx, -20 * sy)
      ..cubicTo(120 * sx, 90 * sy, 140 * sx, 170 * sy, 135 * sx, 260 * sy)
      ..cubicTo(130 * sx, 310 * sy, 140 * sx, 330 * sy, 150 * sx, 350 * sy);
    canvas.drawPath(p3, roadPaint);

    final p4 = Path()
      ..moveTo(310 * sx, -20 * sy)
      ..cubicTo(290 * sx, 90 * sy, 330 * sx, 190 * sy, 310 * sx, 270 * sy)
      ..cubicTo(295 * sx, 320 * sy, 320 * sx, 330 * sy, 330 * sx, 350 * sy);
    canvas.drawPath(p4, broadRoadPaint);

    final p5 = Path()
      ..moveTo(-20 * sx, 160 * sy)
      ..cubicTo(100 * sx, 130 * sy, 240 * sx, 190 * sy, 430 * sx, 155 * sy);
    canvas.drawPath(p5, roadPaint);

    final p6 = Path()
      ..moveTo(55 * sx, -20 * sy)
      ..cubicTo(48 * sx, 80 * sy, 68 * sx, 160 * sy, 58 * sx, 250 * sy)
      ..cubicTo(52 * sx, 300 * sy, 66 * sx, 330 * sy, 62 * sx, 360 * sy);
    canvas.drawPath(p6, roadPaint);

    final p7 = Path()
      ..moveTo(225 * sx, -20 * sy)
      ..cubicTo(215 * sx, 85 * sy, 235 * sx, 170 * sy, 228 * sx, 255 * sy)
      ..cubicTo(222 * sx, 305 * sy, 238 * sx, 335 * sy, 232 * sx, 360 * sy);
    canvas.drawPath(p7, broadRoadPaint);

    for (double y = 0; y < size.height; y += 14 * sy) {
      canvas.drawLine(Offset(175 * sx, y), Offset(175 * sx, y + 7 * sy), dashedPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StreetPainter oldDelegate) =>
      oldDelegate.strokeColor != strokeColor || oldDelegate.isOtp != isOtp;
}
