import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Exact Brand Logo Pin matching the HTML/SVG specification (28x36):
/// Black pin in light mode (white in dark mode) containing an inner
/// inverted triangle and 3 node circles.
class LogoPinPainter extends CustomPainter {
  final Color pinColor;
  final Color innerColor;

  const LogoPinPainter({
    required this.pinColor,
    required this.innerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Canonical SVG viewBox: 0 0 40 50
    final sx = size.width / 40.0;
    final sy = size.height / 50.0;

    // 1. Draw the map-pin silhouette: M20 1 C9.5 1 1 9.3 1 19.5 C1 33 20 49 20 49 s19 -16 19 -29.5 C39 9.3 30.5 1 20 1 Z
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

    // 2. Inner Triangle: M13 15 L27 15 L20 28 Z (stroke-width: 2)
    final trianglePaint = Paint()
      ..color = innerColor
      ..strokeWidth = 2.0 * sx
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final trianglePath = Path()
      ..moveTo(13.0 * sx, 15.0 * sy)
      ..lineTo(27.0 * sx, 15.0 * sy)
      ..lineTo(20.0 * sx, 28.0 * sy)
      ..close();

    canvas.drawPath(trianglePath, trianglePaint);

    // 3. Three Node Circles: (13,15), (27,15), (20,28), r: 3
    final nodePaint = Paint()
      ..color = innerColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final r = 3.0 * sx;
    canvas.drawCircle(Offset(13.0 * sx, 15.0 * sy), r, nodePaint);
    canvas.drawCircle(Offset(27.0 * sx, 15.0 * sy), r, nodePaint);
    canvas.drawCircle(Offset(20.0 * sx, 28.0 * sy), r, nodePaint);
  }

  @override
  bool shouldRepaint(covariant LogoPinPainter oldDelegate) =>
      oldDelegate.pinColor != pinColor || oldDelegate.innerColor != innerColor;
}

class LogoPin extends StatelessWidget {
  final double width;
  final double height;

  const LogoPin({
    super.key,
    this.width = 28.0,
    this.height = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nearhoodColors;
    return CustomPaint(
      size: Size(width, height),
      painter: LogoPinPainter(
        pinColor: colors.ink,
        innerColor: colors.bg,
      ),
    );
  }
}
