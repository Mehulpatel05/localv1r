import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_conversation_model.dart';
import '../core/utils/api_error.dart';
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

  Future<int> prefetchUnreadSummary(String userHandle) async {
    final clean = userHandle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return 0;

    try {
      final token = await AuthService.instance.getAccessToken();
      final uri = Uri.parse('${AuthService.baseUrl}/actions/counters?handle=$clean');
      final res = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final counters = body['counters'] as Map<String, dynamic>? ?? {};
        final unread = (counters['unreadMessages'] as int?) ?? (counters['unreadChats'] as int?) ?? 0;
        unreadCountNotifier.value = unread;
        return unread;
      }

      final fallbackRes = await http.get(
        Uri.parse('${AuthService.baseUrl}/chats?handle=$clean'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 4));

      if (fallbackRes.statusCode == 200) {
        final body = jsonDecode(fallbackRes.body);
        final chats = (body['chats'] as List<dynamic>?) ?? [];
        int totalUnread = 0;
        for (final c in chats) {
          final unread = (c['unreadCount'] as num?)?.toInt() ?? 0;
          totalUnread += unread;
        }
        unreadCountNotifier.value = totalUnread;
        return totalUnread;
      }
    } catch (e) {
      debugPrint('[DirectChatService] prefetchUnreadSummary error: $e');
    }
    return unreadCountNotifier.value;
  }

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
        final seenPartners = <String>{};
        final deduped = <ChatConversation>[];
        for (final chat in loaded) {
          final partner = chat.getPartnerHandle(userHandle).replaceAll('@', '').trim().toLowerCase();
          if (partner.isNotEmpty && !seenPartners.contains(partner)) {
            seenPartners.add(partner);
            await _loadMessagesFromPrefs(chat.id, userHandle);
            final partnerChatId = getChatId(userHandle, partner);
            await _loadMessagesFromPrefs(partnerChatId, userHandle);
            final msgs = _lastKnownMessages[chat.id] ?? _lastKnownMessages[partnerChatId] ?? [];
            ChatConversation resolvedChat = chat;
            if (msgs.isNotEmpty) {
              final lastM = msgs.last;
              final mType = (lastM['type'] ?? lastM['messageType'] ?? '').toString().toLowerCase();
              final rawA = (lastM['audioUrl'] ?? lastM['mediaR2Path'] ?? lastM['imageUrl'] ?? '').toString();
              final isV = mType == 'voice_note' || mType == 'audio' || rawA.contains('voice_') || rawA.endsWith('.m4a') || rawA.endsWith('.aac') || rawA.endsWith('.mp3');
              if (isV) {
                resolvedChat = resolvedChat.copyWith(lastMessage: '🎤 Voice note', lastMessageType: 'voice_note');
              }
            } else if (resolvedChat.lastMessageType == 'voice_note' || resolvedChat.lastMessageType == 'audio' || resolvedChat.lastMessage.contains('voice_') || resolvedChat.lastMessage.endsWith('.m4a') || resolvedChat.lastMessage.endsWith('.aac') || resolvedChat.lastMessage.endsWith('.mp3')) {
              resolvedChat = resolvedChat.copyWith(lastMessage: '🎤 Voice note', lastMessageType: 'voice_note');
            }
            deduped.add(resolvedChat);
          }
        }
        _lastKnownChats = deduped;
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

  static String _getUserMessagesKey(String chatId, [String? userHandle]) {
    final clean = (userHandle ?? '').replaceAll('@', '').trim().toLowerCase();
    final userPart = clean.isNotEmpty ? '${clean}_' : '';
    return 'cache_dm_messages_$userPart$chatId';
  }

  Future<void> _loadMessagesFromPrefs(String chatId, [String? userHandle]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getUserMessagesKey(chatId, userHandle);
      final jsonStr = prefs.getString(key) ?? prefs.getString('cache_dm_messages_$chatId');
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

  Future<void> _saveMessagesToPrefs(String chatId, List<Map<String, dynamic>> messages, [String? userHandle]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = messages.take(50).toList();
      final key = _getUserMessagesKey(chatId, userHandle);
      await prefs.setString(key, jsonEncode(toSave));
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
        final seenPartners = <String>{};
        final deduped = <ChatConversation>[];
        for (final chat in parsed) {
          final partner = chat.getPartnerHandle(clean).replaceAll('@', '').trim().toLowerCase();
          if (partner.isNotEmpty && !seenPartners.contains(partner)) {
            seenPartners.add(partner);
            final partnerChatId = getChatId(clean, partner);
            if (!_lastKnownMessages.containsKey(chat.id) && !_lastKnownMessages.containsKey(partnerChatId)) {
              await _loadMessagesFromPrefs(chat.id, clean);
              await _loadMessagesFromPrefs(partnerChatId, clean);
            }
            final msgs = _lastKnownMessages[chat.id] ?? _lastKnownMessages[partnerChatId] ?? [];
            ChatConversation resolvedChat = chat;
            if (msgs.isNotEmpty) {
              final lastM = msgs.last;
              final mType = (lastM['type'] ?? lastM['messageType'] ?? '').toString().toLowerCase();
              final rawA = (lastM['audioUrl'] ?? lastM['mediaR2Path'] ?? lastM['imageUrl'] ?? '').toString();
              final isV = mType == 'voice_note' || mType == 'audio' || rawA.contains('voice_') || rawA.endsWith('.m4a') || rawA.endsWith('.aac') || rawA.endsWith('.mp3');
              if (isV) {
                resolvedChat = resolvedChat.copyWith(lastMessage: '🎤 Voice note', lastMessageType: 'voice_note');
              }
            } else if (resolvedChat.lastMessageType == 'voice_note' || resolvedChat.lastMessageType == 'audio' || resolvedChat.lastMessage.contains('voice_') || resolvedChat.lastMessage.endsWith('.m4a') || resolvedChat.lastMessage.endsWith('.aac') || resolvedChat.lastMessage.endsWith('.mp3')) {
              resolvedChat = resolvedChat.copyWith(lastMessage: '🎤 Voice note', lastMessageType: 'voice_note');
            }
            deduped.add(resolvedChat);
          }
        }
        _lastKnownChats = deduped;
        int totalUnread = 0;
        for (final chat in deduped) {
          totalUnread += chat.unreadCount;
        }
        unreadCountNotifier.value = totalUnread;
        await _saveChatsToPrefs(clean, deduped);
        return deduped;
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
      await _loadMessagesFromPrefs(cleanId, userHandle);
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
        _saveMessagesToPrefs(cleanId, parsed, userHandle);
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
    String? audioUrl,
    List<String>? mediaUrls,
    String messageType = 'text',
  }) async {
    final cleanSender = sender.replaceAll('@', '').trim();
    final cleanReceiver = receiver.replaceAll('@', '').trim();
    final isVoice = messageType == 'voice_note' || messageType == 'audio' || (audioUrl != null && audioUrl.isNotEmpty);
    final resolvedType = isVoice ? 'voice_note' : messageType;

    try {
      final token = await AuthService.instance.getAccessToken();
      final payload = <String, dynamic>{
        'sender': cleanSender,
        'receiver': cleanReceiver,
        'receiverHandle': cleanReceiver,
        'content': content,
        'text': content,
        'messageType': resolvedType,
      };
      if (audioUrl != null && audioUrl.isNotEmpty) {
        payload['audioUrl'] = audioUrl;
        payload['mediaR2Path'] = audioUrl;
      }
      if (imageUrl != null && imageUrl.isNotEmpty) {
        payload['imageUrl'] = imageUrl;
        if (payload['mediaR2Path'] == null) {
          payload['mediaR2Path'] = imageUrl;
        }
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
            'imageUrl': isVoice ? null : imageUrl,
            'audioUrl': audioUrl,
            'mediaR2Path': audioUrl ?? imageUrl,
            'mediaUrls': mediaUrls ?? [],
            'type': resolvedType,
            'messageType': resolvedType,
            'reactions': <String, dynamic>{},
            'isRead': false,
            'isEdited': false,
            'isDeleted': false,
            'deletedForEveryone': false,
            'createdAt': nowIso,
            'timestamp': nowIso,
          };

          final current = _lastKnownMessages[returnedChatId] ?? [];
          if (!current.any((m) => (m['id'] ?? m['messageId']) == messageId)) {
            current.add(localMessage);
            _lastKnownMessages[returnedChatId] = current;
            _saveMessagesToPrefs(returnedChatId, current, cleanSender);
          }

          final fallbackId = getChatId(cleanSender, cleanReceiver);
          if (fallbackId != returnedChatId) {
            final fbCurrent = _lastKnownMessages[fallbackId] ?? [];
            if (!fbCurrent.any((m) => (m['id'] ?? m['messageId']) == messageId)) {
              fbCurrent.add(localMessage);
              _lastKnownMessages[fallbackId] = fbCurrent;
              _saveMessagesToPrefs(fallbackId, fbCurrent, cleanSender);
            }
          }

          String lastMsgPreview = content.trim();
          if (lastMsgPreview.isEmpty) {
            if (isVoice) {
              lastMsgPreview = '🎤 Voice note';
            } else if (imageUrl != null && imageUrl.isNotEmpty) {
              lastMsgPreview = '📷 Photo';
            } else {
              lastMsgPreview = 'Drafted message';
            }
          }

          if (_lastKnownChats != null) {
            final updatedChats = <ChatConversation>[];
            bool foundChat = false;
            for (final c in _lastKnownChats!) {
              final partner = c.getPartnerHandle(cleanSender).replaceAll('@', '').trim().toLowerCase();
              if (partner == cleanReceiver.toLowerCase() || c.id == returnedChatId || c.id == fallbackId) {
                foundChat = true;
                updatedChats.add(c.copyWith(
                  lastMessage: lastMsgPreview,
                  lastMessageType: resolvedType,
                  updatedAt: DateTime.now(),
                ));
              } else {
                updatedChats.add(c);
              }
            }
            if (!foundChat) {
              updatedChats.insert(
                0,
                ChatConversation(
                  id: returnedChatId,
                  participants: [cleanSender, cleanReceiver],
                  partnerDisplayName: cleanReceiver,
                  partnerAvatarUrl: '',
                  lastMessage: lastMsgPreview,
                  lastMessageType: resolvedType,
                  updatedAt: DateTime.now(),
                  unreadCounts: const {},
                ),
              );
            }
            _lastKnownChats = updatedChats;
            _saveChatsToPrefs(cleanSender, updatedChats);
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
    final cleanId = chatId.replaceAll('@', '').trim().toLowerCase();

    if (_lastKnownChats != null) {
      final updatedList = <ChatConversation>[];
      for (final chat in _lastKnownChats!) {
        final matches = chat.id.toLowerCase() == cleanId ||
            chat.getPartnerHandle(cleanUser).replaceAll('@', '').trim().toLowerCase() == cleanId;
        if (matches) {
          updatedList.add(chat.copyWith(unreadCount: 0));
        } else {
          updatedList.add(chat);
        }
      }
      _lastKnownChats = updatedList;
      int totalUnread = 0;
      for (final c in updatedList) {
        totalUnread += c.unreadCount;
      }
      unreadCountNotifier.value = totalUnread;
      _saveChatsToPrefs(cleanUser, updatedList);
    }

    try {
      final token = await AuthService.instance.getAccessToken();
      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/chats/$cleanId/read?handle=$cleanUser'),
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
        dynamic body;
        try {
          body = jsonDecode(res.body);
        } catch (_) {}
        final detail = extractApiError(body, 'Edit window expired or forbidden');
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
        dynamic body;
        try {
          body = jsonDecode(res.body);
        } catch (_) {}
        final detail = extractApiError(body, 'Failed to delete message');
        throw Exception(detail);
      }
    } catch (e) {
      debugPrint('[DirectChatService] Error deleting message: $e');
      rethrow;
    }
  }
}
