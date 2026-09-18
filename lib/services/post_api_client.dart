import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';

class PostApiClient {
  static const String backendBaseUrl = 'https://localv1r.onrender.com/api/v1';

  Future<Map<String, String>> getAuthHeaders() async {
    final token = await AuthService.instance.getAccessToken();
    final user = FirebaseAuth.instance.currentUser;
    final fallbackToken = user != null ? await user.getIdToken() : '';
    final finalToken = (token != null && token.isNotEmpty) ? token : fallbackToken;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $finalToken',
    };
  }

  Future<void> votePost(String postId, int direction) async {
    final headers = await getAuthHeaders();
    final response = await http.post(
      Uri.parse('$backendBaseUrl/posts/$postId/vote'),
      headers: headers,
      body: jsonEncode({'direction': direction}),
    );
    if (response.statusCode != 200) {
      throw Exception('Vote failed');
    }
  }
}
