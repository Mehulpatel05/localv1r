import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'post_repository.dart';
import 'auth_service.dart';

class R2StorageService {
  static const String backendUploadUrl = '${PostRepository.backendBaseUrl}/storage/upload';

  /// Helper to determine if a file is a video by its extension
  static bool isVideoFile(String path) {
    final ext = path.split('.').last.toLowerCase().split('?').first;
    return ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi', '3gp', 'flv', 'wmv'].contains(ext);
  }

  /// Upload single media (image or video) with automatic content type detection to Cloudflare R2 storage
  static Future<String?> uploadMedia(File file, {void Function(double)? onProgress}) async {
    try {
      if (!await file.exists()) {
        debugPrint('File does not exist: ${file.path}');
        return null;
      }

      final jwtToken = await AuthService.instance.getAccessToken();
      final user = FirebaseAuth.instance.currentUser;
      String? sessionToken = (jwtToken != null && jwtToken.isNotEmpty)
          ? jwtToken
          : (user != null ? await user.getIdToken() : null);

      final bytes = await file.readAsBytes();
      final pathExt = file.path.split('.').last.toLowerCase().split('?').first;

      String ext;
      MediaType contentType;

      // 1. Check Magic Bytes for Image types
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
      } else if (bytes.length > 3 &&
          bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
        ext = 'gif';
        contentType = MediaType('image', 'gif');
      }
      // 2. Check Video Types by Extension / Signatures
      else if (isVideoFile(file.path)) {
        ext = pathExt.isNotEmpty ? pathExt : 'mp4';
        if (ext == 'mov') {
          contentType = MediaType('video', 'quicktime');
        } else if (ext == 'webm') {
          contentType = MediaType('video', 'webm');
        } else if (ext == '3gp') {
          contentType = MediaType('video', '3gpp');
        } else {
          contentType = MediaType('video', 'mp4');
        }
      }
      // 3. Fallback Image types
      else if (['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'].contains(pathExt)) {
        ext = pathExt == 'jpeg' ? 'jpg' : pathExt;
        contentType = MediaType('image', pathExt == 'jpg' || pathExt == 'jpeg' ? 'jpeg' : pathExt);
      } else {
        ext = 'jpg';
        contentType = MediaType('image', 'jpeg');
      }

      final prefix = contentType.type == 'video' ? 'video' : 'image';
      final filename = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      if (onProgress != null) onProgress(0.3);

      Future<http.Response> sendUpload(String? token) async {
        final uri = Uri.parse(backendUploadUrl);
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
        final streamedResponse = await request.send();
        return await http.Response.fromStream(streamedResponse);
      }

      if (onProgress != null) onProgress(0.6);

      var response = await sendUpload(sessionToken);

      // Handle 401 Session Expired -> Refresh token & retry once
      if (response.statusCode == 401) {
        debugPrint('[R2StorageService] 401 received. Refreshing auth token...');
        final refreshedJwt = await AuthService.instance.refreshToken();
        if (refreshedJwt != null && refreshedJwt.isNotEmpty) {
          sessionToken = refreshedJwt;
        } else if (FirebaseAuth.instance.currentUser != null) {
          sessionToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
        }
        response = await sendUpload(sessionToken);
      }

      if (onProgress != null) onProgress(1.0);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final url = (data['imageUrl'] ?? data['url'] ?? data['mediaUrl'] ?? data['fileUrl']) as String?;
        return url;
      } else {
        debugPrint('Media upload failed (${response.statusCode}): ${response.body}');
      }
      return null;
    } catch (e) {
      debugPrint('Error uploading media: $e');
      return null;
    }
  }

  /// Backward-compatible alias for uploadMedia
  static Future<String?> uploadImage(File file, {void Function(double)? onProgress}) {
    return uploadMedia(file, onProgress: onProgress);
  }

  /// Upload multiple media files sequentially/in-batches with combined progress callback
  static Future<List<String>> uploadMultipleMedia(
    List<File> files, {
    void Function(double overallProgress)? onProgress,
  }) async {
    final List<String> results = [];
    if (files.isEmpty) return results;

    final total = files.length;
    for (int i = 0; i < total; i++) {
      final file = files[i];
      final url = await uploadMedia(
        file,
        onProgress: (p) {
          if (onProgress != null) {
            final overall = (i + p) / total;
            onProgress(overall);
          }
        },
      );
      if (url != null && url.isNotEmpty) {
        results.add(url);
      }
    }
    if (onProgress != null) onProgress(1.0);
    return results;
  }
}

/// Backward compatibility alias
typedef TelegramStorageService = R2StorageService;
