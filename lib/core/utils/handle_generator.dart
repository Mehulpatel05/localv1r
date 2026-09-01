import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class HandleGenerator {
  /// Generates a secure, non-reversible, deterministic pseudonymous handle
  /// by hashing the verified phone number with a device-specific cryptographic salt.
  /// This prevents reverse identity lookup attacks (rainbow table mapping).
  static String generateSecureHandle(String phoneNumber, String salt) {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final inputBytes = utf8.encode('$cleanPhone:$salt');
    final digest = sha256.convert(inputBytes);
    
    // Extract first 6 characters of the hash for the handle suffix
    final hexDigest = digest.toString().toUpperCase();
    final suffix = hexDigest.substring(0, 6);
    
    return 'Anon#$suffix';
  }

  /// Generates a secure random salt for storage on the client device
  static String generateRandomSalt() {
    final secureRandom = Random.secure();
    final randomValues = List<int>.generate(32, (_) => secureRandom.nextInt(256));
    return base64Url.encode(randomValues);
  }
}
