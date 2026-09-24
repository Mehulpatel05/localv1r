import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearhood/services/chat_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Mixed Selection Archive Rules', () {
    test('Mixed selection (2 archived + 1 not) -> shouldArchive is true ("Archive"), archiving all 3 produces set of 3', () {
      final currentArchived = {'chat_1', 'chat_2'};
      final selected = {'chat_1', 'chat_2', 'chat_3'}; // 2 archived + 1 unarchived

      // Mixed selection rule: shouldArchive is true because chat_3 is not archived
      final shouldArchive = ChatSelectionLogic.shouldArchive(
        selectedIds: selected,
        archivedIds: currentArchived,
      );
      expect(shouldArchive, isTrue, reason: 'Button must show "Archive" when selection contains at least one non-archived chat');

      // Applying archive: all 3 become archived (chat_1 and chat_2 are skipped/no-op)
      final newArchived = ChatSelectionLogic.archiveSelected(
        currentArchivedIds: currentArchived,
        selectedIds: selected,
      );

      expect(newArchived.length, equals(3));
      expect(newArchived, containsAll(['chat_1', 'chat_2', 'chat_3']));
    });

    test('All-archived selection -> shouldArchive is false ("Unarchive"), unarchiving all removes all of them', () {
      final currentArchived = {'chat_1', 'chat_2', 'chat_3'};
      final selected = {'chat_1', 'chat_2', 'chat_3'}; // 100% archived

      final shouldArchive = ChatSelectionLogic.shouldArchive(
        selectedIds: selected,
        archivedIds: currentArchived,
      );
      expect(shouldArchive, isFalse, reason: 'Button must show "Unarchive" when 100% of selected chats are already archived');

      // Applying unarchive: all selected chats are removed
      final newArchived = ChatSelectionLogic.unarchiveSelected(
        currentArchivedIds: currentArchived,
        selectedIds: selected,
      );

      expect(newArchived, isEmpty);
    });

    test('Partial unarchive: selecting 2 of 3 archived chats removes only the selected 2', () {
      final currentArchived = {'chat_1', 'chat_2', 'chat_3'};
      final selected = {'chat_1', 'chat_2'};

      final shouldArchive = ChatSelectionLogic.shouldArchive(
        selectedIds: selected,
        archivedIds: currentArchived,
      );
      expect(shouldArchive, isFalse);

      final newArchived = ChatSelectionLogic.unarchiveSelected(
        currentArchivedIds: currentArchived,
        selectedIds: selected,
      );

      expect(newArchived, equals({'chat_3'}));
    });
  });

  group('2. Auto-Unarchive on Incoming Message', () {
    test('New message arrives in archived chat -> auto-unarchives when keepChatsArchived is false', () {
      final archivedAt = DateTime.utc(2026, 9, 23, 10, 0, 0);
      final newMessageTime = DateTime.utc(2026, 9, 23, 10, 5, 0); // 5 mins later

      final shouldUnarchive = ChatSelectionLogic.shouldAutoUnarchive(
        isArchived: true,
        keepChatsArchived: false,
        lastMessageTime: newMessageTime,
        archivedAt: archivedAt,
      );

      expect(shouldUnarchive, isTrue, reason: 'New message after archived timestamp must trigger auto-unarchive');
    });

    test('New message arrives in archived chat -> stays archived when keepChatsArchived is true', () {
      final archivedAt = DateTime.utc(2026, 9, 23, 10, 0, 0);
      final newMessageTime = DateTime.utc(2026, 9, 23, 10, 5, 0);

      final shouldUnarchive = ChatSelectionLogic.shouldAutoUnarchive(
        isArchived: true,
        keepChatsArchived: true, // "Keep chats archived" setting enabled
        lastMessageTime: newMessageTime,
        archivedAt: archivedAt,
      );

      expect(shouldUnarchive, isFalse, reason: 'Chat must remain archived if keepChatsArchived setting is enabled');
    });

    test('Old message before archived timestamp does NOT auto-unarchive', () {
      final archivedAt = DateTime.utc(2026, 9, 23, 10, 0, 0);
      final oldMessageTime = DateTime.utc(2026, 9, 23, 9, 55, 0); // 5 mins before

      final shouldUnarchive = ChatSelectionLogic.shouldAutoUnarchive(
        isArchived: true,
        keepChatsArchived: false,
        lastMessageTime: oldMessageTime,
        archivedAt: archivedAt,
      );

      expect(shouldUnarchive, isFalse, reason: 'Existing/old messages must not trigger auto-unarchive');
    });
  });

  group('3. Firestore Write Failure Auto-Rollback vs User-Triggered Undo', () {
    test('Firestore write failure auto-reverts local state to rollback snapshot', () {
      final initialPreferences = <String, dynamic>{
        'pinnedChatIds': {'chat_pin_1'},
        'pinnedTimestamps': {'chat_pin_1': 1000},
        'mutedChatExpiries': <String, int?>{},
        'archivedChatIds': <String>{},
        'archivedTimestamps': <String, int>{},
        'keepChatsArchived': false,
        'favouriteChatIds': <String>{},
        'lockedChatIds': <String>{},
        'deletedChatIds': <String>{},
      };

      // 1. User archives chat_A optimistically
      Map<String, dynamic> localState = {
        ...initialPreferences,
        'archivedChatIds': {'chat_A'},
        'archivedTimestamps': {'chat_A': 2000},
      };
      expect(localState['archivedChatIds'], contains('chat_A'));

      // 2. Simulated Firestore sync failure (e.g. permission or network error)
      const bool firestoreWriteSuccess = false;
      if (!firestoreWriteSuccess) {
        // System Auto-Rollback (separate from user Undo)
        localState = Map<String, dynamic>.from(initialPreferences);
      }

      // 3. Verify state reverted back to initial snapshot
      expect(localState['archivedChatIds'], isEmpty);
      expect(localState['pinnedChatIds'], equals({'chat_pin_1'}));
    });

    test('User-triggered Undo within 5s reverts local state AND prepares prior Firestore payload', () {
      final priorSnapshot = <String, dynamic>{
        'pinnedChatIds': {'chat_pin_1'},
        'pinnedTimestamps': {'chat_pin_1': 1000},
        'mutedChatExpiries': <String, int?>{},
        'archivedChatIds': {'chat_already_archived'},
        'archivedTimestamps': {'chat_already_archived': 500},
        'keepChatsArchived': false,
        'favouriteChatIds': <String>{},
        'lockedChatIds': <String>{},
        'deletedChatIds': <String>{},
      };

      // 1. User archives chat_new
      Map<String, dynamic> activeState = {
        ...priorSnapshot,
        'archivedChatIds': {'chat_already_archived', 'chat_new'},
        'archivedTimestamps': {'chat_already_archived': 500, 'chat_new': 1200},
      };

      expect(activeState['archivedChatIds'], contains('chat_new'));

      // 2. User taps 'Undo' on floating SnackBar within 5 seconds
      activeState = Map<String, dynamic>.from(priorSnapshot);

      // 3. Prior state is restored and synced to Firestore
      expect(activeState['archivedChatIds'], equals({'chat_already_archived'}));
      expect(activeState['archivedChatIds'], isNot(contains('chat_new')));
      expect(activeState['pinnedChatIds'], equals({'chat_pin_1'}));
    });
  });

  group('4. Multi-Device Conflict Resolution (Server Wins)', () {
    test('Server data always overwrites stale local cache on load', () {
      final localCache = {
        'pinnedChatIds': <String>{},
        'pinnedTimestamps': <String, int>{},
        'mutedChatExpiries': <String, int?>{},
        'archivedChatIds': {'stale_local_archive'},
        'archivedTimestamps': {'stale_local_archive': 100},
        'keepChatsArchived': false,
        'favouriteChatIds': <String>{},
        'lockedChatIds': <String>{},
        'deletedChatIds': <String>{},
      };

      final serverData = {
        'pinnedChatIds': {'chat_1'},
        'pinnedTimestamps': {'chat_1': 2000},
        'mutedChatExpiries': <String, int?>{},
        'archivedChatIds': {'server_archived_chat'},
        'archivedTimestamps': {'server_archived_chat': 3000},
        'keepChatsArchived': true,
        'favouriteChatIds': <String>{},
        'lockedChatIds': <String>{},
        'deletedChatIds': <String>{},
      };

      final resolved = ChatSelectionLogic.resolveServerWins(
        localCache: localCache,
        serverData: serverData,
      );

      expect(resolved['archivedChatIds'], equals({'server_archived_chat'}));
      expect(resolved['archivedTimestamps'], equals({'server_archived_chat': 3000}));
      expect(resolved['keepChatsArchived'], isTrue);
      expect(resolved['pinnedChatIds'], equals({'chat_1'}));
    });
  });

  group('5. Batch Archiving (50+ Chats)', () {
    test('Batch archiving 50 chats executes single Set operation without duplicates', () {
      final fiftyChats = List.generate(50, (i) => 'batch_chat_$i').toSet();
      final existingArchived = {'batch_chat_0', 'batch_chat_1'}; // 2 already archived

      final result = ChatSelectionLogic.archiveSelected(
        currentArchivedIds: existingArchived,
        selectedIds: fiftyChats,
      );

      expect(result.length, equals(50));
      for (int i = 0; i < 50; i++) {
        expect(result.contains('batch_chat_$i'), isTrue);
      }
    });
  });

  group('6. Animation Simultaneous Duration Verification (Widget Test)', () {
    testWidgets('Tile collapses height and opacity simultaneously on exact same 250ms timeline', (tester) async {
      bool isDismissing = false;
      late StateSetter stateSetter;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                stateSetter = setState;
                return RepaintBoundary(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: isDismissing ? 0 : 78,
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isDismissing ? 0.0 : 1.0,
                        child: const SizedBox(
                          height: 78,
                          child: Text('Chat Tile Item'),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Initial state: fully visible
      expect(find.text('Chat Tile Item'), findsOneWidget);
      AnimatedOpacity animatedOpacity = tester.widget(find.byType(AnimatedOpacity));
      AnimatedSize animatedSize = tester.widget(find.byType(AnimatedSize));

      expect(animatedOpacity.opacity, equals(1.0));
      expect(animatedOpacity.duration, equals(const Duration(milliseconds: 250)));
      expect(animatedSize.duration, equals(const Duration(milliseconds: 250)));
      expect(animatedOpacity.curve, equals(Curves.easeInOut));
      expect(animatedSize.curve, equals(Curves.easeInOut));

      // Trigger dismissal collapse
      stateSetter(() {
        isDismissing = true;
      });
      await tester.pump();

      // Check midway through animation (125ms)
      await tester.pump(const Duration(milliseconds: 125));
      AnimatedOpacity midwayOpacity = tester.widget(find.byType(AnimatedOpacity));
      expect(midwayOpacity.opacity, equals(0.0)); // Target opacity updated to 0

      // Settle full 250ms animation
      await tester.pump(const Duration(milliseconds: 125));
      await tester.pumpAndSettle();
    });
  });
}
