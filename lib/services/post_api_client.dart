import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post_model.dart';
import '../core/constants/areas_and_categories.dart';

class PostApiClient {
  static const String backendBaseUrl = 'https://localv1r.onrender.com/api/v1';

  Future<Map<String, String>> getAuthHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = user != null ? await user.getIdToken() : '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
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
