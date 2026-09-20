import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nearhood/core/auth_repository.dart';
import 'package:nearhood/core/theme.dart';
import 'package:nearhood/features/auth/login_flow_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screenshotDir = Directory('screenshots');
  final artifactDir = Directory(
      r'C:\Users\swatm\.gemini\antigravity\brain\9bcc0258-759b-41b2-85dd-335b6f2a7320');

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (!screenshotDir.existsSync()) {
      screenshotDir.createSync(recursive: true);
    }
    if (!artifactDir.existsSync()) {
      artifactDir.createSync(recursive: true);
    }
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

  testWidgets('Generate all required Nearhood flow screenshots',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;

    final repaintKey = GlobalKey();

    // --- STEP 1: Phone step (empty) ---
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
        theme: NearhoodTheme.lightTheme,
        darkTheme: NearhoodTheme.darkTheme,
        home: RepaintBoundary(
          key: repaintKey,
          child: const SizedBox(
            width: 390,
            height: 844,
            child: LoginFlowPage(
              authRepository: FakeAuthRepository(simulatedDelay: Duration.zero),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000)); // Hero drop-in complete
    await captureScreen(tester, repaintKey, 'phone_step_empty');

    // --- STEP 2: Phone step (valid number with ✓) ---
    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // Checkmark pop-in complete
    await captureScreen(tester, repaintKey, 'phone_step_valid');

    // --- STEP 3: OTP step ---
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send OTP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50)); // sendOtp future completes
    await tester.pump(const Duration(milliseconds: 350)); // step transition completes (250ms)
    await captureScreen(tester, repaintKey, 'otp_step');

    // --- STEP 4: Success step ---
    final otpFields = find.byType(TextField);
    const code = '123456';
    for (int i = 0; i < 6; i++) {
      await tester.enterText(otpFields.at(i), code[i]);
    }
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Verify and continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50)); // verifyOtp future completes
    await tester.pump(const Duration(milliseconds: 450)); // transition & success pop-in complete (350ms)
    await captureScreen(tester, repaintKey, 'success_step');

    // Reset widget tree before dark mode capture
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // --- STEP 5: Dark mode ---
    final darkRepaintKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: NearhoodTheme.darkTheme,
        darkTheme: NearhoodTheme.darkTheme,
        home: RepaintBoundary(
          key: darkRepaintKey,
          child: const SizedBox(
            width: 390,
            height: 844,
            child: LoginFlowPage(
              authRepository: FakeAuthRepository(simulatedDelay: Duration.zero),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await captureScreen(tester, darkRepaintKey, 'dark_mode');

    // Clean up
    await tester.pumpWidget(const SizedBox());

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
