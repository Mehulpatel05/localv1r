# Nearhood — Hyperlocal Community App
> *"one app. every local need."*

Production-quality login flow featuring hero animations, street map canvas, dynamic nearby chips, Indian phone validation, 6-digit OTP verification, theme extension (light & dark mode), and accessibility compliance.

---

## Architecture & Structure

```text
lib/
  main.dart                                (App entry point, ThemeMode.system, wiring)
  core/
    theme.dart                             (NearhoodColors ThemeExtension + light/dark ThemeData)
    auth_repository.dart                   (Abstract AuthRepository + FakeAuthRepository)
  features/
    auth/
      login_flow_page.dart                 (Hero + bottom sheet + step switching + AnimatedSwitcher/Size)
      widgets/
        street_painter.dart                (CustomPainter: 4 curved thick + 3 thin straight roads)
        logo_pin.dart                      (CustomPainter: white pin shape with green triangle node network)
        nearby_pin_chip.dart               (Animated floating nearby service pills with drop-in curve)
        hero_section.dart                  (Hero background gradient, street canvas, brand row, chips, headline)
        phone_step.dart                    (Mobile number input, +91 prefix, checkmark animation, validation)
        otp_step.dart                      (6-box OTP, backspace handling, paste, 30s timer, shake on error)
        success_step.dart                  (Success checkmark pop-in, "You're in", 1.2s auto-callback)
```

---

## How to Plug in a Real OTP Provider

The authentication layer follows dependency injection via the [`AuthRepository`](file:///c:/Users/swatm/StudioProjects/localv1/lib/core/auth_repository.dart) abstract contract. You can swap in Firebase Auth, MSG91, Twilio, or your custom backend without touching any UI code.

### 1. Implement the `AuthRepository` interface

#### Example: Firebase Phone Auth Provider
```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nearhood/core/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _verificationId;

  @override
  Future<void> sendOtp(String phone) async {
    final formattedPhone = '+91$phone';
    await _auth.verifyPhoneNumber(
      phoneNumber: formattedPhone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        throw Exception(e.message ?? 'SMS verification failed');
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  @override
  Future<bool> verifyOtp(String phone, String code) async {
    if (_verificationId == null) return false;
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user != null;
    } catch (_) {
      return false;
    }
  }
}
```

#### Example: MSG91 / Custom HTTP API Provider
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nearhood/core/auth_repository.dart';

class Msg91AuthRepository implements AuthRepository {
  final String authKey;
  final String templateId;

  Msg91AuthRepository({required this.authKey, required this.templateId});

  @override
  Future<void> sendOtp(String phone) async {
    final response = await http.get(
      Uri.parse('https://control.msg91.com/api/v5/otp?template_id=$templateId&mobile=91$phone&authkey=$authKey'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send OTP via MSG91: ${response.body}');
    }
  }

  @override
  Future<bool> verifyOtp(String phone, String code) async {
    final response = await http.get(
      Uri.parse('https://control.msg91.com/api/v5/otp/verify?otp=$code&mobile=91$phone&authkey=$authKey'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['type'] == 'success';
    }
    return false;
  }
}
```

### 2. Inject into `LoginFlowPage`

In [`lib/main.dart`](file:///c:/Users/swatm/StudioProjects/localv1/lib/main.dart):
```dart
LoginFlowPage(
  authRepository: FirebaseAuthRepository(), // or Msg91AuthRepository(...)
  onLoggedIn: () {
    // Navigate to Home screen
    Navigator.of(context).pushReplacementNamed('/home');
  },
)
```

