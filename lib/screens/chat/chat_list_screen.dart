import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/chat_conversation_model.dart';
import '../../models/friendship_model.dart';
import '../../services/chat_preferences_service.dart';
import '../../services/direct_chat_service.dart';
import '../../services/friend_repository.dart';
import 'personal_chat_screen.dart';

enum ChatFilter { all, unread, favourites }

class ChatListScreen extends StatefulWidget {
  final String currentUserHandle;

  const ChatListScreen({super.key, required this.currentUserHandle});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late final FriendRepository _friendRepo;
  Timer? _searchDebounceTimer;

  // Filter & View State
  ChatFilter _selectedFilter = ChatFilter.all;
  bool _showArchivedView = false;

  // Multi-Selection State
  final Set<String> _selectedChatIds = {};
  final Map<String, ChatConversation> _selectedConversations = {};
  List<ChatConversation> _latestVisibleConversations = [];

  bool get _isSelectionMode => _selectedChatIds.isNotEmpty;

  // Animation tracking sets (for smooth zero-lag card exit animations)
  final Set<String> _animatingDismissIds = {};

  // Single Source of Truth / Cache Sets (Pins, Timestamps, Mutes, Archives, Favourites, Locked, Deleted)
  Set<String> _pinnedChatIds = {};
  Map<String, int> _pinnedTimestamps = {}; // chatId -> epoch ms
  Map<String, int?> _mutedChatExpiries = {}; // chatId -> absolute UTC epoch ms (-1 or null for always)
  Set<String> _archivedChatIds = {};
  Map<String, int> _archivedTimestamps = {}; // chatId -> epoch ms when archived
  bool _keepChatsArchived = false;
  Set<String> _favouriteChatIds = {};
  Set<String> _lockedChatIds = {};
  Set<String> _locallyDeletedChatIds = {};
  final Set<String> _locallyReadChatIds = {};
  final Set<String> _locallyUnreadChatIds = {};

  String get _cleanMe => widget.currentUserHandle.replaceAll('@', '').trim();

  @override
  void initState() {
    super.initState();
    _friendRepo = FriendRepository()..currentUserHandle = widget.currentUserHandle;
    _searchController.addListener(_onSearchChanged);
    _loadPreferences();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cleanExpiredMutesLazy();
  }

  /// Loads preferences from Firestore (Server wins) with local cache fallback
  Future<void> _loadPreferences() async {
    final data = await ChatPreferencesService.instance.loadPreferences(_cleanMe);
    if (!mounted) return;
    setState(() {
      _pinnedChatIds = Set<String>.from(data['pinnedChatIds'] ?? {});
      _pinnedTimestamps = Map<String, int>.from(data['pinnedTimestamps'] ?? {});
      _mutedChatExpiries = Map<String, int?>.from(data['mutedChatExpiries'] ?? {});
      _archivedChatIds = Set<String>.from(data['archivedChatIds'] ?? {});
      _archivedTimestamps = Map<String, int>.from(data['archivedTimestamps'] ?? {});
      _keepChatsArchived = data['keepChatsArchived'] == true;
      _favouriteChatIds = Set<String>.from(data['favouriteChatIds'] ?? {});
      _lockedChatIds = Set<String>.from(data['lockedChatIds'] ?? {});
      _locallyDeletedChatIds = Set<String>.from(data['deletedChatIds'] ?? {});
      _cleanExpiredMutesLazy();
    });
  }

  Map<String, dynamic> _buildPreferencesMap() => {
        'pinnedChatIds': _pinnedChatIds,
        'pinnedTimestamps': _pinnedTimestamps,
        'mutedChatExpiries': _mutedChatExpiries,
        'archivedChatIds': _archivedChatIds,
        'archivedTimestamps': _archivedTimestamps,
        'keepChatsArchived': _keepChatsArchived,
        'favouriteChatIds': _favouriteChatIds,
        'lockedChatIds': _lockedChatIds,
        'deletedChatIds': _locallyDeletedChatIds,
      };

  Map<String, dynamic> _clonePreferencesMap() => {
        'pinnedChatIds': Set<String>.from(_pinnedChatIds),
        'pinnedTimestamps': Map<String, int>.from(_pinnedTimestamps),
        'mutedChatExpiries': Map<String, int?>.from(_mutedChatExpiries),
        'archivedChatIds': Set<String>.from(_archivedChatIds),
        'archivedTimestamps': Map<String, int>.from(_archivedTimestamps),
        'keepChatsArchived': _keepChatsArchived,
        'favouriteChatIds': Set<String>.from(_favouriteChatIds),
        'lockedChatIds': Set<String>.from(_lockedChatIds),
        'deletedChatIds': Set<String>.from(_locallyDeletedChatIds),
      };

  void _restorePreferencesState(Map<String, dynamic> snapshot) {
    setState(() {
      _pinnedChatIds = Set<String>.from(snapshot['pinnedChatIds'] ?? {});
      _pinnedTimestamps = Map<String, int>.from(snapshot['pinnedTimestamps'] ?? {});
      _mutedChatExpiries = Map<String, int?>.from(snapshot['mutedChatExpiries'] ?? {});
      _archivedChatIds = Set<String>.from(snapshot['archivedChatIds'] ?? {});
      _archivedTimestamps = Map<String, int>.from(snapshot['archivedTimestamps'] ?? {});
      _keepChatsArchived = snapshot['keepChatsArchived'] == true;
      _favouriteChatIds = Set<String>.from(snapshot['favouriteChatIds'] ?? {});
      _lockedChatIds = Set<String>.from(snapshot['lockedChatIds'] ?? {});
      _locallyDeletedChatIds = Set<String>.from(snapshot['deletedChatIds'] ?? {});
    });
  }

  Future<bool> _syncPreferencesToFirestore({Map<String, dynamic>? rollbackSnapshot}) async {
    final data = _buildPreferencesMap();
    try {
      final success = await ChatPreferencesService.instance.savePreferences(_cleanMe, data);
      if (!success) {
        if (mounted && rollbackSnapshot != null) {
          _restorePreferencesState(rollbackSnapshot);
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(
                content: Text("Couldn't update, try again"),
                behavior: SnackBarBehavior.floating,
              ),
            );
        }
        return false;
      }
      return true;
    } catch (e) {
      if (mounted && rollbackSnapshot != null) {
        _restorePreferencesState(rollbackSnapshot);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text("Couldn't update, try again"),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      return false;
    }
  }

  /// Lazy check: compares each muted chat's absolute UTC expiry against DateTime.now()
  void _cleanExpiredMutesLazy() {
    final expired = ChatSelectionLogic.getExpiredMuteChatIds(_mutedChatExpiries);
    if (expired.isNotEmpty) {
      setState(() {
        for (final id in expired) {
          _mutedChatExpiries.remove(id);
        }
      });
      _syncPreferencesToFirestore();
    }
  }

  bool _isChatMuted(String chatId) {
    return ChatSelectionLogic.isChatMuted(_mutedChatExpiries, chatId);
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim().toLowerCase();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<ChatConversation>> _getChatsStream() {
    return DirectChatService.instance.pollChatsStream(widget.currentUserHandle);
  }

  String _formatTimestamp(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0 && now.day == dateTime.day) {
      return DateFormat('hh:mm a').format(dateTime);
    } else if (difference.inDays == 1 || (difference.inDays == 0 && now.day != dateTime.day)) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('E').format(dateTime); // e.g. Mon, Tue
    } else {
      return DateFormat('d MMM').format(dateTime); // e.g. 14 Sep
    }
  }

  // ── Selection Logic ──

  void _toggleSelection(ChatConversation conv) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedChatIds.contains(conv.id)) {
        _selectedChatIds.remove(conv.id);
        _selectedConversations.remove(conv.id);
      } else {
        _selectedChatIds.add(conv.id);
        _selectedConversations[conv.id] = conv;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedChatIds.clear();
      _selectedConversations.clear();
    });
  }

  void _showUndoSnackBar(String message, {required Map<String, dynamic> rollbackSnapshot}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: isDark ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          backgroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 5),
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
          action: SnackBarAction(
            label: 'Undo',
            textColor: isDark ? const Color(0xFF2563EB) : const Color(0xFF60A5FA),
            onPressed: () {
              // 1. Revert UI immediately
              _restorePreferencesState(rollbackSnapshot);
              // 2. Revert backend Firestore
              _syncPreferencesToFirestore();
            },
          ),
        ),
      );
  }

  // ── Top Bar Mixed-Selection Actions ──

  bool get _shouldPinMixed => ChatSelectionLogic.shouldPin(
        selectedIds: _selectedChatIds,
        pinnedIds: _pinnedChatIds,
      );

  void _handlePinSelected() {
    HapticFeedback.mediumImpact();
    final selectedCount = _selectedChatIds.length;
    final rollback = _clonePreferencesMap();
    final selectedIds = Set<String>.from(_selectedChatIds);

    if (!_shouldPinMixed) {
      // 100% of selected are already pinned -> Action: UNPIN
      setState(() {
        _pinnedChatIds.removeAll(selectedIds);
        for (final id in selectedIds) {
          _pinnedTimestamps.remove(id);
        }
      });
      _clearSelection();
      _syncPreferencesToFirestore(rollbackSnapshot: rollback);

      _showUndoSnackBar(
        selectedCount == 1 ? 'Chat unpinned' : '$selectedCount chats unpinned',
        rollbackSnapshot: rollback,
      );
    } else {
      // At least one selected chat is NOT pinned -> Action: PIN ALL
      // Pin limit formula: count ONLY the chats in selection that are NOT already pinned
      final alreadyPinnedInSelection = selectedIds.where(_pinnedChatIds.contains).length;
      final newChatsToBePinned = selectedIds.where((id) => !_pinnedChatIds.contains(id)).length;

      final canPin = ChatSelectionLogic.canPinBatch(
        currentPinnedCount: _pinnedChatIds.length,
        alreadyPinnedInSelection: alreadyPinnedInSelection,
        newChatsToBePinned: newChatsToBePinned,
        maxLimit: 3,
      );

      if (!canPin) {
        HapticFeedback.vibrate();
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: const Text(
                'You can only pin up to 3 chats',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
            ),
          );
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        for (final id in selectedIds) {
          _pinnedChatIds.add(id);
          _pinnedTimestamps[id] = now;
        }
      });
      _clearSelection();
      _syncPreferencesToFirestore(rollbackSnapshot: rollback);

      _showUndoSnackBar(
        selectedCount == 1 ? 'Chat pinned' : '$selectedCount chats pinned',
        rollbackSnapshot: rollback,
      );
    }
  }

  bool get _shouldMuteMixed => ChatSelectionLogic.shouldMute(
        selectedIds: _selectedChatIds,
        mutedExpiries: _mutedChatExpiries,
      );

  void _handleMuteSelected() {
    HapticFeedback.selectionClick();
    final selectedCount = _selectedChatIds.length;
    final selectedIds = Set<String>.from(_selectedChatIds);
    final rollback = _clonePreferencesMap();

    if (!_shouldMuteMixed) {
      // 100% of selected are already muted -> Action: UNMUTE
      setState(() {
        for (final id in selectedIds) {
          _mutedChatExpiries.remove(id);
        }
      });
      _clearSelection();
      _syncPreferencesToFirestore(rollbackSnapshot: rollback);

      _showUndoSnackBar(
        selectedCount == 1 ? 'Chat unmuted' : '$selectedCount chats unmuted',
        rollbackSnapshot: rollback,
      );
    } else {
      // At least one selected chat is NOT muted -> Action: MUTE ALL
      _showMuteDurationPickerSheet(selectedIds, selectedCount, rollback);
    }
  }

  void _showMuteDurationPickerSheet(Set<String> selectedIds, int selectedCount, Map<String, dynamic> rollback) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141414) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF262626) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  selectedCount == 1 ? 'Mute notifications' : 'Mute $selectedCount chats',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Other participants will not see that you muted this chat.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),
                _buildMuteOptionTile(
                  title: '8 hours',
                  duration: const Duration(hours: 8),
                  selectedIds: selectedIds,
                  selectedCount: selectedCount,
                  rollback: rollback,
                  ctx: ctx,
                ),
                _buildMuteOptionTile(
                  title: '1 week',
                  duration: const Duration(days: 7),
                  selectedIds: selectedIds,
                  selectedCount: selectedCount,
                  rollback: rollback,
                  ctx: ctx,
                ),
                _buildMuteOptionTile(
                  title: 'Always',
                  duration: null,
                  selectedIds: selectedIds,
                  selectedCount: selectedCount,
                  rollback: rollback,
                  ctx: ctx,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMuteOptionTile({
    required String title,
    required Duration? duration,
    required Set<String> selectedIds,
    required int selectedCount,
    required Map<String, dynamic> rollback,
    required BuildContext ctx,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pop(ctx);
        final expiry = duration == null
            ? -1
            : DateTime.now().toUtc().add(duration).millisecondsSinceEpoch;

        setState(() {
          for (final id in selectedIds) {
            _mutedChatExpiries[id] = expiry;
          }
        });
        _clearSelection();
        _syncPreferencesToFirestore(rollbackSnapshot: rollback);

        _showUndoSnackBar(
          selectedCount == 1 ? 'Chat muted' : '$selectedCount chats muted',
          rollbackSnapshot: rollback,
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, size: 20, color: isDark ? Colors.white : const Color(0xFF0F172A)),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _shouldArchiveMixed =>
      !_showArchivedView &&
      ChatSelectionLogic.shouldArchive(
        selectedIds: _selectedChatIds,
        archivedIds: _archivedChatIds,
      );

  void _handleArchiveSelected() async {
    HapticFeedback.mediumImpact();
    final selectedCount = _selectedChatIds.length;
    final selectedIds = Set<String>.from(_selectedChatIds);
    final isArchiving = _shouldArchiveMixed;
    final rollback = _clonePreferencesMap();
    _clearSelection();

    // Trigger smooth 250ms simultaneous fade & height collapse
    setState(() {
      _animatingDismissIds.addAll(selectedIds);
    });

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    if (!isArchiving) {
      // Unarchive
      setState(() {
        _archivedChatIds.removeAll(selectedIds);
        for (final id in selectedIds) {
          _archivedTimestamps.remove(id);
        }
        _animatingDismissIds.removeAll(selectedIds);
      });
      _syncPreferencesToFirestore(rollbackSnapshot: rollback);

      _showUndoSnackBar(
        selectedCount == 1 ? 'Chat unarchived' : '$selectedCount chats unarchived',
        rollbackSnapshot: rollback,
      );
    } else {
      // Archive (Flags like pin, mute, fav, lock persist unchanged)
      setState(() {
        _archivedChatIds.addAll(selectedIds);
        for (final id in selectedIds) {
          _archivedTimestamps[id] = now;
        }
        _animatingDismissIds.removeAll(selectedIds);
      });
      _syncPreferencesToFirestore(rollbackSnapshot: rollback);

      _showUndoSnackBar(
        selectedCount == 1 ? '1 chat archived' : '$selectedCount chats archived',
        rollbackSnapshot: rollback,
      );
    }
  }

  void _handleDeleteSelected() {
    final selectedCount = _selectedChatIds.length;
    final selectedIds = Set<String>.from(_selectedChatIds);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          selectedCount == 1 ? 'Delete this chat?' : 'Delete $selectedCount chats?',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Messages will be removed from your device. This will not delete messages for other participants.',
          style: TextStyle(
            color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _clearSelection();

              // Trigger smooth 250ms fade + collapse animation
              setState(() {
                _animatingDismissIds.addAll(selectedIds);
              });

              await Future.delayed(const Duration(milliseconds: 250));

              if (mounted) {
                setState(() {
                  _locallyDeletedChatIds.addAll(selectedIds);
                  _pinnedChatIds.removeAll(selectedIds);
                  _archivedChatIds.removeAll(selectedIds);
                  _animatingDismissIds.removeAll(selectedIds);
                });
                _syncPreferencesToFirestore();

                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        selectedCount == 1 ? 'Chat deleted' : '$selectedCount chats deleted',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      backgroundColor: const Color(0xFF1E293B),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      duration: const Duration(seconds: 3),
                      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
                    ),
                  );
              }
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Overflow 3-Dot Menu Actions ──

  bool get _shouldMarkReadMixed {
    final unreadMap = <String, int>{};
    for (final conv in _latestVisibleConversations) {
      unreadMap[conv.id] = conv.getUnreadCount(widget.currentUserHandle);
    }
    return ChatSelectionLogic.shouldMarkAsRead(
      selectedIds: _selectedChatIds,
      unreadCounts: unreadMap,
      locallyUnreadIds: _locallyUnreadChatIds,
      locallyReadIds: _locallyReadChatIds,
    );
  }

  void _handleMarkReadUnread() {
    HapticFeedback.selectionClick();
    final shouldMarkAsRead = _shouldMarkReadMixed;
    final selectedIds = Set<String>.from(_selectedChatIds);

    final rollbackRead = Set<String>.from(_locallyReadChatIds);
    final rollbackUnread = Set<String>.from(_locallyUnreadChatIds);

    setState(() {
      if (shouldMarkAsRead) {
        _locallyReadChatIds.addAll(selectedIds);
        _locallyUnreadChatIds.removeAll(selectedIds);
        for (final id in selectedIds) {
          DirectChatService.instance.markChatRead(id, _cleanMe).catchError((e) {
            if (mounted) {
              setState(() {
                _locallyReadChatIds.clear();
                _locallyReadChatIds.addAll(rollbackRead);
                _locallyUnreadChatIds.clear();
                _locallyUnreadChatIds.addAll(rollbackUnread);
              });
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  const SnackBar(
                    content: Text("Couldn't update, try again"),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
            return false;
          });
        }
      } else {
        _locallyUnreadChatIds.addAll(selectedIds);
        _locallyReadChatIds.removeAll(selectedIds);
      }
    });

    _clearSelection();
  }

  void _handleSelectAll(List<ChatConversation> visibleConversations) {
    HapticFeedback.mediumImpact();
    setState(() {
      for (final conv in visibleConversations) {
        _selectedChatIds.add(conv.id);
        _selectedConversations[conv.id] = conv;
      }
    });
  }

  bool get _shouldLockMixed => ChatSelectionLogic.shouldLock(
        selectedIds: _selectedChatIds,
        lockedIds: _lockedChatIds,
      );

  void _handleLockSelected() {
    HapticFeedback.mediumImpact();
    final selectedCount = _selectedChatIds.length;
    final selectedIds = Set<String>.from(_selectedChatIds);
    final shouldLock = _shouldLockMixed;
    final rollback = _clonePreferencesMap();

    setState(() {
      if (shouldLock) {
        _lockedChatIds.addAll(selectedIds);
      } else {
        _lockedChatIds.removeAll(selectedIds);
      }
    });
    _clearSelection();
    _syncPreferencesToFirestore(rollbackSnapshot: rollback);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            shouldLock
                ? (selectedCount == 1 ? 'Chat locked with security' : '$selectedCount chats locked with security')
                : (selectedCount == 1 ? 'Chat unlocked' : '$selectedCount chats unlocked'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
        ),
      );
  }

  bool get _shouldFavMixed => ChatSelectionLogic.shouldFavourite(
        selectedIds: _selectedChatIds,
        favouriteIds: _favouriteChatIds,
      );

  void _handleFavouriteSelected() {
    HapticFeedback.selectionClick();
    final selectedCount = _selectedChatIds.length;
    final selectedIds = Set<String>.from(_selectedChatIds);
    final shouldFav = _shouldFavMixed;
    final rollback = _clonePreferencesMap();

    setState(() {
      if (shouldFav) {
        _favouriteChatIds.addAll(selectedIds);
      } else {
        _favouriteChatIds.removeAll(selectedIds);
      }
    });
    _clearSelection();
    _syncPreferencesToFirestore(rollbackSnapshot: rollback);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            shouldFav
                ? (selectedCount == 1 ? 'Added to Favourites' : '$selectedCount chats added to Favourites')
                : (selectedCount == 1 ? 'Removed from Favourites' : '$selectedCount chats removed from Favourites'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
        ),
      );
  }

  void _handleAddToListSelected() {
    final selectedCount = _selectedChatIds.length;
    _clearSelection();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141414) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF262626) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Add to List',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              for (final tag in ['Close Friends', 'Family', 'Neighbors', 'Work'])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.label_outline_rounded, color: isDark ? Colors.white : Colors.black),
                  title: Text(tag, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added $selectedCount chats to "$tag"'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleClearChatSelected() {
    final selectedCount = _selectedChatIds.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          selectedCount == 1 ? 'Clear this chat?' : 'Clear $selectedCount chats?',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Messages in this chat will be cleared from your history, but the chat thread will remain in your list.',
          style: TextStyle(
            color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _clearSelection();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(selectedCount == 1 ? 'Chat cleared' : '$selectedCount chats cleared'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: const Text('Clear Chat', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _handleBlockSelected() {
    final selectedConvs = _selectedConversations.values.toList();
    final partnerHandles = selectedConvs.map((c) => c.getPartnerHandle(widget.currentUserHandle)).toList();
    final selectedCount = partnerHandles.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          selectedCount == 1 ? 'Block @${partnerHandles.first}?' : 'Block $selectedCount contacts?',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Blocked contacts will no longer be able to call you or send you messages.',
          style: TextStyle(
            color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              for (final handle in partnerHandles) {
                await _friendRepo.blockUser(handle);
              }
              _clearSelection();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(selectedCount == 1 ? '@${partnerHandles.first} blocked' : '$selectedCount contacts blocked'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
            child: const Text('Block', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141414) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF262626) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: Color(0xFF3B82F6), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Neighborhood Messaging',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '• Messages are strictly private between you and your neighbor.\n• You can message any friend or neighbor directly.\n• Be respectful and follow community safety guidelines.\n• You can block or report any user at any time from their profile.\n• Long press any chat to select, pin, mute, archive or batch manage.',
                style: TextStyle(
                  color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF475569),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.white : Colors.black,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewChatPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewChatFriendPickerSheet(
        currentUserHandle: widget.currentUserHandle,
        friendRepo: _friendRepo,
      ),
    );
  }

  // ── Build Method ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_isSelectionMode && !_showArchivedView,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSelectionMode) {
          _clearSelection();
        } else if (_showArchivedView) {
          setState(() => _showArchivedView = false);
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: _isSelectionMode
                ? _buildSelectionAppBar(isDark)
                : _buildNormalAppBar(isDark),
          ),
        ),
        floatingActionButton: !_isSelectionMode && !_showArchivedView
            ? PressableScale(
                onTap: _showNewChatPicker,
                child: FloatingActionButton(
                  backgroundColor: isDark ? Colors.white : Colors.black,
                  elevation: 3,
                  shape: const CircleBorder(),
                  onPressed: _showNewChatPicker,
                  child: Icon(Icons.edit_rounded, color: isDark ? Colors.black : Colors.white, size: 22),
                ),
              )
            : null,
        body: Column(
          children: [
            // Search Input (Hidden in selection mode)
            if (!_isSelectionMode) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141414) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 14.5),
                    decoration: InputDecoration(
                      hintText: 'Search conversations',
                      hintStyle: TextStyle(
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8),
                        size: 20,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8), size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),

              // Filter Chips (All, Unread, Favourites)
              if (!_showArchivedView)
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildFilterChip('All', ChatFilter.all, isDark),
                      _buildFilterChip('Unread', ChatFilter.unread, isDark),
                      _buildFilterChip('Favourites', ChatFilter.favourites, isDark),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
            ],

            // Messages Stream List with cacheExtent tuning
            Expanded(
              child: StreamBuilder<List<ChatConversation>>(
                stream: _getChatsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return _buildSkeletonLoading();
                  }

                  if (snapshot.hasError) {
                    debugPrint('Chat stream error: ${snapshot.error}');
                    return _buildErrorState(snapshot.error.toString());
                  }

                  final rawDocs = snapshot.data ?? [];
                  final conversations = <ChatConversation>[];
                  for (final conv in rawDocs) {
                    if (!_locallyDeletedChatIds.contains(conv.id)) {
                      conversations.add(conv);
                    }
                  }

                  // 1. Sort conversations (Pinned first, sorted by pinnedTimestamp descending, then updatedAt descending)
                  conversations.sort((a, b) {
                    final aPinned = _pinnedChatIds.contains(a.id);
                    final bPinned = _pinnedChatIds.contains(b.id);
                    if (aPinned && !bPinned) return -1;
                    if (!aPinned && bPinned) return 1;
                    if (aPinned && bPinned) {
                      final aPinTime = _pinnedTimestamps[a.id] ?? 0;
                      final bPinTime = _pinnedTimestamps[b.id] ?? 0;
                      if (aPinTime != bPinTime) return bPinTime.compareTo(aPinTime);
                    }

                    final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return bTime.compareTo(aTime);
                  });

                  // 2. Filter by Archived state
                  var displayList = conversations.where((conv) {
                    final isArchived = _archivedChatIds.contains(conv.id);
                    return _showArchivedView ? isArchived : !isArchived;
                  }).toList();

                  // 3. Filter by Category tab
                  if (!_showArchivedView && _selectedFilter != ChatFilter.all) {
                    displayList = displayList.where((conv) {
                      if (_selectedFilter == ChatFilter.unread) {
                        if (_locallyUnreadChatIds.contains(conv.id)) return true;
                        if (_locallyReadChatIds.contains(conv.id)) return false;
                        return conv.getUnreadCount(widget.currentUserHandle) > 0;
                      } else if (_selectedFilter == ChatFilter.favourites) {
                        return _favouriteChatIds.contains(conv.id);
                      }
                      return true;
                    }).toList();
                  }

                  // 4. Filter by Search Query
                  if (_searchQuery.isNotEmpty) {
                    displayList = displayList.where((conv) {
                      final partner = conv.getPartnerHandle(widget.currentUserHandle).toLowerCase();
                      final snippet = conv.lastMessage.toLowerCase();
                      return partner.contains(_searchQuery) || snippet.contains(_searchQuery);
                    }).toList();
                  }

                  _latestVisibleConversations = displayList;

                  _checkAutoUnarchive(conversations);

                  if (conversations.isEmpty) {
                    return _buildEmptyState();
                  }

                  if (displayList.isEmpty && _searchQuery.isNotEmpty) {
                    return _buildSearchEmptyState();
                  }

                  if (displayList.isEmpty && _showArchivedView) {
                    return _buildArchivedEmptyState(isDark);
                  }

                  final showArchivedRow = !_showArchivedView && _archivedChatIds.isNotEmpty && _searchQuery.isEmpty;

                  if (displayList.isEmpty && !showArchivedRow) {
                    return _buildEmptyFilterState(isDark);
                  }

                  // Count how many pinned chats are in displayList to place Archived row directly below them
                  final pinnedCount = displayList.where((c) => _pinnedChatIds.contains(c.id)).length;
                  final archivedRowIndex = pinnedCount; // below pinned chats, above regular chats
                  final totalItemCount = displayList.length + (showArchivedRow ? 1 : 0);

                  return ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: totalItemCount,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      thickness: 1,
                      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9),
                      indent: 80,
                    ),
                    itemBuilder: (context, index) {
                      // Archived Header row below pinned chats and above regular chats
                      if (showArchivedRow && index == archivedRowIndex) {
                        return _buildArchivedRow(isDark);
                      }

                      final actualIndex = (showArchivedRow && index > archivedRowIndex) ? index - 1 : index;
                      final conv = displayList[actualIndex];
                      return _buildConversationTile(conv);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App Bars ──

  AppBar _buildNormalAppBar(bool isDark) {
    return AppBar(
      key: const ValueKey('normal_app_bar'),
      backgroundColor: isDark ? Colors.black : Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: _showArchivedView ? 0 : 20,
      leading: _showArchivedView
          ? IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
              onPressed: () => setState(() => _showArchivedView = false),
            )
          : null,
      title: Text(
        _showArchivedView ? 'Archived Chats' : 'Messages',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
          letterSpacing: -0.5,
        ),
      ),
      actions: [
        if (!_showArchivedView) ...[
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: 'Help',
            icon: Icon(
              Icons.help_outline_rounded,
              color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
              size: 22,
            ),
            onPressed: _showHelpDialog,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: 'New Message',
            icon: Icon(
              Icons.edit_note_rounded,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              size: 26,
            ),
            onPressed: _showNewChatPicker,
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  AppBar _buildSelectionAppBar(bool isDark) {
    final selectedCount = _selectedChatIds.length;
    final isSingle = selectedCount == 1;

    final shouldPin = _shouldPinMixed;
    final shouldMute = _shouldMuteMixed;
    final shouldArchive = _shouldArchiveMixed;

    return AppBar(
      key: const ValueKey('selection_app_bar'),
      backgroundColor: isDark ? const Color(0xFF141414) : const Color(0xFFF8FAFC),
      elevation: 2,
      scrolledUnderElevation: 2,
      leading: IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        tooltip: 'Close selection',
        icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
        onPressed: _clearSelection,
      ),
      titleSpacing: 0,
      title: Semantics(
        liveRegion: true,
        label: '$selectedCount selected',
        child: Text(
          '$selectedCount',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      ),
      actions: [
        // 1. Pin / Unpin (Mixed rule: Pin if any unpinned, Unpin if 100% pinned)
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: shouldPin
              ? (isSingle ? 'Pin chat' : 'Pin $selectedCount chats')
              : (isSingle ? 'Unpin chat' : 'Unpin $selectedCount chats'),
          icon: Icon(
            shouldPin ? Icons.push_pin_outlined : Icons.push_pin_rounded,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            size: 22,
          ),
          onPressed: _handlePinSelected,
        ),

        // 2. Delete
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: isSingle ? 'Delete chat' : 'Delete $selectedCount chats',
          icon: Icon(
            Icons.delete_outline_rounded,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            size: 22,
          ),
          onPressed: _handleDeleteSelected,
        ),

        // 3. Mute / Unmute (Mixed rule: Mute if any unmuted, Unmute if 100% muted)
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: shouldMute
              ? (isSingle ? 'Mute chat' : 'Mute $selectedCount chats')
              : (isSingle ? 'Unmute chat' : 'Unmute $selectedCount chats'),
          icon: Icon(
            shouldMute ? Icons.volume_off_outlined : Icons.volume_up_outlined,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            size: 22,
          ),
          onPressed: _handleMuteSelected,
        ),

        // 4. Archive / Unarchive (Mixed rule: Archive if any unarchived, Unarchive if 100% archived)
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: shouldArchive
              ? (isSingle ? 'Archive chat' : 'Archive $selectedCount chats')
              : (isSingle ? 'Unarchive chat' : 'Unarchive $selectedCount chats'),
          icon: Icon(
            shouldArchive ? Icons.archive_rounded : Icons.unarchive_rounded,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            size: 22,
          ),
          onPressed: _handleArchiveSelected,
        ),

        // 5. Overflow 3-Dot (⋮) Menu
        PopupMenuButton<String>(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(
            Icons.more_vert_rounded,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            size: 22,
          ),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (val) {
            if (val == 'mark_read_unread') {
              _handleMarkReadUnread();
            } else if (val == 'select_all') {
              _handleSelectAll(_latestVisibleConversations);
            } else if (val == 'lock_chat') {
              _handleLockSelected();
            } else if (val == 'favourite') {
              _handleFavouriteSelected();
            } else if (val == 'add_to_list') {
              _handleAddToListSelected();
            } else if (val == 'clear_chat') {
              _handleClearChatSelected();
            } else if (val == 'block') {
              _handleBlockSelected();
            }
          },
          itemBuilder: (ctx) {
            final shouldMarkRead = _shouldMarkReadMixed;
            final shouldFav = _shouldFavMixed;
            final shouldLock = _shouldLockMixed;

            return [
              PopupMenuItem(
                value: 'mark_read_unread',
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  shouldMarkRead ? 'Mark as read' : 'Mark as unread',
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 14.5),
                ),
              ),
              PopupMenuItem(
                value: 'select_all',
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'Select all',
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 14.5),
                ),
              ),
              PopupMenuItem(
                value: 'lock_chat',
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  shouldLock ? 'Lock chat' : 'Unlock chat',
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 14.5),
                ),
              ),
              PopupMenuItem(
                value: 'favourite',
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  shouldFav ? 'Add to Favourites' : 'Remove from Favourites',
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 14.5),
                ),
              ),
              PopupMenuItem(
                value: 'add_to_list',
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'Add to list',
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 14.5),
                ),
              ),
              PopupMenuItem(
                value: 'clear_chat',
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'Clear chat',
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 14.5),
                ),
              ),
              PopupMenuItem(
                value: 'block',
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: const Text(
                  'Block',
                  style: TextStyle(color: Color(0xFFEF4444), fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
            ];
          },
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  // ── Conversation Tile ──

  Widget _buildConversationTile(ChatConversation conv) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final partner = conv.getPartnerHandle(widget.currentUserHandle);
    final cleanHandle = partner.replaceAll('@', '');

    final isSelected = _selectedChatIds.contains(conv.id);
    final isPinned = _pinnedChatIds.contains(conv.id);
    final isMuted = _isChatMuted(conv.id);
    final isFav = _favouriteChatIds.contains(conv.id);
    final isLocked = _lockedChatIds.contains(conv.id);
    final isDismissing = _animatingDismissIds.contains(conv.id);

    final rawUnread = conv.getUnreadCount(widget.currentUserHandle);
    final isLocallyRead = _locallyReadChatIds.contains(conv.id);
    final isLocallyUnread = _locallyUnreadChatIds.contains(conv.id);
    final int unreadCount = isLocallyRead ? 0 : (isLocallyUnread ? (rawUnread > 0 ? rawUnread : 1) : rawUnread);
    final hasUnread = unreadCount > 0;
    final timeStr = _formatTimestamp(conv.updatedAt);

    // Selected item background color (WhatsApp-style soft green tint in light, dark green tint in dark)
    final Color itemBgColor;
    if (isSelected) {
      itemBgColor = isDark ? const Color(0xFF132A1C) : const Color(0xFFE8F5E9);
    } else if (hasUnread) {
      itemBgColor = isDark ? const Color(0xFF141414) : const Color(0xFFEFF6FF);
    } else {
      itemBgColor = isDark ? Colors.black : Colors.white;
    }

    return RepaintBoundary(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Container(
          height: isDismissing ? 0 : null,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            opacity: isDismissing ? 0.0 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              color: itemBgColor,
                  child: InkWell(
                    onLongPress: () {
                      _toggleSelection(conv);
                    },
                    onTap: () {
                      if (_isSelectionMode) {
                        _toggleSelection(conv);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PersonalChatScreen(
                              currentUserHandle: widget.currentUserHandle,
                              partnerHandle: cleanHandle,
                            ),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Avatar to Checkmark scale 1.0 -> 0.9 + checkmark fade+scale-in 220ms Curves.easeOutCubic
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedScale(
                                scale: isSelected ? 0.90 : 1.0,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: UserAvatar(
                                  handle: cleanHandle,
                                  size: 50,
                                  fontSize: 18,
                                  showOnlineBadge: !isSelected,
                                ),
                              ),
                              AnimatedScale(
                                scale: isSelected ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  opacity: isSelected ? 1.0 : 0.0,
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),

                          // Handle & Last Message Snippet
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              '@$cleanHandle',
                                              style: TextStyle(
                                                fontSize: 15.5,
                                                fontWeight: (hasUnread || isSelected) ? FontWeight.w800 : FontWeight.w700,
                                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                letterSpacing: -0.2,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          AnimatedScale(
                                            scale: isFav ? 1.0 : 0.0,
                                            duration: const Duration(milliseconds: 150),
                                            curve: Curves.easeOut,
                                            child: const Padding(
                                              padding: EdgeInsets.only(left: 4.0),
                                              child: Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                                            ),
                                          ),
                                          AnimatedScale(
                                            scale: isLocked ? 1.0 : 0.0,
                                            duration: const Duration(milliseconds: 150),
                                            curve: Curves.easeOut,
                                            child: Padding(
                                              padding: const EdgeInsets.only(left: 4.0),
                                              child: Icon(Icons.lock_rounded, size: 13, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AnimatedScale(
                                          scale: isPinned ? 1.0 : 0.0,
                                          duration: const Duration(milliseconds: 150),
                                          curve: Curves.easeOut,
                                          child: Padding(
                                            padding: const EdgeInsets.only(right: 6.0),
                                            child: Transform.rotate(
                                              angle: 0.5,
                                              child: Icon(
                                                Icons.push_pin_rounded,
                                                size: 14,
                                                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ),
                                        ),
                                        AnimatedScale(
                                          scale: isMuted ? 1.0 : 0.0,
                                          duration: const Duration(milliseconds: 150),
                                          curve: Curves.easeOut,
                                          child: Padding(
                                            padding: const EdgeInsets.only(right: 6.0),
                                            child: Icon(
                                              Icons.volume_off_rounded,
                                              size: 14,
                                              color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ),
                                        if (timeStr.isNotEmpty)
                                          Text(
                                            timeStr,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                                              color: hasUnread
                                                  ? const Color(0xFF2563EB)
                                                  : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8)),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Expanded(
                                      child: conv.isPartnerTyping(widget.currentUserHandle)
                                          ? const Text(
                                              'typing...',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                fontStyle: FontStyle.italic,
                                                color: Color(0xFF16A34A),
                                                height: 1.3,
                                              ),
                                            )
                                          : Text(
                                              conv.lastMessage.isNotEmpty
                                                  ? conv.lastMessage
                                                  : 'Drafted message',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                                                color: hasUnread
                                                    ? (isDark ? Colors.white : const Color(0xFF1E293B))
                                                    : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B)),
                                                height: 1.3,
                                              ),
                                            ),
                                    ),
                                    AnimatedScale(
                                      scale: hasUnread ? 1.0 : 0.0,
                                      duration: const Duration(milliseconds: 150),
                                      curve: Curves.easeOut,
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 8.0),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF2563EB),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            '$unreadCount',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }

  // ── Auto-Unarchive on Incoming Message ──

  void _checkAutoUnarchive(List<ChatConversation> conversations) {
    if (_keepChatsArchived) return;
    final toUnarchive = <String>{};
    for (final conv in conversations) {
      if (_archivedChatIds.contains(conv.id)) {
        final lastMsgTime = conv.updatedAt;
        final archivedTimeEpoch = _archivedTimestamps[conv.id];
        final archivedTime = archivedTimeEpoch != null
            ? DateTime.fromMillisecondsSinceEpoch(archivedTimeEpoch)
            : null;
        if (ChatSelectionLogic.shouldAutoUnarchive(
          isArchived: true,
          keepChatsArchived: _keepChatsArchived,
          lastMessageTime: lastMsgTime,
          archivedAt: archivedTime,
        )) {
          toUnarchive.add(conv.id);
        }
      }
    }

    if (toUnarchive.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _archivedChatIds.removeAll(toUnarchive);
          for (final id in toUnarchive) {
            _archivedTimestamps.remove(id);
          }
        });
        _syncPreferencesToFirestore();
      });
    }
  }

  // ── Archived Row ──

  Widget _buildArchivedRow(bool isDark) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _showArchivedView = true;
          _clearSelection();
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.archive_rounded, size: 22, color: isDark ? Colors.white : const Color(0xFF0F172A)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Archived',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              key: ValueKey('archived_count_${_archivedChatIds.length}'),
              tween: Tween<double>(begin: 1.08, end: 1.0),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              builder: (context, scale, child) => Transform.scale(
                scale: scale,
                child: child,
              ),
              child: Text(
                '${_archivedChatIds.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  // ── Filter Chip ──

  Widget _buildFilterChip(String label, ChatFilter filter, bool isDark) {
    final isSelected = _selectedFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedFilter = filter);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0)),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected
                  ? (isDark ? Colors.black : Colors.white)
                  : (isDark ? Colors.white : const Color(0xFF0F172A)),
            ),
          ),
        ),
      ),
    );
  }

  // ── Skeleton Loading ──

  Widget _buildSkeletonLoading() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 7,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFFF1F5F9),
        indent: 80,
      ),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 120,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        Container(
                          width: 45,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Empty States ──

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                shape: BoxShape.circle,
                border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 36,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No conversations yet',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Connect and chat with neighbors and friends in Vadodara.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Start a Conversation', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: _showNewChatPicker,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchivedEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.archive_outlined, size: 48, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8)),
            const SizedBox(height: 14),
            Text(
              'No archived chats',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Chats you archive will be stored here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFilterState(bool isDark) {
    final filterName = _selectedFilter == ChatFilter.unread ? 'unread' : 'favourite';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _selectedFilter == ChatFilter.unread ? Icons.mark_chat_read_outlined : Icons.star_outline_rounded,
              size: 44,
              color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            Text(
              'No $filterName chats',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              'No conversations for "$_searchQuery"',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Check your spelling or start a new chat with a friend.',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _searchController.clear(),
              child: Text(
                'Clear search',
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text(
              'Could not load messages',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Please check your network connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                shape: const StadiumBorder(),
              ),
              onPressed: () => setState(() {}),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom Sheet to pick a friend and initiate a 1-on-1 chat
class _NewChatFriendPickerSheet extends StatefulWidget {
  final String currentUserHandle;
  final FriendRepository friendRepo;

  const _NewChatFriendPickerSheet({
    required this.currentUserHandle,
    required this.friendRepo,
  });

  @override
  State<_NewChatFriendPickerSheet> createState() => _NewChatFriendPickerSheetState();
}

class _NewChatFriendPickerSheetState extends State<_NewChatFriendPickerSheet> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      setState(() => _filter = _filterController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle & Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF262626) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'New Message',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: Icon(Icons.close_rounded, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Search Friend Filter
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextField(
                      controller: _filterController,
                      style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'Search friends...',
                        hintStyle: TextStyle(color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8), fontSize: 14),
                        prefixIcon: Icon(Icons.search_rounded, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8), size: 18),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9)),

            // Friends List Stream
            Expanded(
              child: StreamBuilder<List<Friendship>>(
                stream: widget.friendRepo.getFriendsList(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.black));
                  }

                  final friendships = snapshot.data ?? [];
                  final friendHandles = friendships
                      .map((f) => f.getOtherUser(widget.currentUserHandle))
                      .where((h) => h.toLowerCase().contains(_filter))
                      .toList();

                  if (friendHandles.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 40, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8)),
                            const SizedBox(height: 10),
                            Text(
                              _filter.isEmpty
                                  ? 'No friends yet'
                                  : 'No friends matching "$_filter"',
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add neighbors as friends from the feed to start chatting!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B), fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: friendHandles.length,
                    separatorBuilder: (context, index) => Divider(height: 1, indent: 68, color: isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final handle = friendHandles[index];
                      return ListTile(
                        tileColor: isDark ? const Color(0xFF141414) : Colors.white,
                        leading: UserAvatar(handle: handle, size: 42, fontSize: 16),
                        title: Text(
                          '@$handle',
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          'Vadodara Neighbor',
                          style: TextStyle(color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B), fontSize: 12),
                        ),
                        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFFCBD5E1)),
                        onTap: () {
                          Navigator.pop(context); // Close sheet
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PersonalChatScreen(
                                currentUserHandle: widget.currentUserHandle,
                                partnerHandle: handle,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
