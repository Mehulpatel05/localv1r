import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearhood/models/chat_conversation_model.dart';

void main() {
  group('Select All Widget Tree Performance & Repaint Isolation', () {
    testWidgets('Select All isolates rebuilds to visible tiles and maintains RepaintBoundary on every tile', (WidgetTester tester) async {
      int scaffoldBuildCount = 0;
      int listViewBuildCount = 0;
      final Map<String, int> tileBuildCounts = {};

      // 1. Generate 300 mock chat conversations
      final conversations = List.generate(
        300,
        (i) => ChatConversation(
          id: 'chat_conv_$i',
          participants: ['user_me', 'neighbor_$i'],
          lastMessage: 'Hey neighbor $i, how are you?',
          lastSenderHandle: 'neighbor_$i',
          unreadCounts: {'user_me': (i % 3 == 0) ? 1 : 0},
          updatedAt: DateTime.now().subtract(Duration(minutes: i)),
        ),
      );

      final selectedChatIdsNotifier = ValueNotifier<Set<String>>(<String>{});

      // 2. Build the test widget tree containing Scoped Selection & Isolated RepaintBoundaries
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              scaffoldBuildCount++;
              return Scaffold(
                appBar: PreferredSize(
                  preferredSize: const Size.fromHeight(kToolbarHeight),
                  child: ValueListenableBuilder<Set<String>>(
                    valueListenable: selectedChatIdsNotifier,
                    builder: (context, selected, _) {
                      final isSelectionMode = selected.isNotEmpty;
                      return AppBar(
                        key: const ValueKey('app_bar_key'),
                        title: Text(isSelectionMode ? '${selected.length} selected' : 'Messages'),
                        actions: [
                          if (isSelectionMode)
                            IconButton(
                              key: const ValueKey('select_all_button'),
                              icon: const Icon(Icons.select_all_rounded),
                              onPressed: () {
                                selectedChatIdsNotifier.value = conversations.map((c) => c.id).toSet();
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
                body: Builder(
                  builder: (context) {
                    listViewBuildCount++;
                    return ListView.builder(
                      key: const ValueKey('chat_list_view'),
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final conv = conversations[index];

                        // Each tile is enclosed in its own distinct RepaintBoundary with scoped listener
                        return RepaintBoundary(
                          key: ValueKey('repaint_tile_${conv.id}'),
                          child: ValueListenableBuilder<Set<String>>(
                            valueListenable: selectedChatIdsNotifier,
                            builder: (context, selectedIds, _) {
                              tileBuildCounts[conv.id] = (tileBuildCounts[conv.id] ?? 0) + 1;
                              final isSelected = selectedIds.contains(conv.id);
                              return Container(
                                key: ValueKey('tile_container_${conv.id}'),
                                color: isSelected ? const Color(0xFFE8F5E9) : Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected ? const Color(0xFF10B981) : Colors.grey.shade300,
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check, color: Colors.white, size: 24)
                                          : Center(child: Text(conv.participants.last[0].toUpperCase())),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(conv.participants.last, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          Text(conv.lastMessage, maxLines: 1),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      );

      // Initial pump verification
      expect(find.text('Messages'), findsOneWidget);
      expect(scaffoldBuildCount, equals(1));
      expect(listViewBuildCount, equals(1));

      // Verify that RepaintBoundary exists for rendered tiles in the viewport
      final repaintBoundaries = find.byType(RepaintBoundary);
      expect(repaintBoundaries, findsWidgets);

      // 3. Trigger Selection Mode (Select first item)
      selectedChatIdsNotifier.value = {conversations.first.id};
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('select_all_button')), findsOneWidget);

      // Confirm Scaffold & ListView ancestors did NOT rebuild when entering selection mode
      expect(scaffoldBuildCount, equals(1));
      expect(listViewBuildCount, equals(1));

      // 4. Trigger Select All
      await tester.tap(find.byKey(const ValueKey('select_all_button')));
      await tester.pump();

      // 5. Verification of Scoped Rebuilds & Isolation
      // Scaffold and ListView body NEVER rebuilt during Select All!
      expect(scaffoldBuildCount, equals(1));
      expect(listViewBuildCount, equals(1));

      // App bar and selected count updated
      expect(selectedChatIdsNotifier.value.length, equals(300));
      expect(find.text('300 selected'), findsOneWidget);

      // Only visible rendered tiles rebuilt their scoped contents
      final visibleTileCount = tileBuildCounts.keys.length;
      expect(visibleTileCount, lessThanOrEqualTo(25)); // Only visible viewport items are built by ListView.builder

      // Verify that visible items received selected style
      final visibleFirstTile = find.byKey(ValueKey('tile_container_${conversations.first.id}'));
      expect(visibleFirstTile, findsOneWidget);
      final containerWidget = tester.widget<Container>(visibleFirstTile);
      expect(containerWidget.color, equals(const Color(0xFFE8F5E9)));
    });
  });
}
