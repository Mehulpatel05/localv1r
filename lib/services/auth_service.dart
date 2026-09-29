import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/api_constants.dart';
import '../core/action_state/action_state_provider.dart';
import '../core/widgets/user_avatar.dart';
import '../models/token_claims.dart';

import 'direct_chat_service.dart';
import 'notification_service.dart';
import 'token_decision_engine.dart';
import 'user_action_state_service.dart';
import 'chat_preferences_service.dart';
import 'friend_repository.dart';
import 'presence_service.dart';

enum AuthEvent {
  signedIn,
  signedOut,
  forceSignedOut,
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  static AuthService get instance => _instance;

  final StreamController<AuthEvent> _authEventController = StreamController<AuthEvent>.broadcast();
  Stream<AuthEvent> get authEvents => _authEventController.stream;

  TokenDecisionEngine _decisionEngine = TokenDecisionEngine.anonymous();
  TokenDecisionEngine get decisionEngine => _decisionEngine;

  AuthService._internal() {
    _initDecisionEngine();
  }

  Future<void> _initDecisionEngine() async {
    final token = await getAccessToken();
    if (token != null) {
      updateDecisionEngineFromToken(token);
    }
  }

  static const String baseUrl = ApiConstants.baseUrl;

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
          updateDecisionEngineFromToken(accessToken);
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

        // 2. Pure online session - ground truth in secure storage & in-memory state
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
        updateDecisionEngineFromToken(newAccess);
        return newAccess;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // ⚡ Phase 1 & 4 Instant Revocation Force Logout
        debugPrint('[AuthService] Refresh rejected (${response.statusCode}). Revoking session and purging caches.');
        await forceSignOut(reason: 'Session revoked or expired');
        return null;
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

          if (body['access_token'] != null) {
            final newTok = body['access_token'] as String;
            await _secureStorage.write(key: _kAccessTokenKey, value: newTok);
            updateDecisionEngineFromToken(newTok);
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
          }
          if (phone != null && phone.isNotEmpty) {
            await _secureStorage.write(key: _kPhoneKey, value: phone);
          }
          if (uid != null && uid.isNotEmpty) {
            await _secureStorage.write(key: _kUserIdKey, value: uid);
          }
          if (photoUrl != null && photoUrl.isNotEmpty) {
            if (handle != null && handle.isNotEmpty) {
              AvatarCacheService.instance.setCachedUrl(handle, photoUrl);
            }
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
  }

  /// ⚡ Phase 4: Complete Sign Out with Multi-Tenancy Data Purge
  Future<void> signOut() async {
    await _purgeUserSessionData();
    _authEventController.add(AuthEvent.signedOut);
  }

  /// ⚡ Phase 4: Forced Sign Out on Token Revocation or Account Ban
  Future<void> forceSignOut({String reason = 'Session expired'}) async {
    debugPrint('[AuthService] Force sign out triggered: $reason');
    await _purgeUserSessionData();
    _authEventController.add(AuthEvent.forceSignedOut);
  }

  /// Thoroughly purges all user-specific in-memory singletons, disk docs, and secure tokens
  Future<void> _purgeUserSessionData() async {
    try {
      // 1. Reset Decision Engine to Anonymous
      _decisionEngine = TokenDecisionEngine.anonymous();

      // 2. Clear Action State Singletons (Hot sets, O(1) button caches)
      ActionStateProvider.instance.clear();
      UserActionStateService.instance.clear();

      // 3. Clear Avatar, Repo, Friend, Preferences & Presence Caches
      await AvatarCacheService.instance.clearAll();
      FriendRepository().clearCache();
      ChatPreferencesService.instance.clearCache();
      PresenceService.instance.clearCache();

      // 4. Reset DirectChat & Notification Counters & Listeners
      DirectChatService.instance.unreadCountNotifier.value = 0;
      NotificationService.instance.stopListening();
      NotificationService.instance.unreadBadgeNotifier.value = 0;

      // 5. Delete Secure Storage Tokens
      await _secureStorage.deleteAll();

      // 6. Safety clear any legacy SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint('[AuthService] Multi-tenancy session purged successfully.');
    } catch (e) {
      debugPrint('[AuthService] Error during session purge: $e');
    }
  }

  // ==========================================
  // ⚡ PHASE 1: JWT IDENTITY & ZERO-DB DECISION LAYER
  // ==========================================

  /// Parses JWT payload without network calls in 0ms
  Map<String, dynamic>? parseJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      String payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decodedBytes = base64Url.decode(payload);
      final decodedString = utf8.decode(decodedBytes);
      return jsonDecode(decodedString) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[AuthService] Error parsing JWT: $e');
      return null;
    }
  }

  /// Updates in-memory Decision Engine synchronously from newly minted or refreshed JWT
  void updateDecisionEngineFromToken(String token) {
    final payload = parseJwtPayload(token);
    if (payload != null) {
      final claims = TokenClaims.fromJwtMap(payload);
      _decisionEngine = TokenDecisionEngine.fromClaims(claims);
    }
  }

  /// Extracts active token claims (uid, role, cityId, verified, planTier, banned, tokenVersion)
  Future<TokenClaims> getActiveClaims() async {
    final token = await getAccessToken();
    if (token == null) return TokenClaims.anonymous();
    final payload = parseJwtPayload(token);
    if (payload == null) return TokenClaims.anonymous();
    final claims = TokenClaims.fromJwtMap(payload);
    _decisionEngine = TokenDecisionEngine.fromClaims(claims);
    return claims;
  }

  /// Fast synchronous role getter
  Future<String> getUserRole() async {
    final claims = await getActiveClaims();
    return claims.role;
  }

  /// Fast synchronous cityId getter
  Future<String> getUserCityId() async {
    final claims = await getActiveClaims();
    return claims.cityId;
  }

  /// Fast verification state getter
  Future<bool> isUserVerified() async {
    final claims = await getActiveClaims();
    return claims.verified;
  }
}



