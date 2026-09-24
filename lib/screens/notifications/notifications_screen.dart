import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/theme.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/friend_repository.dart';
import '../../models/friendship_model.dart';

enum NotificationFilter { all, unread, likes, comments, requests, uploads }

class NotificationsScreen extends StatefulWidget {
  final String currentUserHandle;

  const NotificationsScreen({
    super.key,
    required this.currentUserHandle,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NotificationFilter _selectedFilter = NotificationFilter.all;
  final Set<String> _acceptingFriendHandles = {};
  final Set<String> _animatingOutDocIds = {};
  StreamSubscription<List<Friendship>>? _friendsSub;
  final Set<String> _friendHandles = {};

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();
    if (cleanHandle.isNotEmpty) {
      final repo = FriendRepository()..currentUserHandle = cleanHandle;
      _friendsSub = repo.getFriendsList().listen((list) {
        if (!mounted) return;
        final set = <String>{};
        for (final f in list) {
          final other = f.getOtherUser(cleanHandle).replaceAll('@', '').trim().toLowerCase();
          if (other.isNotEmpty) set.add(other);
        }
        setState(() {
          _friendHandles.clear();
          _friendHandles.addAll(set);
        });
      });
    }

    _loadNotifications();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadNotifications(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _friendsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty) return;

    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/notifications?handle=$cleanHandle'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['notifications'] as List<dynamic>?) ?? [];
        if (mounted) {
          setState(() {
            _notifications = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'Just now';
    DateTime? dt;
    if (timestamp is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    } else if (timestamp is String) {
      dt = DateTime.tryParse(timestamp);
    }
    if (dt == null) return 'Just now';

    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  Future<void> _deleteNotification(String notifId) async {
    setState(() {
      _notifications.removeWhere((n) => n['id'] == notifId);
    });
  }

  Future<void> _clearReadNotifications(String cleanHandle) async {
    setState(() {
      _notifications.removeWhere((n) => n['isRead'] == true);
    });
  }

  Future<void> _markAllAsRead(String cleanHandle) async {
    try {
      await http.post(
        Uri.parse('${AuthService.baseUrl}/notifications/read-all?handle=$cleanHandle'),
        headers: {'Content-Type': 'application/json'},
      );

      setState(() {
        for (final n in _notifications) {
          n['isRead'] = true;
        }
      });

      if (mounted) {
        final c = context.nearhoodColors;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'All marked as read',
                style: TextStyle(color: c.btnink, fontWeight: FontWeight.w600, fontSize: 13.5),
                textAlign: TextAlign.center,
              ),
              backgroundColor: c.btn,
              behavior: SnackBarBehavior.floating,
              shape: const StadiumBorder(),
              duration: const Duration(milliseconds: 1600),
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
            ),
          );
      }
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  Future<void> _clearAllNotifications(String cleanHandle) async {
    final c = context.nearhoodColors;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.line),
        ),
        title: Text(
          'Clear all notifications?',
          style: TextStyle(
            color: c.ink,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Text(
          'All your activity history will be deleted. This cannot be undone.',
          style: TextStyle(color: c.muted, fontSize: 14, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: c.muted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _notifications.clear();
    });
  }

  void _onNotificationTapped(Map<String, dynamic> notif) async {
    final notifId = (notif['id'] ?? '').toString();
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();

    try {
      if (notif['isRead'] == false) {
        http.post(
          Uri.parse('${AuthService.baseUrl}/notifications/$notifId/read?handle=$cleanHandle'),
          headers: {'Content-Type': 'application/json'},
        ).catchError((_) => http.Response('', 500));
        setState(() {
          notif['isRead'] = true;
        });
      }
    } catch (_) {}

    final payloadData = (notif['data'] as Map<String, dynamic>?) ?? {};
    if (mounted) {
      final routerData = Map<String, dynamic>.from(payloadData);
      if (!routerData.containsKey('type') && notif['type'] != null) {
        routerData['type'] = notif['type'];
      }
      await NotificationService().navigateToScreen(routerData);
    }

    if (mounted) {
      setState(() {
        _animatingOutDocIds.add(notifId);
      });

      await Future.delayed(const Duration(milliseconds: 320));

      setState(() {
        _notifications.removeWhere((n) => n['id'] == notifId);
        _animatingOutDocIds.remove(notifId);
      });
    }
  }

  Future<void> _handleAcceptFriendRequest(String senderHandle, Map<String, dynamic> notif) async {
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();
    final cleanSender = senderHandle.replaceAll('@', '').trim();
    if (cleanSender.isEmpty) return;

    setState(() => _acceptingFriendHandles.add(cleanSender));

    try {
      final repo = FriendRepository()..currentUserHandle = cleanHandle;
      await repo.acceptFriendRequest(cleanSender);

      setState(() {
        notif['isRead'] = true;
        notif['isAccepted'] = true;
        notif['status'] = 'accepted';
      });

      if (mounted) {
        setState(() {
          _friendHandles.add(cleanSender.toLowerCase());
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              'You and @$cleanSender are now friends!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text('Failed to accept: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _acceptingFriendHandles.remove(cleanSender));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nearhoodColors;
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  Semantics(
                    label: 'Back',
                    button: true,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.field,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          size: 19,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.03 * 22,
                        color: c.ink,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.field,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.more_horiz, size: 20, color: c.ink),
                    ),
                    color: c.bg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: c.line),
                    ),
                    onSelected: (val) {
                      if (val == 'read_all') {
                        _markAllAsRead(cleanHandle);
                      } else if (val == 'clear_read') {
                        _clearReadNotifications(cleanHandle);
                      } else if (val == 'clear_all') {
                        _clearAllNotifications(cleanHandle);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'read_all',
                        child: Row(
                          children: [
                            Icon(Icons.done_all_rounded, size: 18, color: c.ink),
                            const SizedBox(width: 10),
                            Text('Mark all as read', style: TextStyle(color: c.ink, fontSize: 14)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'clear_read',
                        child: Row(
                          children: [
                            Icon(Icons.cleaning_services_rounded, size: 18, color: c.ink),
                            const SizedBox(width: 10),
                            Text('Clear read', style: TextStyle(color: c.ink, fontSize: 14)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'clear_all',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 18, color: c.danger),
                            const SizedBox(width: 10),
                            Text('Clear all', style: TextStyle(color: c.danger, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Filter Pills
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: [
                  _buildFilterChip('All', NotificationFilter.all, c),
                  _buildFilterChip('Unread', NotificationFilter.unread, c),
                  _buildFilterChip('Likes', NotificationFilter.likes, c),
                  _buildFilterChip('Comments', NotificationFilter.comments, c),
                  _buildFilterChip('Requests', NotificationFilter.requests, c),
                  _buildFilterChip('Uploads', NotificationFilter.uploads, c),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Notification List
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: c.ink, strokeWidth: 2.5),
                    )
                  : _buildNotificationList(c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationList(NearhoodColors c) {
    var items = List<Map<String, dynamic>>.from(_notifications);

    // Exclude regular chat messages
    items = items.where((n) {
      final payload = (n['data'] as Map<String, dynamic>?) ?? {};
      final type = payload['type'] as String? ?? n['type'] as String?;
      return type != 'chat' && type != 'message';
    }).toList();

    // Filter by category
    if (_selectedFilter != NotificationFilter.all) {
      items = items.where((n) {
        final isRead = n['isRead'] == true;
        if (_selectedFilter == NotificationFilter.unread) {
          return !isRead;
        }
        final payload = (n['data'] as Map<String, dynamic>?) ?? {};
        final type = payload['type'] as String? ?? n['type'] as String?;
        if (_selectedFilter == NotificationFilter.likes) {
          return type == 'post_like';
        } else if (_selectedFilter == NotificationFilter.comments) {
          return type == 'post_comment' || type == 'mention';
        } else if (_selectedFilter == NotificationFilter.requests) {
          return type == 'friend_request' || type == 'friend_accepted';
        } else if (_selectedFilter == NotificationFilter.uploads) {
          return type == 'post_upload' || type == 'post' || type == 'new_post';
        }
        return true;
      }).toList();
    }

    if (items.isEmpty) {
      return _buildEmptyState(c);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final notif = items[index];
        final notifId = (notif['id'] ?? index.toString()).toString();
        final isAnimatingOut = _animatingOutDocIds.contains(notifId);
        final title = notif['title'] as String? ?? 'Nearhood';
        final body = notif['body'] as String? ?? '';
        final isRead = notif['isRead'] == true;
        final timestamp = notif['timestamp'] ?? notif['createdAt'];
        final payload = (notif['data'] as Map<String, dynamic>?) ?? {};
        final type = payload['type'] as String? ?? notif['type'] as String?;
        final sender = (payload['senderHandle'] ?? payload['partnerHandle'] ?? notif['senderHandle'] as String?)?.replaceAll('@', '').trim();

        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: isAnimatingOut
              ? const SizedBox(width: double.infinity, height: 0)
              : AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  opacity: isAnimatingOut ? 0.0 : 1.0,
                  child: Dismissible(
                    key: ValueKey('notif_$notifId'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: c.danger,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    onDismissed: (_) {
                      _deleteNotification(notifId);
                    },
                    child: _buildNotificationCard(
                      notif: notif,
                      notifId: notifId,
                      title: title,
                      body: body,
                      isRead: isRead,
                      timestamp: timestamp,
                      type: type,
                      sender: sender,
                      c: c,
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildNotificationCard({
    required Map<String, dynamic> notif,
    required String notifId,
    required String title,
    required String body,
    required bool isRead,
    required dynamic timestamp,
    required String? type,
    required String? sender,
    required NearhoodColors c,
  }) {
    final cleanSender = (sender ?? '').replaceAll('@', '').trim();
    final isFriendRequest = type == 'friend_request';
    final bool isAlreadyFriend = cleanSender.isNotEmpty &&
        (_friendHandles.contains(cleanSender.toLowerCase()) ||
            notif['isAccepted'] == true ||
            notif['status'] == 'accepted');
    final isAccepting = cleanSender.isNotEmpty && _acceptingFriendHandles.contains(cleanSender);

    return GestureDetector(
      onTap: () => _onNotificationTapped(notif),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isRead ? c.bg : c.field,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRead ? c.line : c.ink.withValues(alpha: 0.16),
            width: isRead ? 1 : 1.3,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (sender != null && sender.isNotEmpty)
                  UserAvatar(handle: sender, size: 44)
                else
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.field,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_getTypeIcon(type), size: 22, color: c.ink),
                  ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      color: _getTypeColor(type),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.bg, width: 1.5),
                    ),
                    child: Icon(
                      _getTypeIcon(type),
                      size: 11,
                      color: Colors.white,
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
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13.5,
                        color: c.ink,
                        height: 1.35,
                      ),
                      children: [
                        if (sender != null && sender.isNotEmpty)
                          TextSpan(
                            text: '@$sender ',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: c.ink,
                            ),
                          ),
                        TextSpan(
                          text: _getFormattedBody(type, body, sender),
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                            color: isRead ? c.muted : c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatTime(timestamp),
                    style: TextStyle(fontSize: 11.5, color: c.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            if (isFriendRequest && cleanSender.isNotEmpty) ...[
              if (isAlreadyFriend)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.field,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, size: 14, color: c.muted),
                      const SizedBox(width: 4),
                      Text(
                        'Friends',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.btn,
                    foregroundColor: c.btnink,
                    elevation: 0,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isAccepting
                      ? null
                      : () => _handleAcceptFriendRequest(cleanSender, notif),
                  child: isAccepting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: c.btnink,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Confirm',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                ),
            ] else ...[
              if (!isRead)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: c.btn,
                    shape: BoxShape.circle,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: c.muted,
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _getFormattedBody(String? type, String body, String? sender) {
    if (type == 'post_like') {
      return 'liked your post.';
    } else if (type == 'post_comment') {
      if (sender != null && body.startsWith('@$sender commented: ')) {
        return body.replaceFirst('@$sender ', '');
      }
      return body;
    } else if (type == 'friend_request') {
      return 'sent you a friend request.';
    } else if (type == 'friend_accepted') {
      return 'accepted your friend request.';
    } else if (type == 'post_upload') {
      return 'Your post was published successfully.';
    } else if (type == 'mention') {
      return 'mentioned you in a comment.';
    }
    return body;
  }

  Color _getTypeColor(String? type) {
    if (type == 'post_like') return const Color(0xFFEF4444);
    if (type == 'post_comment') return const Color(0xFF3B82F6);
    if (type == 'friend_request') return const Color(0xFF8B5CF6);
    if (type == 'friend_accepted') return const Color(0xFF10B981);
    if (type == 'post_upload') return const Color(0xFF10B981);
    if (type == 'mention') return const Color(0xFFF59E0B);
    return const Color(0xFF0F172A);
  }

  IconData _getTypeIcon(String? type) {
    if (type == 'post_like') return Icons.favorite_rounded;
    if (type == 'post_comment') return Icons.chat_bubble_rounded;
    if (type == 'friend_request') return Icons.person_add_rounded;
    if (type == 'friend_accepted') return Icons.how_to_reg_rounded;
    if (type == 'post_upload') return Icons.check_circle_rounded;
    if (type == 'mention') return Icons.alternate_email_rounded;
    return Icons.notifications_rounded;
  }

  Widget _buildFilterChip(String label, NotificationFilter filter, NearhoodColors c) {
    final isSelected = _selectedFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = filter),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? c.btn : c.field,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? c.btn : c.line,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? c.btnink : c.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(NearhoodColors c) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: c.field,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              size: 32,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No activity yet',
            style: TextStyle(
              color: c.ink,
              fontWeight: FontWeight.w700,
              fontSize: 16.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "When someone likes or comments on your post, it will show up here.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.muted,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}
