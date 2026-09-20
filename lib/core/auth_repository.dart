import '../../services/auth_service.dart';

/// Abstract repository contract for authentication operations.
///
/// Designed for easy dependency injection so production OTP providers
/// like Firebase Auth, Twilio, or MSG91 can be swapped in seamlessly.
abstract class AuthRepository {
  /// Sends a 6-digit OTP code to the provided Indian [phone] number.
  Future<void> sendOtp(String phone);

  /// Verifies whether the supplied 6-digit [code] is valid for [phone].
  Future<bool> verifyOtp(String phone, String code);
}

/// A fake auth repository implementation for local testing and design preview.
///
/// Simulates real-world network latency (800ms).
/// Only the OTP code `"123456"` succeeds verification; any other code returns false.
class FakeAuthRepository implements AuthRepository {
  final Duration simulatedDelay;
  final String validOtp;

  const FakeAuthRepository({
    this.simulatedDelay = const Duration(milliseconds: 800),
    this.validOtp = '123456',
  });

  @override
  Future<void> sendOtp(String phone) async {
    await Future<void>.delayed(simulatedDelay);
  }

  @override
  Future<bool> verifyOtp(String phone, String code) async {
    await Future<void>.delayed(simulatedDelay);
    return code == validOtp;
  }
}

/// Production auth repository connecting to Nearhood backend API.
///
/// Sends real SMS OTP to Indian mobile numbers via the backend service.
class BackendAuthRepository implements AuthRepository {
  final AuthService _authService;
  String? _lastRequestId;
  Map<String, dynamic>? _lastAuthResult;

  BackendAuthRepository({AuthService? authService})
      : _authService = authService ?? AuthService.instance;

  Map<String, dynamic>? get lastAuthResult => _lastAuthResult;

  @override
  Future<void> sendOtp(String phone) async {
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final e164 = cleanDigits.length == 10 ? '+91$cleanDigits' : '+$cleanDigits';
    final res = await _authService.sendOtp(e164);
    if (res['success'] == true) {
      _lastRequestId = res['requestId'] as String?;
    } else {
      throw Exception(res['error'] ?? 'Failed to send OTP.');
    }
  }

  @override
  Future<bool> verifyOtp(String phone, String code) async {
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final e164 = cleanDigits.length == 10 ? '+91$cleanDigits' : '+$cleanDigits';
    final requestId = _lastRequestId ?? 'req_${DateTime.now().millisecondsSinceEpoch}';
    final res = await _authService.verifyOtp(
      requestId: requestId,
      otp: code,
      phoneNumber: e164,
    );
    _lastAuthResult = res;
    if (res['success'] == true) {
      await _authService.syncCloudProfile();
      return true;
    }
    return false;
  }
}
