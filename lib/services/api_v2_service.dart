import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// 🚀 Nearhood API V2 Service Bridge
/// Connects Flutter frontend to the new Cloudflare Workers + D1 + R2 backend
class ApiV2Service {
  static final ApiV2Service _instance = ApiV2Service._internal();
  factory ApiV2Service() => _instance;
  static ApiV2Service get instance => _instance;
  ApiV2Service._internal();

  /// V2 Base URL (Live Render Production Endpoint)
  static String baseUrl = 'https://backend-v2-cu1p.onrender.com/api/v2';

  Future<Map<String, String>> _getHeaders() async {
    final token = await AuthService.instance.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ===========================================================================
  // 1. 🗄️ PER-USER R2 MEDIA UPLOADS
  // ===========================================================================

  /// Uploads media directly to the user's isolated R2 folder:
  /// `users/@{handle}/{folder}/{subId}/{filename}`
  /// [folder] can be: 'profile', 'feed', 'bazar', 'bazar_shop', 'chat', 'audio'
  Future<String?> uploadUserMedia(
    File file, {
    required String folder,
    String? subId,
  }) async {
    try {
      final token = await AuthService.instance.getAccessToken();
      var uri = Uri.parse('$baseUrl/media/upload?folder=$folder');
      if (subId != null && subId.isNotEmpty) {
        uri = Uri.parse('$baseUrl/media/upload?folder=$folder&subId=$subId');
      }

      final request = http.MultipartRequest('POST', uri);
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Returns public URL or R2 path
          return data['publicUrl'] as String?;
        }
      }
    } catch (e) {
      debugPrint('[ApiV2Service] uploadUserMedia error: $e');
    }
    return null;
  }

  // ===========================================================================
  // 2. 🏪 BAZAR (D1 + R2)
  // ===========================================================================

  Future<List<Map<String, dynamic>>> getBazarListings({
    String? category,
    String? search,
    String? seller,
  }) async {
    try {
      final headers = await _getHeaders();
      var url = '$baseUrl/bazar/listings?';
      if (category != null && category != 'All') url += 'category=$category&';
      if (search != null && search.isNotEmpty) url += 'search=$search&';
      if (seller != null && seller.isNotEmpty) url += 'seller=$seller&';

      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['listings'] as List<dynamic>? ?? [];
        return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
    } catch (e) {
      debugPrint('[ApiV2Service] getBazarListings error: $e');
    }
    return [];
  }

  Future<bool> createBazarListing({
    required String title,
    required int price,
    required String description,
    required String category,
    required String condition,
    required String location,
    required List<String> imageUrls,
    String? shopId,
  }) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/bazar/listings'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'price': price,
          'description': description,
          'category': category,
          'condition': condition,
          'location': location,
          'imageUrls': imageUrls,
          if (shopId != null) 'shopId': shopId,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[ApiV2Service] createBazarListing error: $e');
    }
    return false;
  }

  // ===========================================================================
  // 3. 💬 1-ON-1 DIRECT CHATS (D1 + R2)
  // ===========================================================================

  Future<List<Map<String, dynamic>>> getChats() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/chats'), headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['chats'] as List<dynamic>? ?? [];
        return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
    } catch (e) {
      debugPrint('[ApiV2Service] getChats error: $e');
    }
    return [];
  }

  Future<bool> sendMessage({
    required String receiver,
    required String content,
    String? mediaR2Path,
    String messageType = 'text',
  }) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/chats/send'),
        headers: headers,
        body: jsonEncode({
          'receiver': receiver,
          'content': content,
          if (mediaR2Path != null) 'mediaR2Path': mediaR2Path,
          'messageType': messageType,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[ApiV2Service] sendMessage error: $e');
    }
    return false;
  }
}
