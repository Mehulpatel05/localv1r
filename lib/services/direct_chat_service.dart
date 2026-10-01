import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

  final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);

  /// ⚡ Phase 2: Stage B Pre-fetch Unread DM Counters (0ms UI Badge warmup)
  Future<int> prefetchUnreadSummary(String userHandle) async {
    final clean = userHandle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return 0;

    try {
      final token = await AuthService.instance.getAccessToken();
      final uri = Uri.parse('${AuthService.baseUrl}/actions/counters');
      final res = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final counters = body['counters'] as Map<String, dynamic>? ?? {};
        final unread = (counters['unreadMessages'] as int?) ?? 0;
        unreadCountNotifier.value = unread;
        return unread;
      }
    } catch (e) {
      debugPrint('[DirectChatService] prefetchUnreadSummary error: $e');
    }
    return unreadCountNotifier.value;
  }

  static const String _kDirectMessagesPrefix = 'cache_dm_messages_';

  static String _getUserChatsKey(String userHandle) {
    final clean = userHandle.replaceAll('@', '').trim().toLowerCase();
    return clean.isNotEmpty ? 'cache_direct_chats_$clean' : 'cache_direct_chats_default';
  }

  List<ChatConversation>? _lastKnownChats;
  final Map<String, List<Map<String, dynamic>>> _lastKnownMessages = {};

  List<ChatConversation>? get lastKnownChats => _lastKnownChats;

  List<Map<String, dynamic>> getLastKnownMessages(String chatId) {
    final cleanId = chatId.trim();
    return _lastKnownMessages[cleanId] ?? [];
  }

  Future<void> _loadChatsFromPrefs(String userHandle) async {
    try {
      final key = _getUserChatsKey(userHandle);
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        final loaded = list
            .map((item) => ChatConversation.fromJson(item as Map<String, dynamic>))
            .toList();
        _lastKnownChats = loaded;
      } else {
        _lastKnownChats = [];
      }
    } catch (e) {
      debugPrint('[DirectChatService] _loadChatsFromPrefs error: $e');
    }
  }

  Future<void> _saveChatsToPrefs(String userHandle, List<ChatConversation> chats) async {
    try {
      final key = _getUserChatsKey(userHandle);
      final prefs = await SharedPreferences.getInstance();
      final jsonList = chats.map((c) => c.toJson()).toList();
      await prefs.setString(key, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[DirectChatService] _saveChatsToPrefs error: $e');
    }
  }

  Future<void> _loadMessagesFromPrefs(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('$_kDirectMessagesPrefix$chatId');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        final loaded = list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        if (loaded.isNotEmpty) {
          _lastKnownMessages[chatId] = loaded;
        }
      }
    } catch (e) {
      debugPrint('[DirectChatService] _loadMessagesFromPrefs error: $e');
    }
  }

  Future<void> _saveMessagesToPrefs(String chatId, List<Map<String, dynamic>> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = messages.take(40).toList();
      await prefs.setString('$_kDirectMessagesPrefix$chatId', jsonEncode(toSave));
    } catch (e) {
      debugPrint('[DirectChatService] _saveMessagesToPrefs error: $e');
    }
  }

  void clearCache() {
    _lastKnownChats = null;
    _lastKnownMessages.clear();
    unreadCountNotifier.value = 0;
  }

  /// Get direct chat list for a user from D1 REST API
  Future<List<ChatConversation>> getChats(String userHandle) async {
    final clean = userHandle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return _lastKnownChats ?? [];

    await _loadChatsFromPrefs(clean);

    try {
      final token = await AuthService.instance.getAccessToken();
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/chats?handle=$clean'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },

      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body['chats'] as List<dynamic>? ?? [];
        final parsed = list.map((json) => ChatConversation.fromJson(json as Map<String, dynamic>)).toList();
        _lastKnownChats = parsed;
        await _saveChatsToPrefs(clean, parsed);
        return parsed;
      }
    } catch (e) {
      debugPrint('[DirectChatService] Error getting chats: $e');
    }
    return _lastKnownChats ?? [];
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
    String? userHandle,
  }) async {
    final cleanId = chatId.trim();
    if (cleanId.isEmpty) return [];

    if (!_lastKnownMessages.containsKey(cleanId) || _lastKnownMessages[cleanId]!.isEmpty) {
      await _loadMessagesFromPrefs(cleanId);
    }

    try {
      final token = await AuthService.instance.getAccessToken();
      var url = '${AuthService.baseUrl}/chats/$cleanId/messages?limit=$limit';
      if (before != null) {
        url += '&before=$before';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body['messages'] as List<dynamic>? ?? [];
        final parsed = list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        _lastKnownMessages[cleanId] = parsed;
        _saveMessagesToPrefs(cleanId, parsed);
        return parsed;
      }
    } catch (e) {
      debugPrint('[DirectChatService] Error getting messages: $e');
    }
    return _lastKnownMessages[cleanId] ?? [];
  }

  /// Periodic stream of messages for a direct chat
  Stream<List<Map<String, dynamic>>> pollMessagesStream(
    String chatId, {
    Duration interval = const Duration(seconds: 2),
    int limit = 50,
    String? userHandle,
  }) async* {
    while (true) {
      final msgs = await getMessages(chatId, limit: limit, userHandle: userHandle);
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
      final token = await AuthService.instance.getAccessToken();
      final payload = <String, dynamic>{
        'sender': cleanSender,
        'receiver': cleanReceiver,
        'receiverHandle': cleanReceiver,
        'content': content,
        'text': content,
        'messageType': messageType,
      };
      if (imageUrl != null && imageUrl.isNotEmpty) {
        payload['imageUrl'] = imageUrl;
        payload['mediaR2Path'] = imageUrl;
      }
      if (mediaUrls != null && mediaUrls.isNotEmpty) {
        payload['mediaUrls'] = mediaUrls;
      }

      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/chats/send'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final messageId = body['messageId'] as String?;
        final returnedChatId = (body['chatId'] as String?) ?? getChatId(cleanSender, cleanReceiver);

        if (messageId != null && messageId.isNotEmpty) {
          final nowIso = DateTime.now().toUtc().toIso8601String();
          final localMessage = <String, dynamic>{
            'id': messageId,
            'messageId': messageId,
            'chatId': returnedChatId,
            'senderHandle': cleanSender,
            'receiverHandle': cleanReceiver,
            'content': content,
            'imageUrl': imageUrl,
            'mediaUrls': mediaUrls ?? [],
            'type': messageType,
            'messageType': messageType,
            'reactions': <String, dynamic>{},
            'isRead': false,
            'isEdited': false,
            'isDeleted': false,
            'deletedForEveryone': false,
            'createdAt': nowIso,
            'timestamp': nowIso,
          };

          // Seamlessly append to in-memory and disk cache
          final current = _lastKnownMessages[returnedChatId] ?? [];
          if (!current.any((m) => (m['id'] ?? m['messageId']) == messageId)) {
            current.add(localMessage);
            _lastKnownMessages[returnedChatId] = current;
            _saveMessagesToPrefs(returnedChatId, current);
          }
        }
        return body;
      } else {
        debugPrint('[DirectChatService] Send message failed (${res.statusCode}): ${res.body}');
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
      final token = await AuthService.instance.getAccessToken();
      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/chats/$chatId/read'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'user_handle': cleanUser}),
      ).timeout(const Duration(seconds: 6));


      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[DirectChatService] Error marking read: $e');
    }
    return false;
  }

  /// Fetch all conversation IDs matching active query/filter from backend query
  Future<List<String>> getChatIds({required String userHandle, String? query}) async {
    final clean = userHandle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return [];

    try {
      final token = await AuthService.instance.getAccessToken();
      var url = '${AuthService.baseUrl}/chats/ids?handle=$clean';
      if (query != null && query.trim().isNotEmpty) {
        url += '&query=${Uri.encodeComponent(query.trim())}';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body['chatIds'] as List<dynamic>? ?? [];
        return list.map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('[DirectChatService] Error getting chat IDs: $e');
    }
    return [];
  }

  /// Edit a direct message with 15-minute server validated hard limit
  Future<Map<String, dynamic>?> editMessage({
    required String messageId,
    required String userHandle,
    required String newContent,
  }) async {
    final cleanUser = userHandle.replaceAll('@', '').trim();
    try {
      final token = await AuthService.instance.getAccessToken();
      final res = await http.put(
        Uri.parse('${AuthService.baseUrl}/chats/message/$messageId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_handle': cleanUser,
          'content': newContent.trim(),
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        final body = jsonDecode(res.body);
        final detail = body['detail'] ?? 'Edit window expired or forbidden';
        debugPrint('[DirectChatService] Edit message failed: $detail');
        throw Exception(detail);
      }
    } catch (e) {
      debugPrint('[DirectChatService] Error editing message: $e');
      rethrow;
    }
  }

  /// Delete a direct message in D1 (Supports forEveryone with 48hr hard limit or forMe)
  Future<bool> deleteMessage(
    String messageId,
    String userHandle, {
    bool forEveryone = false,
  }) async {
    final cleanUser = userHandle.replaceAll('@', '').trim();
    try {
      final token = await AuthService.instance.getAccessToken();
      final req = http.Request('DELETE', Uri.parse('${AuthService.baseUrl}/chats/message/$messageId'));
      req.headers['Content-Type'] = 'application/json';
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      req.body = jsonEncode({
        'user_handle': cleanUser,
        'for_everyone': forEveryone,
      });

      final streamedRes = await req.send().timeout(const Duration(seconds: 6));
      final res = await http.Response.fromStream(streamedRes);

      if (res.statusCode == 200) {
        return true;
      } else {
        final body = jsonDecode(res.body);
        final detail = body['detail'] ?? 'Failed to delete message';
        throw Exception(detail);
      }
    } catch (e) {
      debugPrint('[DirectChatService] Error deleting message: $e');
      rethrow;
    }
  }
}
