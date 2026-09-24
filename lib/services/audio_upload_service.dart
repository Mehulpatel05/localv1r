import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'post_repository.dart';

class AudioUploadService {
  static const String _backendUploadUrl =
      '${PostRepository.backendBaseUrl}/storage/upload';

  /// Uploads a voice note file (.m4a / .aac) and returns the public URL.
  /// Returns null on failure.
  static Future<String?> uploadVoiceNote(File file) async {
    try {
      if (!await file.exists()) {
        debugPrint('[AudioUploadService] File does not exist: ${file.path}');
        return null;
      }

      final jwtToken = await AuthService.instance.getAccessToken();
      final user = FirebaseAuth.instance.currentUser;
      String? sessionToken =
          (jwtToken != null && jwtToken.isNotEmpty)
              ? jwtToken
              : (user != null ? await user.getIdToken() : null);

      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();
      final mimeSubtype = ext == 'm4a' ? 'mp4' : (ext == 'aac' ? 'aac' : 'mp4');
      final contentType = MediaType('audio', mimeSubtype);
      final filename = 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext';

      Future<http.Response> sendUpload(String? token) async {
        final uri = Uri.parse(_backendUploadUrl);
        final request = http.MultipartRequest('POST', uri);
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: filename,
            contentType: contentType,
          ),
        );
        final streamed = await request.send();
        return await http.Response.fromStream(streamed);
      }

      var response = await sendUpload(sessionToken);

      // 401 → refresh token and retry once
      if (response.statusCode == 401) {
        debugPrint('[AudioUploadService] 401 received. Refreshing token...');
        final refreshed = await AuthService.instance.refreshToken();
        if (refreshed != null && refreshed.isNotEmpty) {
          sessionToken = refreshed;
        } else if (FirebaseAuth.instance.currentUser != null) {
          sessionToken =
              await FirebaseAuth.instance.currentUser?.getIdToken(true);
        }
        response = await sendUpload(sessionToken);
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Backend returns 'imageUrl' key for all uploads
        return (data['imageUrl'] ?? data['url'] ?? data['audioUrl']) as String?;
      } else {
        debugPrint(
          '[AudioUploadService] Upload failed (${response.statusCode}): ${response.body}',
        );
      }
      return null;
    } catch (e) {
      debugPrint('[AudioUploadService] Error: $e');
      return null;
    }
  }
}
