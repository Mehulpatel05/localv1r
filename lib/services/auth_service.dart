import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'avatar_cache_service.dart';

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

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final accessToken = body['access_token'] as String;
        final refreshToken = body['refresh_token'] as String;
        final user = body['user'] as Map<String, dynamic>? ?? {};
        final userId = user['userId'] as String? ?? '';
        final phone = user['phoneNumber'] as String? ?? '';
        final handle = user['handle'] as String? ?? '';
        final isNewUser = user['isNewUser'] == true || handle.isEmpty;
        final customFirebaseToken = body['firebase_custom_token'] as String?;

        // 1. Secure storage write
        await _secureStorage.write(key: _kAccessTokenKey, value: accessToken);
        await _secureStorage.write(key: _kRefreshTokenKey, value: refreshToken);
        await _secureStorage.write(key: _kUserIdKey, value: userId);
        await _secureStorage.write(key: _kPhoneKey, value: phone);
        if (handle.isNotEmpty) {
          await _secureStorage.write(key: _kHandleKey, value: handle);
        }

        // 2. SharedPreferences cache for instant synchronous state lookups
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('is_logged_in', 'true');
        await prefs.setString('user_id', userId);
        await prefs.setString('phone_number', phone);
        if (handle.isNotEmpty) {
          await prefs.setString('user_handle', handle);
        }

        // 3. Connect to Firebase Auth via Custom Token if available
        if (customFirebaseToken != null && customFirebaseToken.isNotEmpty) {
          try {
            await FirebaseAuth.instance.signInWithCustomToken(customFirebaseToken);
          } catch (e) {
            debugPrint('[AuthService] Firebase custom token login note: $e');
          }
        }

        return {
          'success': true,
          'userId': userId,
          'phone': phone,
          'handle': handle,
          'isNewUser': isNewUser,
        };
      } else {
        final errorMsg = body['error']?['message'] ?? body['detail'] ?? 'Verification failed.';
        return {
          'success': false,
          'error': errorMsg,
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network connection error during verification.',
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

  Future<void> saveUserHandle(String handle, {String? userId, String? phone}) async {
    await _secureStorage.write(key: _kHandleKey, value: handle);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_handle', handle);
    await prefs.setString('is_logged_in', 'true');

    // Sync to Firestore users and profiles collections for multi-device cross-login
    try {
      final effectiveUid = userId ?? await getUserId() ?? FirebaseAuth.instance.currentUser?.uid;
      final effectivePhone = phone ?? await getPhoneNumber();

      if (effectiveUid != null && effectiveUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(effectiveUid).set({
          'handle': handle,
          'userId': effectiveUid,
          if (effectivePhone != null && effectivePhone.isNotEmpty) 'phoneNumber': effectivePhone,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final clean = handle.replaceAll('@', '').trim();
      if (clean.isNotEmpty) {
        await FirebaseFirestore.instance.collection('profiles').doc(clean).set({
          'handle': clean,
          if (effectiveUid != null && effectiveUid.isNotEmpty) 'ownerUid': effectiveUid,
          if (effectivePhone != null && effectivePhone.isNotEmpty) 'phoneNumber': effectivePhone,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[AuthService] Firestore handle sync note: $e');
    }
  }

  /// Restores user profile, handle, and avatar from cloud for seamless multi-device login
  Future<Map<String, dynamic>?> syncCloudProfile() async {
    try {
      final userId = await getUserId() ?? FirebaseAuth.instance.currentUser?.uid;
      final phone = await getPhoneNumber();

      String? resolvedHandle;
      String? resolvedPhoto;

      if (userId != null && userId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null) {
            final h = data['handle'] ?? data['userHandle'];
            if (h != null && h.toString().trim().isNotEmpty) {
              resolvedHandle = h.toString().trim();
            }
            resolvedPhoto = data['photoUrl']?.toString();
          }
        }
      }

      if ((resolvedHandle == null || resolvedHandle.isEmpty) && phone != null && phone.isNotEmpty) {
        final q = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: phone)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final data = q.docs.first.data();
          final h = data['handle'] ?? data['userHandle'];
          if (h != null && h.toString().trim().isNotEmpty) {
            resolvedHandle = h.toString().trim();
          }
          resolvedPhoto = data['photoUrl']?.toString();
        }
      }

      if (resolvedHandle != null && resolvedHandle.isNotEmpty) {
        await saveUserHandle(resolvedHandle, userId: userId, phone: phone);
        if (resolvedPhoto != null && resolvedPhoto.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('profile_photo_url', resolvedPhoto);
        }
        return {
          'handle': resolvedHandle,
          'photoUrl': resolvedPhoto,
        };
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

  /// Delete Account permanently via Backend Admin SDK
  Future<Map<String, dynamic>> deleteAccount() async {
    String? token = await getAccessToken();
    token ??= await refreshToken();
    if (token == null) {
      try {
        token = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }

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

  Future<void> updateUserProfileImage(String photoUrl) async {
    final user = FirebaseAuth.instance.currentUser;
    final handle = await getUserHandle();
    final uid = user?.uid ?? await getUserId();

    // 1. Firebase Auth photoURL
    if (user != null) {
      try {
        await user.updatePhotoURL(photoUrl);
      } catch (e) {
        debugPrint('[AuthService] Update Firebase photoURL warning: $e');
      }
    }

    // 2. Firestore users/{uid}
    if (uid != null && uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'photoUrl': photoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[AuthService] Update users photoUrl warning: $e');
      }
    }

    // 3. Firestore profiles/{handle}
    if (handle != null && handle.isNotEmpty) {
      final clean = handle.replaceAll('@', '').trim().toLowerCase();
      try {
        await FirebaseFirestore.instance.collection('profiles').doc(clean).set({
          'photoUrl': photoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[AuthService] Update profiles photoUrl warning: $e');
      }
      AvatarCacheService.instance.setCachedUrl(clean, photoUrl);
    }

    // 4. Local storage
    await AvatarCacheService.instance.saveMyPhotoUrlLocally(photoUrl);
  }

  Future<void> removeUserProfileImage() async {
    final user = FirebaseAuth.instance.currentUser;
    final handle = await getUserHandle();
    final uid = user?.uid ?? await getUserId();

    // 1. Firebase Auth
    if (user != null) {
      try {
        await user.updatePhotoURL(null);
      } catch (e) {
        debugPrint('[AuthService] Clear Firebase photoURL warning: $e');
      }
    }

    // 2. Firestore users/{uid}
    if (uid != null && uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'photoUrl': FieldValue.delete(),
        });
      } catch (e) {
        debugPrint('[AuthService] Delete users photoUrl warning: $e');
      }
    }

    // 3. Firestore profiles/{handle}
    if (handle != null && handle.isNotEmpty) {
      final clean = handle.replaceAll('@', '').trim().toLowerCase();
      try {
        await FirebaseFirestore.instance.collection('profiles').doc(clean).update({
          'photoUrl': FieldValue.delete(),
        });
      } catch (e) {
        debugPrint('[AuthService] Delete profiles photoUrl warning: $e');
      }
      AvatarCacheService.instance.setCachedUrl(clean, null);
    }

    // 4. Local storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_photo_url');
  }

  /// Complete Sign Out
  Future<void> signOut() async {
    try {
      await _secureStorage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('[AuthService] Sign out error: $e');
    }
  }
}
