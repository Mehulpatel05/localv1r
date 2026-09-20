import 'package:flutter/material.dart';

/// StreetPainter rendering the exact abstract map street paths from the HTML specification.
class StreetPainter extends CustomPainter {
  final Color strokeColor;
  final bool isOtp;

  const StreetPainter({
    required this.strokeColor,
    this.isOtp = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Canonical viewBox in HTML: 400 x (isOtp ? 210 : 300)
    final double baseWidth = 400.0;
    final double baseHeight = isOtp ? 210.0 : 300.0;

    final sx = size.width / baseWidth;
    final sy = size.height / baseHeight;

    final thickPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0 * sx
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final thinPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * sx
      ..strokeCap = StrokeCap.round;

    if (!isOtp) {
      // --- LOGIN STREETS (viewBox 0 0 400 300) ---
      // 1. d="M-20 90 C90 60 160 150 260 120 S380 60 430 90"
      final p1 = Path()
        ..moveTo(-20 * sx, 90 * sy)
        ..cubicTo(90 * sx, 60 * sy, 160 * sx, 150 * sy, 260 * sx, 120 * sy)
        ..cubicTo(360 * sx, 90 * sy, 380 * sx, 60 * sy, 430 * sx, 90 * sy);
      canvas.drawPath(p1, thickPaint);

      // 2. d="M-20 240 C60 210 140 270 230 230 S360 190 430 250"
      final p2 = Path()
        ..moveTo(-20 * sx, 240 * sy)
        ..cubicTo(60 * sx, 210 * sy, 140 * sx, 270 * sy, 230 * sx, 230 * sy)
        ..cubicTo(320 * sx, 190 * sy, 360 * sx, 190 * sy, 430 * sx, 250 * sy);
      canvas.drawPath(p2, thickPaint);

      // 3. d="M70 -20 C90 90 60 180 110 260 S140 320 140 330"
      final p3 = Path()
        ..moveTo(70 * sx, -20 * sy)
        ..cubicTo(90 * sx, 90 * sy, 60 * sx, 180 * sy, 110 * sx, 260 * sy)
        ..cubicTo(160 * sx, 340 * sy, 140 * sx, 320 * sy, 140 * sx, 330 * sy);
      canvas.drawPath(p3, thickPaint);

      // 4. d="M310 -20 C290 80 340 160 310 250 S330 310 340 330"
      final p4 = Path()
        ..moveTo(310 * sx, -20 * sy)
        ..cubicTo(290 * sx, 80 * sy, 340 * sx, 160 * sy, 310 * sx, 250 * sy)
        ..cubicTo(280 * sx, 340 * sy, 330 * sx, 310 * sy, 340 * sx, 330 * sy);
      canvas.drawPath(p4, thickPaint);

      // Thin paths:
      // d="M-20 170 L430 150"
      canvas.drawLine(
        Offset(-20 * sx, 170 * sy),
        Offset(430 * sx, 150 * sy),
        thinPaint,
      );

      // d="M200 -20 L215 330"
      canvas.drawLine(
        Offset(200 * sx, -20 * sy),
        Offset(215 * sx, 330 * sy),
        thinPaint,
      );
    } else {
      // --- OTP STREETS (viewBox 0 0 400 210) ---
      // 1. d="M-20 80 C90 50 160 130 260 100 S380 50 430 80"
      final p1 = Path()
        ..moveTo(-20 * sx, 80 * sy)
        ..cubicTo(90 * sx, 50 * sy, 160 * sx, 130 * sy, 260 * sx, 100 * sy)
        ..cubicTo(360 * sx, 70 * sy, 380 * sx, 50 * sy, 430 * sx, 80 * sy);
      canvas.drawPath(p1, thickPaint);

      // 2. d="M70 -20 C90 70 60 140 110 230"
      final p2 = Path()
        ..moveTo(70 * sx, -20 * sy)
        ..cubicTo(90 * sx, 70 * sy, 60 * sx, 140 * sy, 110 * sx, 230 * sy);
      canvas.drawPath(p2, thickPaint);

      // 3. d="M310 -20 C290 60 340 130 320 230"
      final p3 = Path()
        ..moveTo(310 * sx, -20 * sy)
        ..cubicTo(290 * sx, 60 * sy, 340 * sx, 130 * sy, 320 * sx, 230 * sy);
      canvas.drawPath(p3, thickPaint);

      // Thin path: d="M-20 150 L430 135"
      canvas.drawLine(
        Offset(-20 * sx, 150 * sy),
        Offset(430 * sx, 135 * sy),
        thinPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StreetPainter oldDelegate) =>
      oldDelegate.strokeColor != strokeColor || oldDelegate.isOtp != isOtp;
}
