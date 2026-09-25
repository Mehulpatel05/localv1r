import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'avatar_cache_service.dart';
import 'community_repository.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  static AuthService get instance => _instance;

  AuthService._internal();

  static const String baseUrl = 'https://localv1r.onrender.com/api/v1';

  // Secure storage instance with Android & iOS security configurations
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kAccessTokenKey = 'auth_access_token';
  static const _kRefreshTokenKey = 'auth_refresh_token';
  static const _kUserIdKey = 'auth_user_id';
  static const _kPhoneKey = 'auth_phone_number';
  static const _kHandleKey = 'auth_user_handle';

  /// Sends 6-digit OTP to user phone number via backend (which interacts with Wakit)
  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    final uri = Uri.parse('$baseUrl/auth/otp/send');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone_number': phoneNumber}),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'requestId': body['request_id'],
          'expiresIn': body['expires_in'] ?? 300,
        };
      } else {
        final errorMsg = body['error']?['message'] ?? body['detail'] ?? 'Failed to send OTP.';
        return {
          'success': false,
          'error': errorMsg,
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network connection error. Please check your internet.',
      };
    }
  }

  /// Robust check to determine if a handle belongs to a new/unconfigured account
  static bool isNewUserHandle(String? handle) {
    if (handle == null) return true;
    final h = handle.trim().toLowerCase();
    if (h.isEmpty || h == 'guest' || h.startsWith('anon#')) {
      return true;
    }
    return false;
  }

  /// Verifies OTP with backend, stores tokens securely, and authenticates session
  Future<Map<String, dynamic>> verifyOtp({
    required String requestId,
    required String otp,
    String? phoneNumber,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/otp/verify');
    try {
      final payload = <String, dynamic>{
        'request_id': requestId,
        'otp': otp,
      };
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        payload['phone_number'] = phoneNumber;
      }

      debugPrint('[AuthService] Posting OTP verification to $uri with requestId=$requestId');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      debugPrint('[AuthService] verifyOtp response status: ${response.statusCode}, body: ${response.body}');

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final accessToken = (body['access_token'] as String?) ?? '';
        final refreshToken = (body['refresh_token'] as String?) ?? '';
        final user = body['user'] as Map<String, dynamic>? ?? {};
        final userId = (user['userId'] as String?) ?? '';
        final phone = (user['phoneNumber'] as String?) ?? (phoneNumber ?? '');
        final handle = (user['handle'] as String?) ?? '';
        final isNewUser = user['isNewUser'] == true || isNewUserHandle(handle);

        // 1. Secure storage write
        if (accessToken.isNotEmpty) {
          await _secureStorage.write(key: _kAccessTokenKey, value: accessToken);
        }
        if (refreshToken.isNotEmpty) {
          await _secureStorage.write(key: _kRefreshTokenKey, value: refreshToken);
        }
        if (userId.isNotEmpty) {
          await _secureStorage.write(key: _kUserIdKey, value: userId);
        }
        if (phone.isNotEmpty) {
          await _secureStorage.write(key: _kPhoneKey, value: phone);
        }
        if (handle.isNotEmpty) {
          await _secureStorage.write(key: _kHandleKey, value: handle);
        }

        // 2. SharedPreferences cache for instant synchronous state lookups
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('is_logged_in', 'true');
        if (userId.isNotEmpty) await prefs.setString('user_id', userId);
        if (phone.isNotEmpty) await prefs.setString('phone_number', phone);
        if (handle.isNotEmpty) await prefs.setString('user_handle', handle);

        debugPrint('[AuthService] Login session saved. userId=$userId, handle=$handle, isNewUser=$isNewUser');

        return {
          'success': true,
          'userId': userId,
          'phone': phone,
          'handle': handle,
          'isNewUser': isNewUser,
        };
      } else {
        final errorMsg = body['error']?['message'] ?? body['detail'] ?? 'Verification failed.';
        debugPrint('[AuthService] Verification failed: $errorMsg (status: ${response.statusCode})');
        return {
          'success': false,
          'error': errorMsg,
          'statusCode': response.statusCode,
        };
      }
    } on TimeoutException {
      debugPrint('[AuthService] OTP verification request timed out after 15s');
      return {
        'success': false,
        'error': 'Network timeout. Please check your connection and tap Verify again.',
      };
    } catch (e, stack) {
      debugPrint('[AuthService] verifyOtp unexpected exception: $e\n$stack');
      return {
        'success': false,
        'error': 'Network connection error during verification ($e).',
      };
    }
  }

  /// Refreshes JWT token with backend
  Future<String?> refreshToken() async {
    final currentRefresh = await _secureStorage.read(key: _kRefreshTokenKey);
    if (currentRefresh == null) return null;

    final uri = Uri.parse('$baseUrl/auth/refresh');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': currentRefresh}),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final newAccess = body['access_token'] as String;
        final newRefresh = body['refresh_token'] as String;
        await _secureStorage.write(key: _kAccessTokenKey, value: newAccess);
        await _secureStorage.write(key: _kRefreshTokenKey, value: newRefresh);
        return newAccess;
      }
    } catch (e) {
      debugPrint('[AuthService] Token refresh error: $e');
    }
    return null;
  }

  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: _kAccessTokenKey);
  }

  Future<String?> getUserId() async {
    return await _secureStorage.read(key: _kUserIdKey);
  }

  Future<String?> getPhoneNumber() async {
    return await _secureStorage.read(key: _kPhoneKey);
  }

  Future<String?> getUserHandle() async {
    return await _secureStorage.read(key: _kHandleKey);
  }

  /// Checks if handle is available via backend D1
  Future<bool> checkHandleAvailable(String handle) async {
    try {
      final clean = handle.replaceAll('@', '').trim();
      final uri = Uri.parse('$baseUrl/auth/check-handle?handle=${Uri.encodeComponent(clean)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      debugPrint('[AuthService] checkHandleAvailable ($uri): status=${res.statusCode}, body=${res.body}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['available'] == true;
      }
    } catch (e) {
      debugPrint('[AuthService] checkHandleAvailable error: $e');
    }
    return true;
  }

  /// Updates user handle in Cloudflare D1
  Future<Map<String, dynamic>> saveUserHandle(String handle, {String? userId, String? phone}) async {
    final clean = handle.replaceAll('@', '').trim();

    try {
      String? token = await getAccessToken();
      token ??= await refreshToken();
      debugPrint('[AuthService] saveUserHandle: clean=$clean, tokenAvailable=${token != null && token.isNotEmpty}');
      if (token != null && token.isNotEmpty) {
        final uri = Uri.parse('$baseUrl/auth/profile/handle');
        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'handle': clean}),
        ).timeout(const Duration(seconds: 15));

        debugPrint('[AuthService] saveUserHandle response ($uri): status=${response.statusCode}, body=${response.body}');

        final body = jsonDecode(response.body);
        if (response.statusCode == 200) {
          await _secureStorage.write(key: _kHandleKey, value: clean);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_handle', clean);
          await prefs.setString('is_logged_in', 'true');

          if (body['access_token'] != null) {
            await _secureStorage.write(key: _kAccessTokenKey, value: body['access_token']);
          }
          if (body['refresh_token'] != null) {
            await _secureStorage.write(key: _kRefreshTokenKey, value: body['refresh_token']);
          }
          return {'success': true};
        } else {
          final errorMsg = body['detail'] ?? body['error']?['message'] ?? 'Failed to update username.';
          return {
            'success': false,
            'statusCode': response.statusCode,
            'isTaken': response.statusCode == 409,
            'error': errorMsg,
          };
        }
      } else {
        return {
          'success': false,
          'statusCode': 401,
          'error': 'Session expired. Please sign in again.',
        };
      }
    } on TimeoutException {
      return {
        'success': false,
        'error': 'Connection timed out. Please tap Continue again.',
      };
    } catch (e, stack) {
      debugPrint('[AuthService] D1 handle sync error: $e\n$stack');
      return {
        'success': false,
        'error': 'Network connection error during handle save ($e).',
      };
    }
  }

  /// Restores user profile, handle, and avatar from Cloudflare D1
  Future<Map<String, dynamic>?> syncCloudProfile() async {
    try {
      String? token = await getAccessToken();
      token ??= await refreshToken();
      if (token == null) return null;

      final uri = Uri.parse('$baseUrl/auth/profile');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final user = body['user'] as Map<String, dynamic>?;
        if (user != null) {
          final handle = user['handle'] as String?;
          final photoUrl = user['avatarUrl'] as String?;
          final phone = user['phoneNumber'] as String?;
          final uid = user['userId'] as String?;

          if (handle != null && handle.isNotEmpty) {
            await _secureStorage.write(key: _kHandleKey, value: handle);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_handle', handle);
          }
          if (phone != null && phone.isNotEmpty) {
            await _secureStorage.write(key: _kPhoneKey, value: phone);
          }
          if (uid != null && uid.isNotEmpty) {
            await _secureStorage.write(key: _kUserIdKey, value: uid);
          }
          if (photoUrl != null && photoUrl.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('profile_photo_url', photoUrl);
          }

          return {
            'handle': handle,
            'photoUrl': photoUrl,
            'phoneNumber': phone,
            'userId': uid,
            'reputation': user['reputation'] ?? 0,
            'upvotes': user['upvotes'] ?? 0,
            'friendCount': user['friendCount'] ?? 0,
          };
        }
      }
    } catch (e) {
      debugPrint('[AuthService] syncCloudProfile warning: $e');
    }
    return null;
  }

  Future<bool> isLoggedIn() async {
    final token = await _secureStorage.read(key: _kAccessTokenKey);
    return token != null && token.isNotEmpty;
  }

  /// Delete Account permanently via Backend D1
  Future<Map<String, dynamic>> deleteAccount() async {
    String? token = await getAccessToken();
    token ??= await refreshToken();

    final uri = Uri.parse('$baseUrl/auth/account');
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      var response = await http.delete(uri, headers: headers);

      // If 401, try refreshing token once
      if (response.statusCode == 401) {
        final newToken = await refreshToken();
        if (newToken != null) {
          headers['Authorization'] = 'Bearer $newToken';
          response = await http.delete(uri, headers: headers);
        }
      }

      if (response.statusCode == 200) {
        await signOut();
        return {'success': true};
      } else {
        try {
          final body = jsonDecode(response.body);
          final errorMsg = body['detail'] ?? body['message'] ?? 'Failed to delete account from server.';
          return {'success': false, 'error': errorMsg};
        } catch (_) {
          return {'success': false, 'error': 'Server returned status ${response.statusCode}'};
        }
      }
    } catch (e) {
      debugPrint('[AuthService] Delete account network error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Updates user profile image in Cloudflare D1
  Future<void> updateUserProfileImage(String photoUrl) async {
    final handle = await getUserHandle();
    try {
      String? token = await getAccessToken();
      token ??= await refreshToken();
      if (token != null) {
        final uri = Uri.parse('$baseUrl/auth/profile/avatar');
        await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'avatar_url': photoUrl}),
        );
      }
    } catch (e) {
      debugPrint('[AuthService] Update avatar error: $e');
    }

    if (handle != null && handle.isNotEmpty) {
      final clean = handle.replaceAll('@', '').trim().toLowerCase();
      AvatarCacheService.instance.setCachedUrl(clean, photoUrl);
    }
    await AvatarCacheService.instance.saveMyPhotoUrlLocally(photoUrl);
  }

  /// Removes user profile image in Cloudflare D1
  Future<void> removeUserProfileImage() async {
    final handle = await getUserHandle();
    try {
      String? token = await getAccessToken();
      token ??= await refreshToken();
      if (token != null) {
        final uri = Uri.parse('$baseUrl/auth/profile/avatar');
        await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'avatar_url': ''}),
        );
      }
    } catch (e) {
      debugPrint('[AuthService] Remove avatar error: $e');
    }

    if (handle != null && handle.isNotEmpty) {
      final clean = handle.replaceAll('@', '').trim().toLowerCase();
      AvatarCacheService.instance.setCachedUrl(clean, null);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_photo_url');
  }

  /// Complete Sign Out
  Future<void> signOut() async {
    try {
      CommunityRepository().clearLocalCache();
      await _secureStorage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('[AuthService] Sign out error: $e');
    }
  }
}

