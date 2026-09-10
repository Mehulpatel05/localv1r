import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'post_repository.dart';

class TelegramStorageService {
  static const String backendUploadUrl = '${PostRepository.backendBaseUrl}/storage/upload';

  static Future<String?> uploadImage(File file, {void Function(double)? onProgress}) async {
    try {
      if (!await file.exists()) {
        debugPrint('File does not exist: ${file.path}');
        return null;
      }

      final user = FirebaseAuth.instance.currentUser;
      final sessionToken = user != null ? await user.getIdToken() : null;

      // Read bytes first — detect format from magic bytes (not file extension)
      final bytes = await file.readAsBytes();

      // Detect real image format from magic bytes
      String ext;
      MediaType contentType;
      if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        ext = 'jpg';
        contentType = MediaType('image', 'jpeg');
      } else if (bytes.length > 8 &&
          bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        ext = 'png';
        contentType = MediaType('image', 'png');
      } else if (bytes.length > 11 &&
          bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
          bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
        ext = 'webp';
        contentType = MediaType('image', 'webp');
      } else {
        final pathExt = file.path.split('.').last.toLowerCase();
        if (['jpg', 'jpeg', 'png', 'webp'].contains(pathExt)) {
          ext = pathExt == 'jpeg' ? 'jpg' : pathExt;
          contentType = MediaType('image', pathExt == 'jpg' || pathExt == 'jpeg' ? 'jpeg' : pathExt);
        } else {
          ext = 'jpg';
          contentType = MediaType('image', 'jpeg');
        }
      }

      final filename = 'image_${DateTime.now().millisecondsSinceEpoch}.$ext';

      if (onProgress != null) onProgress(0.3);

      final uri = Uri.parse(backendUploadUrl);
      final request = http.MultipartRequest('POST', uri);
      if (sessionToken != null && sessionToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $sessionToken';
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: contentType,
        ),
      );

      if (onProgress != null) onProgress(0.6);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (onProgress != null) onProgress(1.0);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['imageUrl'] as String?;
      } else {
        debugPrint('Image upload failed (${response.statusCode}): ${response.body}');
      }
      return null;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }
}
