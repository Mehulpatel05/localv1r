import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/chat_conversation_model.dart';
import '../../models/friendship_model.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/name_cache_service.dart';
import '../../core/services/badge_cache_service.dart';
import '../../core/widgets/verified_badge.dart';
import '../../core/widgets/sliding_category_tab_bar.dart';
import '../../services/chat_preferences_service.dart';
import '../../services/direct_chat_service.dart';
import '../../services/friend_repository.dart';
import '../../theme/app_colors.dart';
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

  ChatFilter _selectedFilter = ChatFilter.all;
  bool _showArchivedView = false;

  final Set<String> _selectedChatIds = {};
  final Map<String, ChatConversation> _selectedConversations = {};
  List<ChatConversation> _latestVisibleConversations = [];

  bool get _isSelectionMode => _selectedChatIds.isNotEmpty;

  final Set<String> _animatingDismissIds = {};
  final Map<String, String> _dismissDirections = {};
  int _pinBounceTrigger = 0;
  bool _isNewChatSheetOpen = false;
  bool _isFabPressed = false;
  Map<String, int> _staggerDelays = {};
  String? _scalingTileId;
  double _archivedTransitionDirection = 1.0;
  bool _lastTransitionWasArchived = false;

  Set<String> _pinnedChatIds = {};
  Map<String, int> _pinnedTimestamps = {};
  Map<String, int?> _mutedChatExpiries = {};
  Set<String> _archivedChatIds = {};
  Map<String, int> _archivedTimestamps = {};
  bool _keepChatsArchived = false;
  Set<String> _favouriteChatIds = {};
  Set<String> _lockedChatIds = {};
  Set<String> _locallyDeletedChatIds = {};
  final Set<String> _locallyReadChatIds = {};
  final Set<String> _locallyUnreadChatIds = {};
  late final Stream<List<ChatConversation>> _chatsStream;

  String get _cleanMe => widget.currentUserHandle.replaceAll('@', '').trim();

  @override
  void initState() {
    super.initState();
    _chatsStream = DirectChatService.instance.pollChatsStream(widget.currentUserHandle).asBroadcastStream();
    _friendRepo = FriendRepository()..currentUserHandle = widget.currentUserHandle;
    _searchController.addListener(_onSearchChanged);
    _loadPreferences();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cleanExpiredMutesLazy();
  }

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

  final Map<String, int> _partnerTypingTimestamps = {};

  bool _isPartnerTypingFresh(ChatConversation conv) {
    final isTyping = conv.isPartnerTyping(widget.currentUserHandle);
    if (!isTyping) {
      _partnerTypingTimestamps.remove(conv.id);
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastSeen = _partnerTypingTimestamps[conv.id];
    if (lastSeen == null) {
      _partnerTypingTimestamps[conv.id] = now;
      return true;
    }
    if (now - lastSeen > 5000) {
      return false;
    }
    return true;
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
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
    return _chatsStream;
  }

  String _formatTimestamp(DateTime? dateTime) {
    if (dateTime == null) return '';
    final localDt = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    final now = DateTime.now();

    final isSameDay = now.year == localDt.year && now.month == localDt.month && now.day == localDt.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == localDt.year && yesterday.month == localDt.month && yesterday.day == localDt.day;

    if (isSameDay) {
      return DateFormat('hh:mm a').format(localDt);
    } else if (isYesterday) {
      return 'Yesterday';
    } else {
      final difference = now.difference(localDt);
      if (difference.inDays < 7) {
        return DateFormat('E').format(localDt);
      } else {
        return DateFormat('d MMM').format(localDt);
      }
    }
  }

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
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          backgroundColor: AppColors.textPrimary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 5),
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppColors.primarySoft,
            onPressed: () {
              _restorePreferencesState(rollbackSnapshot);
              _syncPreferencesToFirestore();
            },
          ),
        ),
      );
  }

  bool get _shouldPinMixed => ChatSelectionLogic.shouldPin(
        selectedIds: _selectedChatIds,
        pinnedIds: _pinnedChatIds,
      );

  void _handlePinSelected() async {
    HapticFeedback.mediumImpact();
    final selectedCount = _selectedChatIds.length;
    final rollback = _clonePreferencesMap();
    final selectedIds = Set<String>.from(_selectedChatIds);

    if (!_shouldPinMixed) {
      setState(() {
        _pinnedChatIds.removeAll(selectedIds);
        for (final id in selectedIds) {
          _pinnedTimestamps.remove(id);
        }
      });
      _clearSelection();
      _showUndoSnackBar(
        selectedCount == 1 ? 'Chat unpinned' : '$selectedCount chats unpinned',
        rollbackSnapshot: rollback,
      );

      final res = await ChatPreferencesService.instance.pinChats(_cleanMe, selectedIds.toList(), pin: false);
      if (res != null && mounted) {
        setState(() {
          _pinnedChatIds = Set<String>.from((res['pinnedChatIds'] as List? ?? []).map((e) => e.toString()));
          _pinnedTimestamps = Map<String, int>.from(
            (res['pinnedTimestamps'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
          );
        });
      }
    } else {
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
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
            ),
          );
        return;
      }

      final optimisticNow = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        for (final id in selectedIds) {
          _pinnedChatIds.add(id);
          _pinnedTimestamps[id] = optimisticNow;
        }
      });
      _clearSelection();
      _showUndoSnackBar(
        selectedCount == 1 ? 'Chat pinned' : '$selectedCount chats pinned',
        rollbackSnapshot: rollback,
      );

      final res = await ChatPreferencesService.instance.pinChats(_cleanMe, selectedIds.toList(), pin: true);
      if (res != null && mounted) {
        setState(() {
          _pinnedChatIds = Set<String>.from((res['pinnedChatIds'] as List? ?? []).map((e) => e.toString()));
          _pinnedTimestamps = Map<String, int>.from(
            (res['pinnedTimestamps'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
          );
        });
      }
    }
  }

  bool get _shouldMuteMixed => ChatSelectionLogic.shouldMute(
        selectedIds: _selectedChatIds,
        mutedExpiries: _mutedChatExpiries,
      );

  void _handleMuteSelected() async {
    HapticFeedback.selectionClick();
    final selectedCount = _selectedChatIds.length;
    final selectedIds = Set<String>.from(_selectedChatIds);
    final rollback = _clonePreferencesMap();

    if (!_shouldMuteMixed) {
      setState(() {
        for (final id in selectedIds) {
          _mutedChatExpiries.remove(id);
        }
      });
      _clearSelection();
      _showUndoSnackBar(
        selectedCount == 1 ? 'Chat unmuted' : '$selectedCount chats unmuted',
        rollbackSnapshot: rollback,
      );

      final res = await ChatPreferencesService.instance.muteChats(_cleanMe, selectedIds.toList(), mute: false);
      if (res != null && mounted) {
        setState(() {
          _mutedChatExpiries = Map<String, int?>.from(
            (res['mutedChatExpiries'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num?)?.toInt())),
          );
        });
      }
    } else {
      _showMuteDurationPickerSheet(selectedIds, selectedCount, rollback);
    }
  }

  void _showMuteDurationPickerSheet(Set<String> selectedIds, int selectedCount, Map<String, dynamic> rollback) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  selectedCount == 1 ? 'Mute notifications' : 'Mute $selectedCount chats',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Other participants will not see that you muted this chat.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                _buildMuteOptionTile(
                  title: '8 hours',
                  duration: const Duration(hours: 8),
                  durationEnum: '8h',
                  selectedIds: selectedIds,
                  selectedCount: selectedCount,
                  rollback: rollback,
                  ctx: ctx,
                ),
                _buildMuteOptionTile(
                  title: '1 week',
                  duration: const Duration(days: 7),
                  durationEnum: '1w',
                  selectedIds: selectedIds,
                  selectedCount: selectedCount,
                  rollback: rollback,
                  ctx: ctx,
                ),
                _buildMuteOptionTile(
                  title: 'Always',
                  duration: null,
                  durationEnum: 'always',
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
    required String durationEnum,
    required Set<String> selectedIds,
    required int selectedCount,
    required Map<String, dynamic> rollback,
    required BuildContext ctx,
  }) {
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        Navigator.pop(ctx);
        final optimisticExpiry = duration == null
            ? -1
            : DateTime.now().toUtc().add(duration).millisecondsSinceEpoch;

        setState(() {
          for (final id in selectedIds) {
            _mutedChatExpiries[id] = optimisticExpiry;
          }
        });
        _clearSelection();
        _showUndoSnackBar(
          selectedCount == 1 ? 'Chat muted' : '$selectedCount chats muted',
          rollbackSnapshot: rollback,
        );

        final res = await ChatPreferencesService.instance.muteChats(
          _cleanMe,
          selectedIds.toList(),
          mute: true,
          duration: duration,
          durationEnum: durationEnum,
        );
        if (res != null && mounted) {
          setState(() {
            _mutedChatExpiries = Map<String, int?>.from(
              (res['mutedChatExpiries'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num?)?.toInt())),
            );
          });
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.access_time_rounded, size: 20, color: AppColors.textPrimary),
            const SizedBox(width: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
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

    setState(() {
      for (final id in selectedIds) {
        _dismissDirections[id] = 'right';
      }
      _animatingDismissIds.addAll(selectedIds);
    });

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    if (!isArchiving) {
      setState(() {
        _archivedChatIds.removeAll(selectedIds);
        for (final id in selectedIds) {
          _archivedTimestamps.remove(id);
          _dismissDirections.remove(id);
        }
        _animatingDismissIds.removeAll(selectedIds);
      });
      _syncPreferencesToFirestore(rollbackSnapshot: rollback);

      _showUndoSnackBar(
        selectedCount == 1 ? 'Chat unarchived' : '$selectedCount chats unarchived',
        rollbackSnapshot: rollback,
      );
    } else {
      setState(() {
        _archivedChatIds.addAll(selectedIds);
        for (final id in selectedIds) {
          _archivedTimestamps[id] = now;
          _dismissDirections.remove(id);
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
    final rollback = _clonePreferencesMap();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Delete Dialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim, secondaryAnim) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          selectedCount == 1 ? 'Delete this chat?' : 'Delete $selectedCount chats?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: const Text(
          'Messages will be removed from your device. This will not delete messages for other participants.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _clearSelection();

              setState(() {
                for (final id in selectedIds) {
                  _dismissDirections[id] = 'left';
                }
                _animatingDismissIds.addAll(selectedIds);
              });

              await Future.delayed(const Duration(milliseconds: 250));

              if (mounted) {
                setState(() {
                  _locallyDeletedChatIds.addAll(selectedIds);
                  _pinnedChatIds.removeAll(selectedIds);
                  _archivedChatIds.removeAll(selectedIds);
                  _animatingDismissIds.removeAll(selectedIds);
                  for (final id in selectedIds) {
                    _dismissDirections.remove(id);
                  }
                });
                _syncPreferencesToFirestore(rollbackSnapshot: rollback);

                _showUndoSnackBar(
                  selectedCount == 1 ? 'Chat deleted' : '$selectedCount chats deleted',
                  rollbackSnapshot: rollback,
                );
              }
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

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

  void _handleSelectAll(List<ChatConversation> visibleConversations) async {
    HapticFeedback.mediumImpact();
    final delays = <String, int>{};
    for (int i = 0; i < visibleConversations.length; i++) {
      delays[visibleConversations[i].id] = i * 30;
    }

    setState(() {
      _staggerDelays = delays;
      for (final conv in visibleConversations) {
        _selectedChatIds.add(conv.id);
        _selectedConversations[conv.id] = conv;
      }
    });

    final totalStaggerMs = (visibleConversations.length * 30) + 250;
    Future.delayed(Duration(milliseconds: totalStaggerMs), () {
      if (mounted) {
        setState(() {
          _staggerDelays.clear();
        });
      }
    });

    try {
      final allIds = await DirectChatService.instance.getChatIds(
        userHandle: _cleanMe,
        query: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      if (allIds.isNotEmpty && mounted) {
        final priorCount = _selectedChatIds.length;
        setState(() {
          _selectedChatIds.addAll(allIds);
        });
        if (_selectedChatIds.length > priorCount && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Selected all ${_selectedChatIds.length} conversations'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[ChatListScreen] Query-bound select all error: $e');
    }
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
          backgroundColor: AppColors.textPrimary,
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
          backgroundColor: AppColors.textPrimary,
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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Add to List',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              for (final tag in ['Close Friends', 'Family', 'Neighbors', 'Work'])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.label_outline_rounded, color: AppColors.textPrimary),
                  title: Text(tag, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          selectedCount == 1 ? 'Clear this chat?' : 'Clear $selectedCount chats?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: const Text(
          'Messages in this chat will be cleared from your history, but the chat thread will remain in your list.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          selectedCount == 1 ? 'Block ${getDisplayName(partnerHandles.first)}?' : 'Block $selectedCount contacts?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: const Text(
          'Blocked contacts will no longer be able to call you or send you messages.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
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
                    content: Text(selectedCount == 1 ? '${partnerHandles.first.displayHandle} blocked' : '$selectedCount contacts blocked'),
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
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Help Dialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim, secondaryAnim) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text(
              'Neighborhood Messaging',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        content: const Text(
          '• Messages are strictly private between you and your neighbor.\n• You can message any friend or neighbor directly.\n• Be respectful and follow community safety guidelines.\n• You can block or report any user at any time from their profile.\n• Long press any chat to select, pin, mute, archive or batch manage.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _showNewChatPicker() async {
    setState(() => _isNewChatSheetOpen = true);
    final selectedHandle = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 250),
        reverseDuration: Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      builder: (ctx) => _NewChatFriendPickerSheet(
        currentUserHandle: widget.currentUserHandle,
        friendRepo: _friendRepo,
      ),
    );

    if (mounted) {
      setState(() => _isNewChatSheetOpen = false);
    }

    if (selectedHandle != null && mounted) {
      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          pageBuilder: (context, animation, secondaryAnimation) => HeroMode(
            enabled: false,
            child: PersonalChatScreen(
              currentUserHandle: widget.currentUserHandle,
              partnerHandle: selectedHandle,
            ),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
            final scale = Tween<double>(begin: 0.96, end: 1.0).animate(curved);
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: scale,
                child: child,
              ),
            );
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSelectionMode && !_showArchivedView,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSelectionMode) {
          _clearSelection();
        } else if (_showArchivedView) {
          setState(() {
            _archivedTransitionDirection = -1.0;
            _lastTransitionWasArchived = true;
            _showArchivedView = false;
            _clearSelection();
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
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
                ? _buildSelectionAppBar()
                : _buildNormalAppBar(),
          ),
        ),
        floatingActionButton: !_isSelectionMode && !_showArchivedView
            ? AnimatedScale(
                scale: _isFabPressed ? 0.90 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: FloatingActionButton(
                  backgroundColor: AppColors.primary,
                  elevation: 3,
                  shape: const CircleBorder(),
                  onPressed: () {
                    setState(() => _isFabPressed = true);
                    Future.delayed(const Duration(milliseconds: 150), () {
                      if (mounted) setState(() => _isFabPressed = false);
                    });
                    if (_isNewChatSheetOpen) {
                      Navigator.pop(context);
                    } else {
                      _showNewChatPicker();
                    }
                  },
                  child: AnimatedRotation(
                    turns: _isNewChatSheetOpen ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        _isNewChatSheetOpen ? Icons.close_rounded : Icons.edit_rounded,
                        key: ValueKey('fab_icon_$_isNewChatSheetOpen'),
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        body: Column(
          children: [
            if (!_isSelectionMode) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.divider, width: 1.0),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                    decoration: InputDecoration(
                      hintText: 'Search conversations',
                      hintStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                      suffixIcon: AnimatedOpacity(
                        opacity: _searchController.text.isNotEmpty ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 100),
                        child: IgnorePointer(
                          ignoring: _searchController.text.isEmpty,
                          child: IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppColors.textMuted,
                              size: 18,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                        ),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
              if (!_showArchivedView)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: SizedBox(
                    height: 42,
                    child: SlidingCategoryTabBar(
                      categories: const ['All', 'Unread', 'Favourites'],
                      selectedIndex: _selectedFilter.index,
                      onSelected: (index) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _lastTransitionWasArchived = false;
                          _selectedFilter = ChatFilter.values[index];
                        });
                      },
                    ),
                  ),
                ),
            ],
            Expanded(
              child: StreamBuilder<List<ChatConversation>>(
                stream: _getChatsStream(),
                initialData: DirectChatService.instance.lastKnownChats,
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

                  var displayList = conversations.where((conv) {
                    final isArchived = _archivedChatIds.contains(conv.id);
                    return _showArchivedView ? isArchived : !isArchived;
                  }).toList();

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

                  if (_searchQuery.isNotEmpty) {
                    displayList = displayList.where((conv) {
                      final partner = conv.getPartnerHandle(widget.currentUserHandle).toLowerCase();
                      final partnerName = NameCacheService.instance.getDisplayName(partner, fallback: conv.partnerDisplayName).toLowerCase();
                      final snippet = conv.lastMessage.toLowerCase();
                      return partner.contains(_searchQuery) ||
                          partnerName.contains(_searchQuery) ||
                          snippet.contains(_searchQuery);
                    }).toList();
                  }

                  _latestVisibleConversations = displayList;

                  _checkAutoUnarchive(conversations);

                  Widget listBody;
                  if (conversations.isEmpty) {
                    listBody = _buildEmptyState();
                  } else if (displayList.isEmpty && _searchQuery.isNotEmpty) {
                    listBody = _buildSearchEmptyState();
                  } else if (displayList.isEmpty && _showArchivedView) {
                    listBody = _buildArchivedEmptyState();
                  } else {
                    final showArchivedRow = !_showArchivedView && _archivedChatIds.isNotEmpty && _searchQuery.isEmpty;

                    if (displayList.isEmpty && !showArchivedRow) {
                      listBody = _buildEmptyFilterState();
                    } else {
                      final pinnedCount = displayList.where((c) => _pinnedChatIds.contains(c.id)).length;
                      final archivedRowIndex = pinnedCount;
                      final totalItemCount = displayList.length + (showArchivedRow ? 1 : 0);

                      listBody = ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.only(bottom: 88 + MediaQuery.paddingOf(context).bottom),
                        itemCount: totalItemCount,
                        separatorBuilder: (context, index) => const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.divider,
                          indent: 80,
                        ),
                        itemBuilder: (context, index) {
                          if (showArchivedRow && index == archivedRowIndex) {
                            return _buildArchivedRow();
                          }

                          final actualIndex = (showArchivedRow && index > archivedRowIndex) ? index - 1 : index;
                          final conv = displayList[actualIndex];
                          return _buildConversationTile(conv);
                        },
                      );
                    }
                  }

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      final isArchivedNav = _lastTransitionWasArchived;
                      final slideOffset = isArchivedNav
                          ? Offset(_archivedTransitionDirection * 0.3, 0.0)
                          : const Offset(0.0, 0.03);

                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: slideOffset,
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                        child: FadeTransition(
                          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey('list_filter_${_selectedFilter}_archived_${_showArchivedView}_empty_${displayList.isEmpty}'),
                      child: listBody,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      key: const ValueKey('normal_app_bar'),
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: _showArchivedView ? 0 : 20,
      leading: _showArchivedView
          ? IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
              onPressed: () {
                setState(() {
                  _archivedTransitionDirection = -1.0;
                  _lastTransitionWasArchived = true;
                  _showArchivedView = false;
                  _clearSelection();
                });
              },
            )
          : null,
      title: Text(
        _showArchivedView ? 'Archived Chats' : 'Messages',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
      actions: [
        if (!_showArchivedView) ...[
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: 'Help',
            icon: const Icon(
              Icons.help_outline_rounded,
              color: AppColors.textMuted,
              size: 22,
            ),
            onPressed: _showHelpDialog,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: 'New Message',
            icon: const Icon(
              Icons.edit_note_rounded,
              color: AppColors.textPrimary,
              size: 26,
            ),
            onPressed: _showNewChatPicker,
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    final selectedCount = _selectedChatIds.length;
    final isSingle = selectedCount == 1;

    final shouldPin = _shouldPinMixed;
    final shouldMute = _shouldMuteMixed;
    final shouldArchive = _shouldArchiveMixed;

    return AppBar(
      key: const ValueKey('selection_app_bar'),
      backgroundColor: AppColors.surface,
      elevation: 2,
      scrolledUnderElevation: 2,
      leading: IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        tooltip: 'Close selection',
        icon: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.25, end: 0.0),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          builder: (context, turns, child) => RotationTransition(
            turns: AlwaysStoppedAnimation(turns),
            child: child,
          ),
          child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
        ),
        onPressed: _clearSelection,
      ),
      titleSpacing: 0,
      title: Semantics(
        liveRegion: true,
        label: '$selectedCount selected',
        child: Text(
          '$selectedCount',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      actions: [
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: shouldPin
              ? (isSingle ? 'Pin chat' : 'Pin $selectedCount chats')
              : (isSingle ? 'Unpin chat' : 'Unpin $selectedCount chats'),
          icon: TweenAnimationBuilder<double>(
            key: ValueKey('pin_bounce_$_pinBounceTrigger'),
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            builder: (context, val, child) {
              final dropY = math.sin(val * math.pi) * 4.0;
              return Transform.translate(
                offset: Offset(0, dropY),
                child: child,
              );
            },
            child: Icon(
              shouldPin ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
          ),
          onPressed: () {
            setState(() => _pinBounceTrigger++);
            _handlePinSelected();
          },
        ),
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: isSingle ? 'Delete chat' : 'Delete $selectedCount chats',
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: AppColors.textPrimary,
            size: 22,
          ),
          onPressed: _handleDeleteSelected,
        ),
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: shouldMute
              ? (isSingle ? 'Mute chat' : 'Mute $selectedCount chats')
              : (isSingle ? 'Unmute chat' : 'Unmute $selectedCount chats'),
          icon: Icon(
            shouldMute ? Icons.volume_off_outlined : Icons.volume_up_outlined,
            color: AppColors.textPrimary,
            size: 22,
          ),
          onPressed: _handleMuteSelected,
        ),
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: shouldArchive
              ? (isSingle ? 'Archive chat' : 'Archive $selectedCount chats')
              : (isSingle ? 'Unarchive chat' : 'Unarchive $selectedCount chats'),
          icon: Icon(
            shouldArchive ? Icons.archive_rounded : Icons.unarchive_rounded,
            color: AppColors.textPrimary,
            size: 22,
          ),
          onPressed: _handleArchiveSelected,
        ),
        PopupMenuButton<String>(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(
            Icons.more_vert_rounded,
            color: AppColors.textPrimary,
            size: 22,
          ),
          color: AppColors.surface,
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
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                ),
              ),
              const PopupMenuItem(
                value: 'select_all',
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'Select all',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                ),
              ),
              PopupMenuItem(
                value: 'lock_chat',
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  shouldLock ? 'Lock chat' : 'Unlock chat',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                ),
              ),
              PopupMenuItem(
                value: 'favourite',
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  shouldFav ? 'Add to Favourites' : 'Remove from Favourites',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                ),
              ),
              const PopupMenuItem(
                value: 'add_to_list',
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'Add to list',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                ),
              ),
              const PopupMenuItem(
                value: 'clear_chat',
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'Clear chat',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                ),
              ),
              const PopupMenuItem(
                value: 'block',
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'Block',
                  style: TextStyle(color: AppColors.error, fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
            ];
          },
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildConversationTile(ChatConversation conv) {
    final partner = conv.getPartnerHandle(widget.currentUserHandle);
    final cleanHandle = partner.replaceAll('@', '');
    final partnerDisplayName = NameCacheService.instance.getDisplayName(
      cleanHandle,
      fallback: conv.partnerDisplayName,
    );

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

    final Color itemBgColor = isSelected ? AppColors.primarySoft : AppColors.surface;
    final dismissDir = _dismissDirections[conv.id] ?? 'right';
    final staggerDelay = _staggerDelays[conv.id] ?? 0;

    return RepaintBoundary(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Container(
          height: isDismissing ? 0 : null,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 250),
            curve: dismissDir == 'right' ? Curves.easeIn : Curves.easeOut,
            offset: isDismissing
                ? (dismissDir == 'right' ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0))
                : Offset.zero,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              opacity: isDismissing ? 0.0 : 1.0,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                scale: _scalingTileId == conv.id ? 0.97 : 1.0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  color: itemBgColor,
                  child: InkWell(
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      setState(() => _scalingTileId = conv.id);
                      Future.delayed(const Duration(milliseconds: 120), () {
                        if (mounted) setState(() => _scalingTileId = null);
                      });
                      _toggleSelection(conv);
                    },
                    onTap: () {
                      if (_isSelectionMode) {
                        _toggleSelection(conv);
                      } else {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            transitionDuration: const Duration(milliseconds: 300),
                            pageBuilder: (_, animation, secondaryAnimation) => PersonalChatScreen(
                              currentUserHandle: widget.currentUserHandle,
                              partnerHandle: cleanHandle,
                            ),
                            transitionsBuilder: (_, animation, _, child) => FadeTransition(
                              opacity: animation,
                              child: child,
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
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedScale(
                                scale: isSelected ? 0.90 : 1.0,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: Hero(
                                  tag: 'chat_avatar_${cleanHandle.toLowerCase()}',
                                  child: UserAvatar(
                                    handle: cleanHandle,
                                    size: 50,
                                    fontSize: 18,
                                    showOnlineBadge: !isSelected,
                                  ),
                                ),
                              ),
                              AnimatedScale(
                                scale: isSelected ? 1.0 : 0.0,
                                duration: Duration(milliseconds: 150 + staggerDelay),
                                curve: Curves.easeOutCubic,
                                child: AnimatedOpacity(
                                  duration: Duration(milliseconds: 150 + staggerDelay),
                                  curve: Curves.easeOutCubic,
                                  opacity: isSelected ? 1.0 : 0.0,
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
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
                                              getDisplayName(cleanHandle, fallback: partnerDisplayName),
                                              style: TextStyle(
                                                fontSize: 15.5,
                                                fontWeight: (hasUnread || isSelected) ? FontWeight.w800 : FontWeight.w700,
                                                color: AppColors.textPrimary,
                                                letterSpacing: -0.2,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Builder(
                                            builder: (context) {
                                              final isPartnerVerified = BadgeCacheService.instance.isUserVerified(cleanHandle);
                                              final partnerBadge = BadgeCacheService.instance.getUserBadge(cleanHandle);
                                              if (isPartnerVerified || (partnerBadge != null && partnerBadge.isNotEmpty)) {
                                                return Padding(
                                                  padding: const EdgeInsets.only(left: 4.0),
                                                  child: VerifiedBadge(
                                                    isVerified: isPartnerVerified,
                                                    badgeText: partnerBadge,
                                                    iconSize: 13,
                                                    fontSize: 8.5,
                                                    compact: true,
                                                  ),
                                                );
                                              }
                                              return const SizedBox.shrink();
                                            },
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
                                            child: const Padding(
                                              padding: EdgeInsets.only(left: 4.0),
                                              child: Icon(Icons.lock_rounded, size: 13, color: AppColors.textMuted),
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
                                              child: const Icon(
                                                Icons.push_pin_rounded,
                                                size: 14,
                                                color: AppColors.textMuted,
                                              ),
                                            ),
                                          ),
                                        ),
                                        AnimatedScale(
                                          scale: isMuted ? 1.0 : 0.0,
                                          duration: const Duration(milliseconds: 150),
                                          curve: Curves.easeOut,
                                          child: const Padding(
                                            padding: EdgeInsets.only(right: 6.0),
                                            child: Icon(
                                              Icons.volume_off_rounded,
                                              size: 14,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                        ),
                                        if (timeStr.isNotEmpty)
                                          Text(
                                            timeStr,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                                              color: hasUnread ? AppColors.primary : AppColors.textMuted,
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
                                      child: _isPartnerTypingFresh(conv)
                                          ? const Text(
                                              'typing...',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                fontStyle: FontStyle.italic,
                                                color: AppColors.primary,
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
                                                color: hasUnread ? AppColors.textPrimary : AppColors.textMuted,
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
                                            color: AppColors.primary,
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
        ),
      ),
    );
  }

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

  Widget _buildArchivedRow() {
    return TweenAnimationBuilder<double>(
      key: const ValueKey('archived_banner_entry'),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, factor, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: factor,
          child: child,
        ),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _archivedTransitionDirection = 1.0;
              _lastTransitionWasArchived = true;
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
                  decoration: const BoxDecoration(
                    color: AppColors.chipBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.archive_rounded, size: 22, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Archived',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 7,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 1,
        color: AppColors.divider,
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
                  color: AppColors.chipBg,
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
                            color: AppColors.chipBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        Container(
                          width: 45,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.chipBg,
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
                        color: AppColors.chipBg,
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

  Widget _buildEmptyState() {
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
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No conversations yet',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Connect and chat with neighbors and friends in Vadodara.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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

  Widget _buildArchivedEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.archive_outlined, size: 48, color: AppColors.textMuted),
            SizedBox(height: 14),
            Text(
              'No archived chats',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Chats you archive will be stored here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFilterState() {
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
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'No $filterName chats',
              style: const TextStyle(
                color: AppColors.textPrimary,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'No conversations for "$_searchQuery"',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Check your spelling or start a new chat with a friend.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _searchController.clear(),
              child: const Text(
                'Clear search',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            const Text(
              'Could not load messages',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please check your network connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'New Message',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextField(
                      controller: _filterController,
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Search friends...',
                        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                        prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: StreamBuilder<List<Friendship>>(
                stream: widget.friendRepo.getFriendsList(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
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
                            const Icon(Icons.people_outline_rounded, size: 40, color: AppColors.textMuted),
                            const SizedBox(height: 10),
                            Text(
                              _filter.isEmpty
                                  ? 'No friends yet'
                                  : 'No friends matching "$_filter"',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Add neighbors as friends from the feed to start chatting!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: friendHandles.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, indent: 68, color: AppColors.divider),
                    itemBuilder: (context, index) {
                      final handle = friendHandles[index];
                      return ListTile(
                        tileColor: AppColors.surface,
                        leading: UserAvatar(handle: handle, size: 42, fontSize: 16),
                        title: () {
                          final cleanH = handle.replaceAll('@', '').trim();
                          final dn = NameCacheService.instance.getDisplayName(cleanH);
                          final label = dn.isNotEmpty ? dn : cleanH;
                          return Text(
                            label,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          );
                        }(),
                        subtitle: const Text(
                          'Vadodara Neighbor',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context, handle);
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
