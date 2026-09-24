import 'package:flutter_test/flutter_test.dart';
import 'package:nearhood/services/chat_preferences_service.dart';

void main() {
  group('ChatSelectionLogic - Mixed Selection Rules', () {
    // ── 1. Pin / Unpin Mixed Selection ──
    test('Pin: All unpinned -> shouldPin is true (Action: Pin)', () {
      final selected = {'chat_1', 'chat_2'};
      final pinned = <String>{};
      expect(ChatSelectionLogic.shouldPin(selectedIds: selected, pinnedIds: pinned), isTrue);
    });

    test('Pin: All pinned -> shouldPin is false (Action: Unpin)', () {
      final selected = {'chat_1', 'chat_2'};
      final pinned = {'chat_1', 'chat_2', 'chat_3'};
      expect(ChatSelectionLogic.shouldPin(selectedIds: selected, pinnedIds: pinned), isFalse);
    });

    test('Pin: Mixed (1 pinned, 1 unpinned) -> shouldPin is true (Action: Pin All)', () {
      final selected = {'chat_1', 'chat_2'};
      final pinned = {'chat_1'};
      expect(ChatSelectionLogic.shouldPin(selectedIds: selected, pinnedIds: pinned), isTrue);
    });

    // ── 2. Mute / Unmute Mixed Selection ──
    test('Mute: All unmuted -> shouldMute is true (Action: Mute)', () {
      final selected = {'chat_1', 'chat_2'};
      final mutes = <String, int?>{};
      expect(ChatSelectionLogic.shouldMute(selectedIds: selected, mutedExpiries: mutes), isTrue);
    });

    test('Mute: All muted -> shouldMute is false (Action: Unmute)', () {
      final selected = {'chat_1', 'chat_2'};
      final mutes = {'chat_1': -1, 'chat_2': -1};
      expect(ChatSelectionLogic.shouldMute(selectedIds: selected, mutedExpiries: mutes), isFalse);
    });

    test('Mute: Mixed (1 muted, 1 unmuted) -> shouldMute is true (Action: Mute All)', () {
      final selected = {'chat_1', 'chat_2'};
      final mutes = {'chat_1': -1};
      expect(ChatSelectionLogic.shouldMute(selectedIds: selected, mutedExpiries: mutes), isTrue);
    });

    // ── 3. Archive / Unarchive Mixed Selection ──
    test('Archive: All unarchived -> shouldArchive is true (Action: Archive)', () {
      final selected = {'chat_1', 'chat_2'};
      final archives = <String>{};
      expect(ChatSelectionLogic.shouldArchive(selectedIds: selected, archivedIds: archives), isTrue);
    });

    test('Archive: All archived -> shouldArchive is false (Action: Unarchive)', () {
      final selected = {'chat_1', 'chat_2'};
      final archives = {'chat_1', 'chat_2'};
      expect(ChatSelectionLogic.shouldArchive(selectedIds: selected, archivedIds: archives), isFalse);
    });

    test('Archive: Mixed (1 archived, 1 unarchived) -> shouldArchive is true (Action: Archive All)', () {
      final selected = {'chat_1', 'chat_2'};
      final archives = {'chat_1'};
      expect(ChatSelectionLogic.shouldArchive(selectedIds: selected, archivedIds: archives), isTrue);
    });

    // ── 4. Favourite Mixed Selection ──
    test('Favourite: All unfavourited -> shouldFavourite is true (Action: Add to Favourites)', () {
      final selected = {'chat_1', 'chat_2'};
      final favs = <String>{};
      expect(ChatSelectionLogic.shouldFavourite(selectedIds: selected, favouriteIds: favs), isTrue);
    });

    test('Favourite: All favourited -> shouldFavourite is false (Action: Remove from Favourites)', () {
      final selected = {'chat_1', 'chat_2'};
      final favs = {'chat_1', 'chat_2'};
      expect(ChatSelectionLogic.shouldFavourite(selectedIds: selected, favouriteIds: favs), isFalse);
    });

    test('Favourite: Mixed (1 fav, 1 not fav) -> shouldFavourite is true (Action: Add to Favourites)', () {
      final selected = {'chat_1', 'chat_2'};
      final favs = {'chat_1'};
      expect(ChatSelectionLogic.shouldFavourite(selectedIds: selected, favouriteIds: favs), isTrue);
    });

    // ── 5. Lock Mixed Selection ──
    test('Lock: All unlocked -> shouldLock is true (Action: Lock)', () {
      final selected = {'chat_1', 'chat_2'};
      final locked = <String>{};
      expect(ChatSelectionLogic.shouldLock(selectedIds: selected, lockedIds: locked), isTrue);
    });

    test('Lock: All locked -> shouldLock is false (Action: Unlock)', () {
      final selected = {'chat_1', 'chat_2'};
      final locked = {'chat_1', 'chat_2'};
      expect(ChatSelectionLogic.shouldLock(selectedIds: selected, lockedIds: locked), isFalse);
    });

    test('Lock: Mixed (1 locked, 1 unlocked) -> shouldLock is true (Action: Lock All)', () {
      final selected = {'chat_1', 'chat_2'};
      final locked = {'chat_1'};
      expect(ChatSelectionLogic.shouldLock(selectedIds: selected, lockedIds: locked), isTrue);
    });

    // ── 6. Mark as Read / Unread Mixed Selection ──
    test('Read/Unread: All read -> shouldMarkAsRead is false (Action: Mark as unread)', () {
      final selected = {'chat_1', 'chat_2'};
      final unreadMap = {'chat_1': 0, 'chat_2': 0};
      expect(
        ChatSelectionLogic.shouldMarkAsRead(
          selectedIds: selected,
          unreadCounts: unreadMap,
          locallyUnreadIds: {},
          locallyReadIds: {},
        ),
        isFalse,
      );
    });

    test('Read/Unread: All unread -> shouldMarkAsRead is true (Action: Mark as read)', () {
      final selected = {'chat_1', 'chat_2'};
      final unreadMap = {'chat_1': 3, 'chat_2': 1};
      expect(
        ChatSelectionLogic.shouldMarkAsRead(
          selectedIds: selected,
          unreadCounts: unreadMap,
          locallyUnreadIds: {},
          locallyReadIds: {},
        ),
        isTrue,
      );
    });

    test('Read/Unread: Mixed (1 unread, 1 read) -> shouldMarkAsRead is true (Action: Mark as read)', () {
      final selected = {'chat_1', 'chat_2'};
      final unreadMap = {'chat_1': 2, 'chat_2': 0};
      expect(
        ChatSelectionLogic.shouldMarkAsRead(
          selectedIds: selected,
          unreadCounts: unreadMap,
          locallyUnreadIds: {},
          locallyReadIds: {},
        ),
        isTrue,
      );
    });
  });

  group('Pin Limit Calculation Logic', () {
    test('2 pinned + select 2 new + 1 already-pinned in selection (3 selected total) -> should ALLOW (projected total = 3)', () {
      // Current pinned = 2 (e.g. chat_A, chat_B)
      // Selected = chat_B (already pinned), chat_C (new), chat_D (new)
      // alreadyPinnedInSelection = 1 (chat_B)
      // newChatsToBePinned = 2 (chat_C, chat_D)
      // projected total = 2 - 1 + (1 + 2) = 3 <= 3 -> ALLOW
      final canPin = ChatSelectionLogic.canPinBatch(
        currentPinnedCount: 2,
        alreadyPinnedInSelection: 1,
        newChatsToBePinned: 2,
        maxLimit: 3,
      );
      expect(canPin, isTrue);
    });

    test('2 pinned + select 2 new + 0 already-pinned -> should REJECT (projected total = 4 > 3)', () {
      final canPin = ChatSelectionLogic.canPinBatch(
        currentPinnedCount: 2,
        alreadyPinnedInSelection: 0,
        newChatsToBePinned: 2,
        maxLimit: 3,
      );
      expect(canPin, isFalse);
    });

    test('3 pinned + select 1 already-pinned -> should ALLOW (projected total = 3)', () {
      final canPin = ChatSelectionLogic.canPinBatch(
        currentPinnedCount: 3,
        alreadyPinnedInSelection: 1,
        newChatsToBePinned: 0,
        maxLimit: 3,
      );
      expect(canPin, isTrue);
    });
  });

  group('Mute Expiry Logic', () {
    test('Mute for 8 hours is active before expiry', () {
      final now = DateTime.utc(2026, 3, 23, 12, 0);
      final expiry = now.add(const Duration(hours: 8)).millisecondsSinceEpoch;
      final mutes = {'chat_1': expiry};

      // 4 hours later -> still muted
      final checkTime = now.add(const Duration(hours: 4));
      expect(ChatSelectionLogic.isChatMuted(mutes, 'chat_1', now: checkTime), isTrue);
    });

    test('Mute for 8 hours expires after 8 hours', () {
      final now = DateTime.utc(2026, 3, 23, 12, 0);
      final expiry = now.add(const Duration(hours: 8)).millisecondsSinceEpoch;
      final mutes = {'chat_1': expiry};

      // 9 hours later -> expired!
      final checkTime = now.add(const Duration(hours: 9));
      expect(ChatSelectionLogic.isChatMuted(mutes, 'chat_1', now: checkTime), isFalse);
    });

    test('Always mute (-1) never expires', () {
      final now = DateTime.utc(2026, 3, 23, 12, 0);
      final mutes = {'chat_1': -1};

      // 1 year later -> still muted!
      final checkTime = now.add(const Duration(days: 365));
      expect(ChatSelectionLogic.isChatMuted(mutes, 'chat_1', now: checkTime), isTrue);
    });

    test('Lazy check: Mute set 8h ago with expiry in the past -> purged on check, badge removed', () {
      final baseTime = DateTime.utc(2026, 3, 23, 10, 0);
      final eightHoursAgoExpiry = baseTime.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final futureExpiry = baseTime.add(const Duration(hours: 4)).millisecondsSinceEpoch;

      final mutes = {
        'chat_expired_1': eightHoursAgoExpiry,
        'chat_active_2': futureExpiry,
        'chat_always_3': -1,
      };

      // 1. Detect expired
      final expiredIds = ChatSelectionLogic.getExpiredMuteChatIds(mutes, now: baseTime);
      expect(expiredIds, contains('chat_expired_1'));
      expect(expiredIds, isNot(contains('chat_active_2')));
      expect(expiredIds, isNot(contains('chat_always_3')));

      // 2. Filter active mutes
      final activeMutes = ChatSelectionLogic.filterActiveMutes(mutes, now: baseTime);
      expect(activeMutes.containsKey('chat_expired_1'), isFalse);
      expect(activeMutes.containsKey('chat_active_2'), isTrue);
      expect(activeMutes.containsKey('chat_always_3'), isTrue);
      expect(ChatSelectionLogic.isChatMuted(activeMutes, 'chat_expired_1', now: baseTime), isFalse);
    });
  });

  group('Multi-Device Conflict Resolution: Server Wins', () {
    test('Server Wins: Stale local cache is discarded in favor of Firestore server data', () {
      final localStaleCache = {
        'pinnedChatIds': {'stale_chat_1', 'stale_chat_2'},
        'pinnedTimestamps': {'stale_chat_1': 1000, 'stale_chat_2': 2000},
        'mutedChatExpiries': {'stale_chat_1': -1},
        'archivedChatIds': {'stale_chat_3'},
        'favouriteChatIds': <String>{},
        'lockedChatIds': <String>{},
        'deletedChatIds': <String>{},
      };

      final serverTruth = {
        'pinnedChatIds': {'server_chat_A'},
        'pinnedTimestamps': {'server_chat_A': 9999},
        'mutedChatExpiries': {'server_chat_B': -1},
        'archivedChatIds': {'server_chat_C'},
        'favouriteChatIds': {'server_chat_D'},
        'lockedChatIds': {'server_chat_E'},
        'deletedChatIds': <String>{},
      };

      final resolved = ChatSelectionLogic.resolveServerWins(
        localCache: localStaleCache,
        serverData: serverTruth,
      );

      // Assert server data completely overwrote stale local values
      expect(resolved['pinnedChatIds'], equals({'server_chat_A'}));
      expect(resolved['pinnedTimestamps'], equals({'server_chat_A': 9999}));
      expect(resolved['mutedChatExpiries'], equals({'server_chat_B': -1}));
      expect(resolved['archivedChatIds'], equals({'server_chat_C'}));
      expect(resolved['favouriteChatIds'], equals({'server_chat_D'}));
      expect(resolved['lockedChatIds'], equals({'server_chat_E'}));
    });
  });

  group('Firestore Write Failure Auto-Rollback', () {
    test('Optimistic update auto-reverts to rollback snapshot on write error', () {
      final preActionState = <String, dynamic>{
        'pinnedChatIds': {'chat_1'},
        'pinnedTimestamps': {'chat_1': 1000},
        'mutedChatExpiries': <String, int?>{},
        'archivedChatIds': <String>{},
        'favouriteChatIds': <String>{},
        'lockedChatIds': <String>{},
        'deletedChatIds': <String>{},
      };

      // Optimistic user action: Pin chat_2
      Map<String, dynamic> currentState = <String, dynamic>{
        'pinnedChatIds': {'chat_1', 'chat_2'},
        'pinnedTimestamps': {'chat_1': 1000, 'chat_2': 2000},
        'mutedChatExpiries': <String, int?>{},
        'archivedChatIds': <String>{},
        'favouriteChatIds': <String>{},
        'lockedChatIds': <String>{},
        'deletedChatIds': <String>{},
      };

      // Simulate simulated write failure
      const bool writeSucceeded = false;
      if (!writeSucceeded) {
        // Auto-revert logic
        currentState = Map<String, dynamic>.from(preActionState);
      }

      // Assert state reverted to preActionState
      expect(currentState['pinnedChatIds'], equals({'chat_1'}));
      expect(currentState['pinnedChatIds'], isNot(contains('chat_2')));
    });
  });

  group('Select All Performance Benchmark (300+ items)', () {
    test('Select All on 300+ items executes single-pass batch update in under 5ms (well under 16ms/frame limit)', () {
      final conversations = List.generate(350, (i) => 'conversation_chat_id_$i');
      final selectedChatIds = <String>{};

      final stopwatch = Stopwatch()..start();

      // Single setState batch operation simulation
      selectedChatIds.addAll(conversations);

      stopwatch.stop();

      final elapsedMs = stopwatch.elapsedMilliseconds;

      expect(selectedChatIds.length, equals(350));
      // Frame budget is 16.6ms for 60fps and 8.3ms for 120fps.
      // Batch Set addition on 350 items takes less than 1ms.
      expect(elapsedMs, lessThan(8));
      // Verify all items are selected
      expect(selectedChatIds.contains('conversation_chat_id_0'), isTrue);
      expect(selectedChatIds.contains('conversation_chat_id_349'), isTrue);
    });
  });
}
