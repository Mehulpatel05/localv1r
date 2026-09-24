import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// Pure logic helpers for mixed-selection rules and limit calculations
class ChatSelectionLogic {
  /// Default action = apply to majority/not yet applied state.
  /// If ANY selected chat is NOT pinned -> return true (Action: "Pin").
  /// Only if ALL are pinned -> return false (Action: "Unpin").
  static bool shouldPin({
    required Set<String> selectedIds,
    required Set<String> pinnedIds,
  }) {
    if (selectedIds.isEmpty) return false;
    return selectedIds.any((id) => !pinnedIds.contains(id));
  }

  /// If ANY selected chat is NOT muted -> return true (Action: "Mute").
  /// Only if ALL are muted -> return false (Action: "Unmute").
  static bool shouldMute({
    required Set<String> selectedIds,
    required Map<String, int?> mutedExpiries,
    DateTime? now,
  }) {
    if (selectedIds.isEmpty) return false;
    return selectedIds.any((id) => !isChatMuted(mutedExpiries, id, now: now));
  }

  /// If ANY selected chat is NOT archived -> return true (Action: "Archive").
  /// Only if ALL are archived -> return false (Action: "Unarchive").
  static bool shouldArchive({
    required Set<String> selectedIds,
    required Set<String> archivedIds,
  }) {
    if (selectedIds.isEmpty) return false;
    return selectedIds.any((id) => !archivedIds.contains(id));
  }

  /// Calculates new archived set when applying Archive action to selection.
  /// Already-archived chats are skipped/no-op.
  static Set<String> archiveSelected({
    required Set<String> currentArchivedIds,
    required Set<String> selectedIds,
  }) {
    return {...currentArchivedIds, ...selectedIds};
  }

  /// Calculates new archived set when applying Unarchive action to selection.
  static Set<String> unarchiveSelected({
    required Set<String> currentArchivedIds,
    required Set<String> selectedIds,
  }) {
    return currentArchivedIds.where((id) => !selectedIds.contains(id)).toSet();
  }

  /// Evaluates whether an archived chat should auto-unarchive on receiving a new message.
  /// If keepChatsArchived is true, it remains archived.
  /// Otherwise, if lastMessageTime > archivedAt, it auto-unarchives.
  static bool shouldAutoUnarchive({
    required bool isArchived,
    required bool keepChatsArchived,
    required DateTime? lastMessageTime,
    required DateTime? archivedAt,
  }) {
    if (!isArchived) return false;
    if (keepChatsArchived) return false;
    if (lastMessageTime == null) return false;
    if (archivedAt == null) return true;
    return lastMessageTime.isAfter(archivedAt);
  }

  /// If ANY selected chat is NOT favourited -> return true (Action: "Add to Favourites").
  /// Only if ALL are favourited -> return false (Action: "Remove from Favourites").
  static bool shouldFavourite({
    required Set<String> selectedIds,
    required Set<String> favouriteIds,
  }) {
    if (selectedIds.isEmpty) return false;
    return selectedIds.any((id) => !favouriteIds.contains(id));
  }

  /// If ANY selected chat is NOT locked -> return true (Action: "Lock chat").
  /// Only if ALL are locked -> return false (Action: "Unlock chat").
  static bool shouldLock({
    required Set<String> selectedIds,
    required Set<String> lockedIds,
  }) {
    if (selectedIds.isEmpty) return false;
    return selectedIds.any((id) => !lockedIds.contains(id));
  }

  /// If ANY selected chat is unread -> return true (Action: "Mark as read").
  /// Only if ALL selected are read -> return false (Action: "Mark as unread").
  static bool shouldMarkAsRead({
    required Set<String> selectedIds,
    required Map<String, int> unreadCounts,
    required Set<String> locallyUnreadIds,
    required Set<String> locallyReadIds,
  }) {
    if (selectedIds.isEmpty) return false;
    for (final id in selectedIds) {
      if (locallyUnreadIds.contains(id)) return true;
      if (locallyReadIds.contains(id)) continue;
      final count = unreadCounts[id] ?? 0;
      if (count > 0) return true;
    }
    return false;
  }

  /// Formula for Pin limit calculation:
  /// Count ONLY the chats in the selection that are NOT already pinned.
  /// If (currentPinnedCount - alreadyPinnedInSelection + newChatsToBePinned) > maxLimit -> reject.
  static bool canPinBatch({
    required int currentPinnedCount,
    required int alreadyPinnedInSelection,
    required int newChatsToBePinned,
    int maxLimit = 3,
  }) {
    final projectedTotal = currentPinnedCount - alreadyPinnedInSelection + newChatsToBePinned;
    return projectedTotal <= maxLimit;
  }

  /// Checks if chat is muted against absolute UTC timestamp.
  /// -1 or null with key present = Always muted.
  /// Expiry timestamp in future = Muted.
  /// Past expiry timestamp = Expired (not muted).
  static bool isChatMuted(
    Map<String, int?> mutedExpiries,
    String chatId, {
    DateTime? now,
  }) {
    if (!mutedExpiries.containsKey(chatId)) return false;
    final expiry = mutedExpiries[chatId];
    if (expiry == null || expiry == -1) return true; // Always muted
    final currentEpoch = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    return expiry > currentEpoch;
  }

  /// Identifies and returns all expired chat IDs from the mutes map based on UTC epoch ms.
  static Set<String> getExpiredMuteChatIds(
    Map<String, int?> mutedExpiries, {
    DateTime? now,
  }) {
    final currentEpoch = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final expired = <String>{};
    for (final entry in mutedExpiries.entries) {
      if (entry.value != null && entry.value != -1 && entry.value! <= currentEpoch) {
        expired.add(entry.key);
      }
    }
    return expired;
  }

  /// Cleans and returns a new map with expired mutes purged.
  static Map<String, int?> filterActiveMutes(
    Map<String, int?> mutedExpiries, {
    DateTime? now,
  }) {
    final expired = getExpiredMuteChatIds(mutedExpiries, now: now);
    if (expired.isEmpty) return Map<String, int?>.from(mutedExpiries);
    final result = Map<String, int?>.from(mutedExpiries);
    for (final id in expired) {
      result.remove(id);
    }
    return result;
  }

  /// Multi-device conflict resolution: Server is always the source of truth (Server Wins).
  static Map<String, dynamic> resolveServerWins({
    required Map<String, dynamic> localCache,
    required Map<String, dynamic> serverData,
  }) {
    return {
      'pinnedChatIds': Set<String>.from(serverData['pinnedChatIds'] ?? {}),
      'pinnedTimestamps': Map<String, int>.from(serverData['pinnedTimestamps'] ?? {}),
      'mutedChatExpiries': Map<String, int?>.from(serverData['mutedChatExpiries'] ?? {}),
      'archivedChatIds': Set<String>.from(serverData['archivedChatIds'] ?? {}),
      'archivedTimestamps': Map<String, int>.from(serverData['archivedTimestamps'] ?? {}),
      'keepChatsArchived': serverData['keepChatsArchived'] ?? false,
      'favouriteChatIds': Set<String>.from(serverData['favouriteChatIds'] ?? {}),
      'lockedChatIds': Set<String>.from(serverData['lockedChatIds'] ?? {}),
      'deletedChatIds': Set<String>.from(serverData['deletedChatIds'] ?? {}),
    };
  }
}

/// Service handling persistent D1 SQL single source of truth + SharedPreferences local cache
class ChatPreferencesService {
  static final ChatPreferencesService _instance = ChatPreferencesService._internal();
  factory ChatPreferencesService() => _instance;
  static ChatPreferencesService get instance => _instance;
  ChatPreferencesService._internal();

  /// Loads preferences with Cloudflare D1 REST single source of truth (Server wins).
  Future<Map<String, dynamic>> loadPreferences(String userHandle) async {
    final clean = userHandle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return _emptyPreferences();

    Map<String, dynamic> localData = await _loadFromCache(clean);

    try {
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/preferences/$clean'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final prefsData = body['preferences'] as Map<String, dynamic>? ?? {};
        final serverData = _parsePreferencesData(prefsData);

        final resolved = ChatSelectionLogic.resolveServerWins(
          localCache: localData,
          serverData: serverData,
        );

        final activeMutes = ChatSelectionLogic.filterActiveMutes(resolved['mutedChatExpiries']);
        final hasExpired = activeMutes.length != resolved['mutedChatExpiries'].length;
        resolved['mutedChatExpiries'] = activeMutes;

        await _saveToCache(clean, resolved);

        if (hasExpired) {
          unawaited(savePreferences(clean, resolved));
        }

        return resolved;
      }
    } catch (e) {
      debugPrint('Error loading chat preferences from D1 API: $e');
    }

    final activeLocalMutes = ChatSelectionLogic.filterActiveMutes(localData['mutedChatExpiries'] ?? {});
    localData['mutedChatExpiries'] = activeLocalMutes;
    return localData;
  }

  /// Writes preferences to D1 REST API (source of truth) and updates local cache.
  Future<bool> savePreferences(String userHandle, Map<String, dynamic> data) async {
    final clean = userHandle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return false;

    // 1. Optimistic write to local cache (guaranteed offline resilience)
    await _saveToCache(clean, data);

    // 2. Write to Cloudflare D1 via backend
    try {
      final payload = {
        'handle': clean,
        'preferences': {
          'pinnedChatIds': (data['pinnedChatIds'] as Set<String>?)?.toList() ?? (data['pinnedChatIds'] as List<dynamic>?) ?? [],
          'pinnedTimestamps': data['pinnedTimestamps'] ?? {},
          'mutedChatExpiries': data['mutedChatExpiries'] ?? {},
          'archivedChatIds': (data['archivedChatIds'] as Set<String>?)?.toList() ?? (data['archivedChatIds'] as List<dynamic>?) ?? [],
          'archivedTimestamps': data['archivedTimestamps'] ?? {},
          'keepChatsArchived': data['keepChatsArchived'] ?? false,
          'favouriteChatIds': (data['favouriteChatIds'] as Set<String>?)?.toList() ?? (data['favouriteChatIds'] as List<dynamic>?) ?? [],
          'lockedChatIds': (data['lockedChatIds'] as Set<String>?)?.toList() ?? (data['lockedChatIds'] as List<dynamic>?) ?? [],
          'deletedChatIds': (data['deletedChatIds'] as Set<String>?)?.toList() ?? (data['deletedChatIds'] as List<dynamic>?) ?? [],
        },
      };

      await http.post(
        Uri.parse('${AuthService.baseUrl}/preferences'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));

      return true;
    } catch (e) {
      debugPrint('D1 savePreferences note (saved to local cache): $e');
      return true;
    }
  }

  /// Checks if a chat is currently muted for a specific user.
  Future<bool> isChatMutedForUser(String userHandle, String partnerHandle) async {
    final cleanMe = userHandle.replaceAll('@', '').trim().toLowerCase();
    final cleanPartner = partnerHandle.replaceAll('@', '').trim().toLowerCase();

    final prefs = await loadPreferences(cleanMe);
    final mutes = (prefs['mutedChatExpiries'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as num?)?.toInt()),
        ) ??
        {};

    for (final entry in mutes.entries) {
      if (entry.key.toLowerCase().contains(cleanPartner)) {
        return ChatSelectionLogic.isChatMuted(mutes, entry.key);
      }
    }
    return false;
  }

  Map<String, dynamic> _emptyPreferences() => {
        'pinnedChatIds': <String>{},
        'pinnedTimestamps': <String, int>{},
        'mutedChatExpiries': <String, int?>{},
        'archivedChatIds': <String>{},
        'archivedTimestamps': <String, int>{},
        'keepChatsArchived': false,
        'favouriteChatIds': <String>{},
        'lockedChatIds': <String>{},
        'deletedChatIds': <String>{},
      };

  Map<String, dynamic> _parsePreferencesData(Map<String, dynamic> data) {
    final pinnedList = (data['pinnedChatIds'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? <String>{};
    final archivedList = (data['archivedChatIds'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? <String>{};
    final favList = (data['favouriteChatIds'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? <String>{};
    final lockedList = (data['lockedChatIds'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? <String>{};
    final deletedList = (data['deletedChatIds'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? <String>{};

    final rawPinnedTimes = data['pinnedTimestamps'] as Map<String, dynamic>? ?? {};
    final pinnedTimestamps = rawPinnedTimes.map((k, v) => MapEntry(k, (v as num).toInt()));

    final rawArchivedTimes = data['archivedTimestamps'] as Map<String, dynamic>? ?? {};
    final archivedTimestamps = rawArchivedTimes.map((k, v) => MapEntry(k, (v as num).toInt()));

    final keepChatsArchived = data['keepChatsArchived'] == true;

    final rawMutes = data['mutedChatExpiries'] as Map<String, dynamic>? ?? {};
    final mutedChatExpiries = rawMutes.map((k, v) => MapEntry(k, (v as num?)?.toInt()));

    return {
      'pinnedChatIds': pinnedList,
      'pinnedTimestamps': pinnedTimestamps,
      'mutedChatExpiries': mutedChatExpiries,
      'archivedChatIds': archivedList,
      'archivedTimestamps': archivedTimestamps,
      'keepChatsArchived': keepChatsArchived,
      'favouriteChatIds': favList,
      'lockedChatIds': lockedList,
      'deletedChatIds': deletedList,
    };
  }

  Future<Map<String, dynamic>> _loadFromCache(String cleanHandle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chat_prefs_v2_$cleanHandle');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return _parsePreferencesData(decoded);
      }
    } catch (_) {}
    return _emptyPreferences();
  }

  Future<void> _saveToCache(String cleanHandle, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheMap = {
        'pinnedChatIds': (data['pinnedChatIds'] as Set<String>?)?.toList() ?? (data['pinnedChatIds'] as List<dynamic>?) ?? [],
        'pinnedTimestamps': data['pinnedTimestamps'] ?? {},
        'mutedChatExpiries': data['mutedChatExpiries'] ?? {},
        'archivedChatIds': (data['archivedChatIds'] as Set<String>?)?.toList() ?? (data['archivedChatIds'] as List<dynamic>?) ?? [],
        'archivedTimestamps': data['archivedTimestamps'] ?? {},
        'keepChatsArchived': data['keepChatsArchived'] ?? false,
        'favouriteChatIds': (data['favouriteChatIds'] as Set<String>?)?.toList() ?? (data['favouriteChatIds'] as List<dynamic>?) ?? [],
        'lockedChatIds': (data['lockedChatIds'] as Set<String>?)?.toList() ?? (data['lockedChatIds'] as List<dynamic>?) ?? [],
        'deletedChatIds': (data['deletedChatIds'] as Set<String>?)?.toList() ?? (data['deletedChatIds'] as List<dynamic>?) ?? [],
      };
      await prefs.setString('chat_prefs_v2_$cleanHandle', jsonEncode(cacheMap));
    } catch (_) {}
  }
}
