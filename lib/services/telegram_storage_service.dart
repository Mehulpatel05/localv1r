import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'post_repository.dart';

class TelegramStorageService {
  // ⚠️ CONFIGURATION: Points to the secure FastAPI backend proxy
  static const String backendUploadUrl = '${PostRepository.backendBaseUrl}/storage/upload';

  /// Uploads a local image file to the Backend Proxy and returns the public CDN URL
  /// 🛡️ Zero client-side tokens are used, preventing API key exposure.
  static Future<String?> uploadImage(File file, {void Function(double)? onProgress}) async {
    try {
      if (!await file.exists()) {
        debugPrint('File does not exist: ${file.path}');
        return null;
      }

      final user = FirebaseAuth.instance.currentUser;
      final sessionToken = user != null ? await user.getIdToken() : '';
      
      final uri = Uri.parse(backendUploadUrl);
      final request = http.MultipartRequest('POST', uri);

      if (sessionToken != null && sessionToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $sessionToken';
      }

      final ext = file.path.split('.').last.toLowerCase();
      MediaType contentType;
      if (ext == 'png') {
        contentType = MediaType('image', 'png');
      } else if (ext == 'webp') {
        contentType = MediaType('image', 'webp');
      } else if (ext == 'gif') {
        contentType = MediaType('image', 'gif');
      } else {
        contentType = MediaType('image', 'jpeg');
      }

      final bytes = await file.readAsBytes();
      final filename = 'image_${DateTime.now().millisecondsSinceEpoch}.$ext';

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: contentType,
        ),
      );

      if (onProgress != null) {
        onProgress(0.5);
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (onProgress != null) {
        onProgress(1.0);
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['imageUrl'] as String?;
      } else {
        debugPrint('Image upload backend failed (${response.statusCode}): ${response.body}');
      }
      return null;
    } catch (e) {
      debugPrint('Error uploading image to backend proxy: $e');
      return null;
    }
  }
}
