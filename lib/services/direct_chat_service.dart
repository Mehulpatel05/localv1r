import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_conversation_model.dart';
import 'auth_service.dart';

class DirectChatService {
  static final DirectChatService _instance = DirectChatService._internal();
  factory DirectChatService() => _instance;
  static DirectChatService get instance => _instance;
  DirectChatService._internal();

  /// Canonical pair helper
  static String getChatId(String user1, String user2) {
    final u1 = user1.replaceAll('@', '').trim().toLowerCase();
    final u2 = user2.replaceAll('@', '').trim().toLowerCase();
    final sorted = [u1, u2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Get direct chat list for a user from D1 REST API
  Future<List<ChatConversation>> getChats(String userHandle) async {
    final clean = userHandle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return [];

    try {
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/chats?handle=$clean'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body['chats'] as List<dynamic>? ?? [];
        return list.map((json) => ChatConversation.fromJson(json as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('[DirectChatService] Error getting chats: $e');
    }
    return [];
  }

  /// Periodic stream of user's direct chats
  Stream<List<ChatConversation>> pollChatsStream(String userHandle, {Duration interval = const Duration(seconds: 3)}) async* {
    while (true) {
      final chats = await getChats(userHandle);
      yield chats;
      await Future.delayed(interval);
    }
  }

  /// Get messages for a direct chat from D1 REST API
  Future<List<Map<String, dynamic>>> getMessages(
    String chatId, {
    int limit = 50,
    int? before,
  }) async {
    final cleanId = chatId.trim();
    if (cleanId.isEmpty) return [];

    try {
      var url = '${AuthService.baseUrl}/chats/$cleanId/messages?limit=$limit';
      if (before != null) {
        url += '&before=$before';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body['messages'] as List<dynamic>? ?? [];
        return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
    } catch (e) {
      debugPrint('[DirectChatService] Error getting messages: $e');
    }
    return [];
  }

  /// Periodic stream of messages for a direct chat
  Stream<List<Map<String, dynamic>>> pollMessagesStream(
    String chatId, {
    Duration interval = const Duration(seconds: 2),
    int limit = 50,
  }) async* {
    while (true) {
      final msgs = await getMessages(chatId, limit: limit);
      yield msgs;
      await Future.delayed(interval);
    }
  }

  /// Send a 1-on-1 direct message via D1 REST API
  Future<Map<String, dynamic>?> sendMessage({
    required String sender,
    required String receiver,
    required String content,
    String? imageUrl,
    List<String>? mediaUrls,
    String messageType = 'text',
  }) async {
    final cleanSender = sender.replaceAll('@', '').trim();
    final cleanReceiver = receiver.replaceAll('@', '').trim();

    try {
      final payload = {
        'sender': cleanSender,
        'receiver': cleanReceiver,
        'content': content,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (mediaUrls != null) 'mediaUrls': mediaUrls,
        'messageType': messageType,
      };

      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/chats/message'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[DirectChatService] Error sending direct message: $e');
    }
    return null;
  }

  /// Mark chat as read for this user in D1
  Future<bool> markChatRead(String chatId, String userHandle) async {
    final cleanUser = userHandle.replaceAll('@', '').trim();
    try {
      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/chats/$chatId/read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_handle': cleanUser}),
      ).timeout(const Duration(seconds: 6));

      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[DirectChatService] Error marking read: $e');
      return false;
    }
  }

  /// Delete a direct message in D1
  Future<bool> deleteMessage(String messageId, String userHandle) async {
    final cleanUser = userHandle.replaceAll('@', '').trim();
    try {
      final res = await http.delete(
        Uri.parse('${AuthService.baseUrl}/chats/message/$messageId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_handle': cleanUser}),
      ).timeout(const Duration(seconds: 6));

      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[DirectChatService] Error deleting message: $e');
      return false;
    }
  }
}
