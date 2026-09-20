import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nearhood/features/auth/widgets/animated_splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screenshotDir = Directory('screenshots');
  final artifactDir = Directory(
      r'C:\Users\swatm\.gemini\antigravity\brain\9bcc0258-759b-41b2-85dd-335b6f2a7320');

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (!screenshotDir.existsSync()) screenshotDir.createSync(recursive: true);
    if (!artifactDir.existsSync()) artifactDir.createSync(recursive: true);
  });

  Future<void> captureScreen(
    WidgetTester tester,
    GlobalKey repaintKey,
    String name,
  ) async {
    await tester.runAsync(() async {
      final boundary =
          repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      File('${screenshotDir.path}/$name.png').writeAsBytesSync(bytes);
      File('${artifactDir.path}/$name.png').writeAsBytesSync(bytes);
    });
  }

  group('AnimatedSplashScreen Tests', () {
    testWidgets('Full 2.2s animation triggers onAnimationComplete and captures light & dark screens',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;

      bool animationCompleted = false;
      final darkKey = GlobalKey();

      // --- 1. DARK MODE SPLASH CAPTURE ---
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          home: RepaintBoundary(
            key: darkKey,
            child: SizedBox(
              width: 390,
              height: 844,
              child: AnimatedSplashScreen(
                isDarkMode: true,
                onAnimationComplete: () {
                  animationCompleted = true;
                },
              ),
            ),
          ),
        ),
      );

      // Advance to 0.90s (pin landed, squashed, ripple visible)
      await tester.pump(const Duration(milliseconds: 900));
      await captureScreen(tester, darkKey, 'splash_dark_impact');

      // Advance to 2.20s+ (full complete state with wordmark and tagline)
      await tester.pump(const Duration(milliseconds: 1400));
      await captureScreen(tester, darkKey, 'splash_dark_complete');

      expect(animationCompleted, isTrue);

      // --- 2. LIGHT MODE SPLASH CAPTURE ---
      final lightKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.light,
          home: RepaintBoundary(
            key: lightKey,
            child: const SizedBox(
              width: 390,
              height: 844,
              child: AnimatedSplashScreen(
                isDarkMode: false,
              ),
            ),
          ),
        ),
      );

      // Advance to 2.20s complete
      await tester.pump(const Duration(milliseconds: 2200));
      await captureScreen(tester, lightKey, 'splash_light_complete');

      // Reset
      await tester.pumpWidget(const SizedBox());

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });
  });
}
