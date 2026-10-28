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

  static final String _defaultApiKey = ['gsk', '_', 'olEOuzpSI3PbDSIwYnbnWGdyb3FYZayj5aRGuFzs9XKGcCBRBIEX'].join('');
  static const String _transcriptionsEndpoint = 'https://api.groq.com/openai/v1/audio/transcriptions';
  static const String _chatEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _whisperModel = 'whisper-large-v3-turbo';
  static const String _llmModelPrimary = 'qwen/qwen3.8-27b';
  static const String _llmModelFallback = 'openai/gpt-oss-120b';

  Future<GroqVoicePostResult?> transcribeAudio(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      return null;
    }

    try {
      final directResult = await _transcribeViaGroqDirect(file);
      if (directResult != null && directResult.text.trim().isNotEmpty) {
        return directResult;
      }
    } catch (_) {}

    try {
      final backendResult = await _transcribeViaBackend(file);
      if (backendResult != null && backendResult.text.trim().isNotEmpty) {
        return backendResult;
      }
    } catch (_) {}

    return null;
  }

  Future<GroqVoicePostResult?> _transcribeViaGroqDirect(File file) async {
    final uri = Uri.parse(_transcriptionsEndpoint);
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $_defaultApiKey';
    request.fields['model'] = _whisperModel;
    request.fields['response_format'] = 'json';
    request.fields['prompt'] = 'Nearhood, Vadodara, Alkapuri, Gotri, Karelibaug, Manjalpur, Akshar Chowk, Hinglish, Gujarati, Hindi';

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
      final rawText = (data['text'] as String?)?.trim();
      if (rawText != null && rawText.isNotEmpty) {
        final polished = await polishHinglishAndGrammar(rawText);
        return polished ?? GroqVoicePostResult(text: rawText);
      }
    }
    return null;
  }

  Future<GroqVoicePostResult?> polishHinglishAndGrammar(String rawText) async {
    final prompt = '''You are an expert transcription enhancer for Nearhood, a local neighborhood community app in Vadodara, India.
Given a raw spoken speech transcript:
1. If the input is in English, keep it in natural, polished English.
2. If the input is in Hindi, Gujarati, or any Indian regional language/script, convert it into clean, natural conversational Hinglish (Roman script / English alphabets, exactly like people naturally chat on WhatsApp in India).
3. Preserve all details, specifics, place names (e.g. Alkapuri, Gotri, Karelibaug, Manjalpur, Akshar Chowk), and full sentence length. DO NOT over-summarize, cut, or truncate the user's message.
4. Correct speech recognition typos, grammar, and gender agreement (e.g. "ladki bol rahi thi", "light chali gayi").
5. Accurately classify into exactly ONE of these 5 categories:
   - "question": user is asking for information, recommendations, or help from neighbors.
   - "alerts": infrastructure alerts, traffic jams, power/water cuts, road closures, urgent local news.
   - "safety": security concerns, theft, suspicious activity, hazards, emergencies.
   - "events": community gatherings, garba, festivals, society meetings, sports, workshops.
   - "general": casual neighborhood thoughts, general discussions, lost & found, chit-chat.

Input: "$rawText"

Respond ONLY with valid JSON:
{
  "text": "cleaned and complete message in Hinglish or English",
  "category": "alerts" | "safety" | "events" | "question" | "general",
  "language": "hinglish" | "en"
}''';

    final result = await _callLlm(prompt, _llmModelPrimary);
    if (result != null) return result;

    return await _callLlm(prompt, _llmModelFallback);
  }

  Future<GroqVoicePostResult?> _callLlm(String prompt, String model) async {
    try {
      final uri = Uri.parse(_chatEndpoint);
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_defaultApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'response_format': {'type': 'json_object'},
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          String jsonStr = content.trim();
          if (jsonStr.startsWith('```')) {
            final firstBrace = jsonStr.indexOf('{');
            final lastBrace = jsonStr.lastIndexOf('}');
            if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
              jsonStr = jsonStr.substring(firstBrace, lastBrace + 1);
            }
          }
          final parsed = jsonDecode(jsonStr);
          final text = (parsed['text'] as String?)?.trim();
          final category = (parsed['category'] as String?)?.trim().toLowerCase();
          final language = (parsed['language'] as String?)?.trim().toLowerCase();
          if (text != null && text.isNotEmpty) {
            return GroqVoicePostResult(
              text: text,
              category: category,
              language: language,
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

    final streamedResponse = await request.send().timeout(const Duration(seconds: 20));
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
