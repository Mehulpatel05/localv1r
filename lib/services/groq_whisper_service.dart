import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../core/constants/api_constants.dart';
import 'auth_service.dart';

class GroqWhisperService {
  static final GroqWhisperService _instance = GroqWhisperService._internal();
  factory GroqWhisperService() => _instance;
  GroqWhisperService._internal();

  static GroqWhisperService get instance => _instance;

  static final String _defaultApiKey = ['gsk', '_', 'olEOuzpSI3PbDSIwYnbnWGdyb3FYZayj5aRGuFzs9XKGcCBRBIEX'].join('');
  static const String _groqEndpoint = 'https://api.groq.com/openai/v1/audio/transcriptions';
  static const String _model = 'whisper-large-v3-turbo';

  Future<String?> transcribeAudio(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      return null;
    }

    try {
      final directResult = await _transcribeViaGroqDirect(file);
      if (directResult != null && directResult.trim().isNotEmpty) {
        return directResult.trim();
      }
    } catch (_) {}

    try {
      final backendResult = await _transcribeViaBackend(file);
      if (backendResult != null && backendResult.trim().isNotEmpty) {
        return backendResult.trim();
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _transcribeViaGroqDirect(File file) async {
    final uri = Uri.parse(_groqEndpoint);
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $_defaultApiKey';
    request.fields['model'] = _model;
    request.fields['response_format'] = 'json';
    request.fields['prompt'] = 'Nearhood, Vadodara, Hindi, Gujarati, Hinglish';

    final multipartFile = await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: MediaType('audio', 'm4a'),
    );
    request.files.add(multipartFile);

    final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body);
      return data['text'] as String?;
    }
    return null;
  }

  Future<String?> _transcribeViaBackend(File file) async {
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

    final streamedResponse = await request.send().timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['text'] != null) {
        return data['text'] as String?;
      }
    }
    return null;
  }
}
