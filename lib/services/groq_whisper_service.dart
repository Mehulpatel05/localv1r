import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../core/constants/api_constants.dart';
import 'auth_service.dart';

class GroqVoicePostResult {
  final String text;
  final String? category;
  final String? language;

  const GroqVoicePostResult({
    required this.text,
    this.category,
    this.language,
  });
}

class GroqWhisperService {
  static final GroqWhisperService _instance = GroqWhisperService._internal();
  factory GroqWhisperService() => _instance;
  GroqWhisperService._internal();

  static GroqWhisperService get instance => _instance;

  Future<GroqVoicePostResult?> transcribeAudio(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      return null;
    }

    try {
      final backendResult = await _transcribeViaBackend(file);
      if (backendResult != null && backendResult.text.trim().isNotEmpty) {
        return backendResult;
      }
    } catch (_) {}

    return null;
  }

  Future<GroqVoicePostResult?> polishHinglishAndGrammar(String rawText) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/ai/polish');
      final token = await AuthService.instance.getAccessToken();

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'text': rawText}),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['text'] != null) {
          final text = (data['text'] as String).trim();
          if (text.isNotEmpty) {
            return GroqVoicePostResult(
              text: text,
              category: (data['category'] as String?)?.trim().toLowerCase(),
              language: (data['language'] as String?)?.trim().toLowerCase(),
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<GroqVoicePostResult?> _transcribeViaBackend(File file) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/ai/transcribe');
    final request = http.MultipartRequest('POST', uri);

    final token = await AuthService.instance.getAccessToken();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final multipartFile = await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: MediaType('audio', 'm4a'),
    );
    request.files.add(multipartFile);

    final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['text'] != null) {
        return GroqVoicePostResult(
          text: (data['text'] as String).trim(),
          category: data['category'] as String?,
          language: data['language'] as String?,
        );
      }
    }
    return null;
  }
}
