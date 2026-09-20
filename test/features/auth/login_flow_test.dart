import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearhood/core/auth_repository.dart';
import 'package:nearhood/core/theme.dart';
import 'package:nearhood/features/auth/login_flow_page.dart';
import 'package:nearhood/features/auth/widgets/phone_step.dart';
import 'package:nearhood/features/auth/widgets/otp_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthRepository Unit Tests', () {
    test('FakeAuthRepository validates 123456 and rejects others', () async {
      const repo = FakeAuthRepository(
        simulatedDelay: Duration(milliseconds: 10),
      );

      await repo.sendOtp('9876543210');
      final valid = await repo.verifyOtp('9876543210', '123456');
      final invalid = await repo.verifyOtp('9876543210', '000000');

      expect(valid, isTrue);
      expect(invalid, isFalse);
    });
  });

  group('Nearhood Theme Tokens', () {
    test('NearhoodColors light and dark theme extension values', () {
      expect(NearhoodColors.light.bg, const Color(0xFFFFFFFF));
      expect(NearhoodColors.light.btn, const Color(0xFF000000));
      expect(NearhoodColors.dark.bg, const Color(0xFF000000));
      expect(NearhoodColors.dark.btn, const Color(0xFFFFFFFF));
    });

    testWidgets('NearhoodColors dark theme in context', (tester) async {
      late NearhoodColors resolvedColors;
      await tester.pumpWidget(
        MaterialApp(
          theme: NearhoodTheme.darkTheme,
          home: Builder(
            builder: (context) {
              resolvedColors = context.nearhoodColors;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(resolvedColors.field, const Color(0xFF141414));
    });
  });

  group('PhoneStep Widget Tests', () {
    testWidgets('Validates Indian phone number and toggles Send OTP button',
        (tester) async {
      final repo = const FakeAuthRepository(
        simulatedDelay: Duration.zero,
      );
      String? submittedPhone;

      await tester.pumpWidget(
        MaterialApp(
          theme: NearhoodTheme.lightTheme,
          home: Scaffold(
            body: PhoneStep(
              authRepository: repo,
              onPhoneSubmitted: (p) => submittedPhone = p,
            ),
          ),
        ),
      );

      // Button is initially disabled
      final sendOtpButtonFinder = find.widgetWithText(ElevatedButton, 'Send OTP');
      expect(tester.widget<ElevatedButton>(sendOtpButtonFinder).onPressed, isNull);

      // Enter 10 digits starting with invalid digit (e.g. 1)
      await tester.enterText(find.byType(TextField), '1234567890');
      await tester.pump();
      expect(find.text('Enter a valid Indian mobile number starting with 6–9.'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(sendOtpButtonFinder).onPressed, isNull);

      // Enter valid Indian mobile number starting with 9
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.pump();
      expect(find.byKey(const Key('phone_valid_tick')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(sendOtpButtonFinder).onPressed, isNotNull);

      // Tap Send OTP
      await tester.tap(sendOtpButtonFinder);
      await tester.pumpAndSettle();
      expect(submittedPhone, '9876543210');
    });
  });

  group('OtpStep Widget Tests', () {
    testWidgets('Auto-moves and rejects incorrect code with shake error',
        (tester) async {
      final repo = const FakeAuthRepository(
        simulatedDelay: Duration.zero,
      );
      bool verified = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: NearhoodTheme.lightTheme,
          home: Scaffold(
            body: OtpStep(
              phone: '9876543210',
              authRepository: repo,
              onChangeNumber: () {},
              onVerified: () => verified = true,
            ),
          ),
        ),
      );

      // Verify formatted phone number
      expect(find.text('Sent to +91 98765 43210'), findsOneWidget);

      // Enter incorrect OTP
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(6));

      for (int i = 0; i < 6; i++) {
        await tester.enterText(textFields.at(i), '0');
      }
      await tester.pump();

      final verifyButton = find.widgetWithText(ElevatedButton, 'Verify and continue');
      await tester.tap(verifyButton);
      await tester.pumpAndSettle();

      expect(verified, isFalse);
      expect(find.text('Incorrect code. Try again.'), findsOneWidget);

      // Enter correct code "123456"
      const correctCode = '123456';
      for (int i = 0; i < 6; i++) {
        await tester.enterText(textFields.at(i), correctCode[i]);
      }
      await tester.pump();

      await tester.tap(verifyButton);
      await tester.pumpAndSettle();
      expect(verified, isTrue);
    });
  });

  group('Responsiveness & Overflow Prevention', () {
    testWidgets('No overflow on small screen (360x640) with virtual keyboard and 1.3x font scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      // Simulate 280px keyboard inset
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            viewInsets: EdgeInsets.only(bottom: 280),
            textScaler: TextScaler.linear(1.3),
          ),
          child: MaterialApp(
            theme: NearhoodTheme.lightTheme,
            home: const LoginFlowPage(
              authRepository: FakeAuthRepository(simulatedDelay: Duration.zero),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Reset view
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });
    });
  });
}
