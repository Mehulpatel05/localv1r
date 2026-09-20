import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nearhood/features/auth/widgets/logo_pin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Generate high-res 1024x1024 app icon from vector LogoPin', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1.0;

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: repaintKey,
          child: Container(
            width: 1024,
            height: 1024,
            color: Colors.black,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 410,
              height: 525,
              child: CustomPaint(
                size: Size(410, 525),
                painter: LogoPinPainter(
                  pinColor: Colors.white,
                  innerColor: Colors.black,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary =
          repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      File('assets/images/nearhood_app_icon_1024.png').writeAsBytesSync(bytes);
    });

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('Generate nearhood_logo.png matching monochrome branding', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 2.0;

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: repaintKey,
          child: Container(
            width: 400,
            height: 350,
            color: Colors.transparent,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 110,
                  height: 140,
                  child: CustomPaint(
                    size: Size(110, 140),
                    painter: LogoPinPainter(
                      pinColor: Colors.black,
                      innerColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'nearhood',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'one app. every local need.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6E6E6E),
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary =
          repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      File('assets/images/nearhood_logo.png').writeAsBytesSync(bytes);
    });

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
