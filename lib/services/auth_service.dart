import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/api_constants.dart';
import '../core/utils/api_error.dart';
import '../core/action_state/action_state_provider.dart';
import '../core/widgets/user_avatar.dart';
import '../core/services/name_cache_service.dart';
import '../core/services/badge_cache_service.dart';
import '../models/token_claims.dart';

import 'direct_chat_service.dart';
import 'notification_service.dart';
import 'token_decision_engine.dart';
import 'user_action_state_service.dart';
import 'chat_preferences_service.dart';
import 'friend_repository.dart';
import 'presence_service.dart';
import 'post_repository.dart';
import 'rewards_service.dart';

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

  Completer<String?>? _refreshCompleter;

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
      ).timeout(const Duration(seconds: 35));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'requestId': body['request_id'],
          'expiresIn': body['expires_in'] ?? 300,
        };
      } else {
        final errorMsg = extractApiError(body, 'Failed to send OTP.');
        return {
          'success': false,
          'error': errorMsg,
          'statusCode': response.statusCode,
        };
      }
    } on TimeoutException {
      return {
        'success': false,
        'error': 'Server is starting up, please wait a moment and try again.',
      };
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
    final h = handle.trim().toLowerCase().replaceAll('@', '');
    if (h.isEmpty || h == 'guest' || h.startsWith('anon#') || h.startsWith('user_')) {
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
      ).timeout(const Duration(seconds: 35));

      debugPrint('[AuthService] verifyOtp response status: ${response.statusCode}, body: ${response.body}');

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final accessToken = (body['access_token'] as String?) ?? (body['sessionToken'] as String?) ?? '';
        final refreshToken = (body['refresh_token'] as String?) ?? '';
        final user = body['user'] as Map<String, dynamic>? ?? {};
        final userId = (user['userId'] as String?) ?? '';
        final phone = (user['phoneNumber'] as String?) ?? (phoneNumber ?? '');
        final handle = (user['handle'] as String?) ?? (body['handle'] as String?) ?? '';
        final displayName = ((user['displayName'] ?? user['display_name'] ?? body['displayName']) as String?)?.trim() ?? '';
        final avatarUrl = ((user['avatarUrl'] ?? user['avatar_url']) as String?)?.trim() ?? '';
        final isNewUser = body['isNewUser'] == true || user['isNewUser'] == true || isNewUserHandle(handle);

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

        if (isNewUser) {
          await AvatarCacheService.instance.clearAll();
          NameCacheService.instance.clearAll();
        } else if (handle.isNotEmpty) {
          if (displayName.isNotEmpty && !NameCacheService.isPlaceholderName(displayName)) {
            NameCacheService.instance.setCachedName(handle, displayName);
            await NameCacheService.instance.saveMyNameLocally(displayName);
          }
          AvatarCacheService.instance.setCachedUrl(handle, avatarUrl.isNotEmpty ? avatarUrl : null);
          await AvatarCacheService.instance.saveMyPhotoUrlLocally(avatarUrl);
        }

        try {
          final prefs = await SharedPreferences.getInstance();
          if (handle.isNotEmpty) await prefs.setString('user_handle', handle);
          if (userId.isNotEmpty) await prefs.setString('user_id', userId);
          if (accessToken.isNotEmpty) await prefs.setString('auth_access_token', accessToken);
          await prefs.remove('phone_number');
        } catch (_) {}


        debugPrint('[AuthService] Login session saved. userId=$userId, handle=$handle, isNewUser=$isNewUser');

        return {
          'success': true,
          'userId': userId,
          'phone': phone,
          'handle': handle,
          'isNewUser': isNewUser,
        };
      } else {
        final errorMsg = extractApiError(body, 'Verification failed.');
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

  Future<String?> refreshToken() async {
    if (_refreshCompleter != null) {
      return await _refreshCompleter!.future;
    }

    final completer = Completer<String?>();
    _refreshCompleter = completer;

    try {
      final currentRefresh = await _secureStorage.read(key: _kRefreshTokenKey);
      if (currentRefresh == null) {
        completer.complete(null);
        return null;
      }

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
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('auth_access_token', newAccess);
          } catch (_) {}
          updateDecisionEngineFromToken(newAccess);
          completer.complete(newAccess);
          return newAccess;
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          debugPrint('[AuthService] Refresh rejected (${response.statusCode}). Revoking session and purging caches.');
          await forceSignOut(reason: 'Session revoked or expired');
          completer.complete(null);
          return null;
        }
      } catch (e) {
        debugPrint('[AuthService] Token refresh error: $e');
      }
      completer.complete(null);
      return null;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<String?> getAccessToken() async {
    try {
      final token = await _secureStorage.read(key: _kAccessTokenKey).timeout(const Duration(milliseconds: 1500));
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_access_token') ?? prefs.getString('access_token');
    } catch (_) {}
    return null;
  }

  Future<String?> getUserId() async {
    try {
      final uid = await _secureStorage.read(key: _kUserIdKey).timeout(const Duration(milliseconds: 1500));
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_id');
    } catch (_) {}
    return null;
  }

  Future<String?> getPhoneNumber() async {
    try {
      final phone = await _secureStorage.read(key: _kPhoneKey).timeout(const Duration(milliseconds: 1500));
      if (phone != null && phone.isNotEmpty) return phone;
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('phone_number');
    } catch (_) {}
    return null;
  }

  Future<String?> getUserHandle() async {
    try {
      final handle = await _secureStorage.read(key: _kHandleKey).timeout(const Duration(milliseconds: 1500));
      if (handle != null && handle.isNotEmpty) return handle;
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefHandle = prefs.getString('user_handle') ?? prefs.getString('current_user_handle');
      if (prefHandle != null && prefHandle.isNotEmpty) return prefHandle;
    } catch (_) {}
    return null;
  }

  Future<bool> checkHandleAvailable(String handle) async {
    try {
      final clean = handle.replaceAll('@', '').trim();
      final uri = Uri.parse('$baseUrl/auth/check-handle?handle=${Uri.encodeComponent(clean)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      debugPrint('[AuthService] checkHandleAvailable ($uri): status=${res.statusCode}, body=${res.body}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic> && data.containsKey('available')) {
          return data['available'] == true;
        }
      }
      throw Exception('Server returned ${res.statusCode}');
    } catch (e) {
      debugPrint('[AuthService] checkHandleAvailable error: $e');
      rethrow;
    }
  }

  /// Updates user handle in Cloudflare D1
  Future<Map<String, dynamic>> saveUserHandle(
    String handle, {
    String? userId,
    String? phone,
    String? name,
    String? cityId,
    String? areaId,
    String? areaName,
    String? addressNote,
  }) async {
    final clean = handle.replaceAll('@', '').trim();
    final cleanName = name?.trim();

    try {
      String? token = await getAccessToken();
      token ??= await refreshToken();
      debugPrint('[AuthService] saveUserHandle: clean=$clean, name=$cleanName, tokenAvailable=${token != null && token.isNotEmpty}');
      if (token != null && token.isNotEmpty) {
        final uri = Uri.parse('$baseUrl/auth/profile/handle');
        final requestBody = <String, dynamic>{
          'handle': clean,
        };
        if (cleanName != null && cleanName.isNotEmpty) {
          requestBody['name'] = cleanName;
          requestBody['displayName'] = cleanName;
        }
        if (cityId != null && cityId.isNotEmpty) requestBody['home_city_id'] = cityId;
        if (areaId != null && areaId.isNotEmpty) requestBody['home_area_id'] = areaId;
        if (areaName != null && areaName.isNotEmpty) requestBody['home_area_name'] = areaName;
        if (addressNote != null && addressNote.isNotEmpty) requestBody['address_note'] = addressNote;

        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 15));

        debugPrint('[AuthService] saveUserHandle response ($uri): status=${response.statusCode}, body=${response.body}');

        final body = jsonDecode(response.body);
        if (response.statusCode == 200) {
          await _secureStorage.write(key: _kHandleKey, value: clean);
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_handle', clean);
            if (cityId != null && cityId.isNotEmpty) await prefs.setString('selected_city_id', cityId);
            if (areaId != null && areaId.isNotEmpty) await prefs.setString('selected_area_id', areaId);
            if (areaName != null && areaName.isNotEmpty) {
              await prefs.setString('home_area_name', areaName);
              await prefs.setString('selected_area_name', areaName);
            }
            if (addressNote != null && addressNote.isNotEmpty) await prefs.setString('address_note', addressNote);
          } catch (_) {}

          if (cleanName != null && cleanName.isNotEmpty) {
            await _secureStorage.write(key: 'user_display_name', value: cleanName);
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('user_display_name', cleanName);
            } catch (_) {}
            NameCacheService.instance.setCachedName(clean, cleanName);
            await NameCacheService.instance.saveMyNameLocally(cleanName);
          }

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
          final errorMsg = extractApiError(body, 'Failed to update username.');
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

  Future<void> updateLocalUserCredentials({required String handle, String? displayName}) async {
    final clean = handle.replaceAll('@', '').trim();
    if (clean.isNotEmpty) {
      await _secureStorage.write(key: _kHandleKey, value: clean);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_handle', clean);
        await prefs.setString('current_user_handle', clean);
        await prefs.setString('active_user_handle', clean);
      } catch (_) {}
    }
    if (displayName != null && displayName.trim().isNotEmpty) {
      final cleanName = displayName.trim();
      await _secureStorage.write(key: 'user_display_name', value: cleanName);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_display_name', cleanName);
      } catch (_) {}
      NameCacheService.instance.setCachedName(clean, cleanName);
      await NameCacheService.instance.saveMyNameLocally(cleanName);
    }
  }

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
          final rawName = (user['name'] ?? user['displayName'] ?? user['fullName']) as String?;
          final displayName = (rawName != null && rawName.trim().isNotEmpty) ? rawName.trim() : null;

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
          if (displayName != null && displayName.isNotEmpty) {
            await _secureStorage.write(key: 'user_display_name', value: displayName);
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('user_display_name', displayName);
            } catch (_) {}
            if (handle != null && handle.isNotEmpty) {
              NameCacheService.instance.setCachedName(handle, displayName);
            }
            await NameCacheService.instance.saveMyNameLocally(displayName);
          }

          return {
            'handle': handle,
            'name': displayName,
            'displayName': displayName,
            'photoUrl': photoUrl,
            'phoneNumber': phone,
            'userId': uid,
            'reputation': user['reputation'] ?? 0,
            'upvotes': user['upvotes'] ?? 0,
            'friendCount': user['friendCount'] ?? 0,
            'isVerified': user['isVerified'] == true || user['is_verified'] == 1,
            'bio': user['bio'] ?? '',
            'nameUpdatedAt': user['nameUpdatedAt'] ?? user['name_updated_at'],
            'handleUpdatedAt': user['handleUpdatedAt'] ?? user['handle_updated_at'],
            'canChangeName': user['canChangeName'] ?? user['can_change_name'] ?? true,
            'canChangeHandle': user['canChangeHandle'] ?? user['can_change_handle'] ?? true,
            'nameDaysRemaining': user['nameDaysRemaining'] ?? user['name_days_remaining'] ?? 0,
            'handleDaysRemaining': user['handleDaysRemaining'] ?? user['handle_days_remaining'] ?? 0,
            'nextNameChangeAt': user['nextNameChangeAt'] ?? user['next_name_change_at'],
            'nextHandleChangeAt': user['nextHandleChangeAt'] ?? user['next_handle_change_at'],
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

  Future<String?> getDisplayName() async {
    final cached = await NameCacheService.instance.getMyNameLocally();
    if (cached != null && cached.trim().isNotEmpty) return cached.trim();
    final stored = await _secureStorage.read(key: 'user_display_name');
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_display_name');
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> deleteAccount() async {
    String? token = await getAccessToken();
    token ??= await refreshToken();

    final uri = Uri.parse('$baseUrl/account/purge');
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      var response = await http.delete(uri, headers: headers);

      if (response.statusCode == 401) {
        final newToken = await refreshToken();
        if (newToken != null) {
          headers['Authorization'] = 'Bearer $newToken';
          response = await http.delete(uri, headers: headers);
        }
      }

      if (response.statusCode == 404) {
        response = await http.delete(Uri.parse('$baseUrl/account'), headers: headers);
      }

      if (response.statusCode == 200 || response.statusCode == 204) {
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
    await AvatarCacheService.instance.saveMyPhotoUrlLocally('');
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
      _decisionEngine = TokenDecisionEngine.anonymous();
      TokenDecisionEngine.clear();

      ActionStateProvider.instance.clear();
      UserActionStateService.instance.clear();

      await AvatarCacheService.instance.clearAll();
      FriendRepository().clearCache();
      ChatPreferencesService.instance.clearCache();
      PresenceService.instance.clearCache();
      PostRepository.instance.clearCache();
      DirectChatService.instance.clearCache();
      NameCacheService.instance.clearAll();
      BadgeCacheService.instance.clear();
      RewardsService.instance.clearCache();

      DirectChatService.instance.unreadCountNotifier.value = 0;
      NotificationService.instance.stopListening();
      NotificationService.instance.unreadBadgeNotifier.value = 0;

      await _secureStorage.deleteAll();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_handle');
      await prefs.remove('user_id');
      await prefs.remove('phone_number');
      await prefs.remove('user_display_name');
      await prefs.remove('auth_access_token');
      await prefs.remove('access_token');
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
    final TokenClaims claims;
    if (payload != null) {
      claims = TokenClaims.fromJwtMap(payload);
    } else if (token.isNotEmpty) {
      claims = TokenClaims(
        uid: '',
        role: 'user',
        cityId: 'GJ-VAD',
        verified: true,
        handle: '',
        planTier: 'free',
        banned: false,
        tokenVersion: 1,
        exp: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
      );
    } else {
      claims = TokenClaims.anonymous();
    }
    _decisionEngine = TokenDecisionEngine.fromClaims(claims);
    TokenDecisionEngine.updateFromClaims(claims);
  }

  /// Extracts active token claims (uid, role, cityId, verified, planTier, banned, tokenVersion)
  Future<TokenClaims> getActiveClaims() async {
    final token = await getAccessToken();
    if (token == null || token.isEmpty) {
      final anon = TokenClaims.anonymous();
      _decisionEngine = TokenDecisionEngine.fromClaims(anon);
      TokenDecisionEngine.updateFromClaims(anon);
      return anon;
    }
    final payload = parseJwtPayload(token);
    final TokenClaims claims;
    if (payload != null) {
      claims = TokenClaims.fromJwtMap(payload);
    } else {
      final handle = await getUserHandle() ?? '';
      final uid = await getUserId() ?? '';
      claims = TokenClaims(
        uid: uid,
        role: 'user',
        cityId: 'GJ-VAD',
        verified: true,
        handle: handle,
        planTier: 'free',
        banned: false,
        tokenVersion: 1,
        exp: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
      );
    }
    _decisionEngine = TokenDecisionEngine.fromClaims(claims);
    TokenDecisionEngine.updateFromClaims(claims);
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

  Future<bool> isUserVerified() async {
    final claims = await getActiveClaims();
    return claims.verified;
  }

  Future<List<Map<String, dynamic>>> searchPlacesAutocomplete(
    String query, {
    String? sessionToken,
  }) async {
    try {
      final token = await getAccessToken();
      final url = Uri.parse('$baseUrl/places/autocomplete?q=${Uri.encodeComponent(query)}${sessionToken != null && sessionToken.isNotEmpty ? '&session=${Uri.encodeComponent(sessionToken)}' : ''}');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['predictions'] is List) {
          return List<Map<String, dynamic>>.from(data['predictions']);
        }
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> resolveArea(
    String? placeId, {
    String? name,
    String? cityId,
    String? sessionToken,
  }) async {
    try {
      final token = await getAccessToken();
      final url = Uri.parse('$baseUrl/areas/resolve');
      final payload = <String, dynamic>{
        if (placeId != null && placeId.isNotEmpty) 'place_id': placeId,
        if (name != null && name.isNotEmpty) 'name': name,
        if (cityId != null && cityId.isNotEmpty) 'city_id': cityId,
        if (sessionToken != null && sessionToken.isNotEmpty) 'session': sessionToken,
      };
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> getEnabledCities() async {
    try {
      final token = await getAccessToken();
      final url = Uri.parse('$baseUrl/places/cities');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['cities'] is List) {
          return List<Map<String, dynamic>>.from(data['cities']);
        }
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> reverseGeocodeCoordinates(
    double lat,
    double lng,
  ) async {
    try {
      final token = await getAccessToken();
      final url = Uri.parse('$baseUrl/places/reverse-geocode?lat=$lat&lng=$lng');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> joinWaitlist({
    required String cityText,
    double? lat,
    double? lng,
    required String contactOrDeviceId,
  }) async {
    try {
      final token = await getAccessToken();
      final url = Uri.parse('$baseUrl/waitlist');
      final payload = <String, dynamic>{
        'city_text': cityText,
        'contact_or_device_id': contactOrDeviceId,
      };
      if (lat != null) payload['lat'] = lat;
      if (lng != null) payload['lng'] = lng;

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<List<Map<String, dynamic>>> fetchPopularAreas({
    String cityId = 'GJ-VAD',
  }) async {
    try {
      final token = await getAccessToken();
      final url = Uri.parse('$baseUrl/areas/popular?city_id=$cityId');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['areas'] is List) {
          return List<Map<String, dynamic>>.from(data['areas']);
        }
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> confirmAreaDetails({
    String? areaId,
    String? areaName,
    String? cityId,
    String? addressNote,
  }) async {
    try {
      final token = await getAccessToken();
      final url = Uri.parse('$baseUrl/auth/confirm-area');
      final payload = <String, dynamic>{
        if (areaId != null && areaId.isNotEmpty) 'area_id': areaId,
        if (areaName != null && areaName.isNotEmpty) 'area_name': areaName,
        if (cityId != null && cityId.isNotEmpty) 'city_id': cityId,
        if (addressNote != null && addressNote.isNotEmpty) 'address_note': addressNote,
      };
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (cityId != null && cityId.isNotEmpty) await prefs.setString('selected_city_id', cityId);
          if (areaId != null && areaId.isNotEmpty) await prefs.setString('selected_area_id', areaId);
          if (areaName != null && areaName.isNotEmpty) {
            await prefs.setString('home_area_name', areaName);
            await prefs.setString('selected_area_name', areaName);
          }
          if (addressNote != null && addressNote.isNotEmpty) await prefs.setString('address_note', addressNote);
        } catch (_) {}
        return {'success': true, ...data};
      } else {
        final errorMsg = data['error'] as String? ?? 'Failed to update area.';
        return {'success': false, 'error': errorMsg, ...data};
      }
    } catch (_) {
      return {'success': false, 'error': 'Network error. Please try again.'};
    }
  }

  Future<bool> confirmArea({
    String? areaId,
    String? addressNote,
  }) async {
    final res = await confirmAreaDetails(areaId: areaId, addressNote: addressNote);
    return res['success'] == true;
  }

  Future<Map<String, dynamic>?> fetchMe() async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return null;
      final url = Uri.parse('$baseUrl/auth/me');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> getAreaChangeRequestStatus() async {
    try {
      final token = await getAccessToken();
      final url = Uri.parse('$baseUrl/profile/area-change-request/status');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (_) {}
    return {'success': false, 'hasPending': false};
  }

  Future<Map<String, dynamic>> submitAreaChangeRequest({
    required String requestedAreaId,
    required String requestedAreaName,
    String? requestedCityId,
    String? reason,
  }) async {
    try {
      final token = await getAccessToken();
      final url = Uri.parse('$baseUrl/profile/area-change-request');
      final payload = <String, dynamic>{
        'requested_area_id': requestedAreaId,
        'requested_area_name': requestedAreaName,
        if (requestedCityId != null && requestedCityId.isNotEmpty) 'requested_city_id': requestedCityId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      };
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, ...data};
      } else {
        final errorMsg = data['error'] as String? ?? 'Failed to submit area change request.';
        return {'success': false, 'error': errorMsg, ...data};
      }
    } catch (_) {
      return {'success': false, 'error': 'Network error. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> cancelAreaChangeRequest({String? requestId}) async {
    try {
      final token = await getAccessToken();
      final url = Uri.parse('$baseUrl/profile/area-change-request/cancel');
      final payload = <String, dynamic>{
        if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
      };
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, ...data};
      } else {
        final errorMsg = data['error'] as String? ?? 'Failed to cancel request.';
        return {'success': false, 'error': errorMsg, ...data};
      }
    } catch (_) {
      return {'success': false, 'error': 'Network error. Please try again.'};
    }
  }
}



