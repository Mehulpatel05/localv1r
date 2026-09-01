import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'post_repository.dart';

class TelegramStorageService {
  // ⚠️ CONFIGURATION: Points to the secure FastAPI backend proxy
  static const String backendUploadUrl = '${PostRepository.backendBaseUrl}/storage/upload';

  /// Uploads a local image file to the Backend Proxy and returns the public CDN URL
  /// 🛡️ Zero client-side tokens are used, preventing API key exposure.
  static Future<String?> uploadImage(File file, {void Function(double)? onProgress}) async {
    try {
      const storage = FlutterSecureStorage();
      final sessionToken = await storage.read(key: 'session_token') ?? '';
      
      final uri = Uri.parse(backendUploadUrl);
      final request = http.MultipartRequest('POST', uri)
        ..headers['authorization'] = 'Bearer $sessionToken';

      final length = await file.length();
      int bytesUploaded = 0;

      final stream = http.ByteStream(file.openRead().map((chunk) {
        bytesUploaded += chunk.length;
        if (onProgress != null) {
          onProgress(bytesUploaded / length);
        }
        return chunk;
      }));

      request.files.add(http.MultipartFile('file', stream, length, filename: file.path.split(Platform.pathSeparator).last));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['imageUrl'] as String?;
      } else {
        debugPrint('Image upload backend failed: ${response.body}');
      }
      return null;
    } catch (e) {
      debugPrint('Error uploading image to backend proxy: $e');
      return null;
    }
  }
}
