import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/notification_service.dart';

enum NotificationFilter { all, chat, friends, community, post }

/// Dedicated Activity & Notification Center Screen.
/// Strictly follows Nearhood Black & White design system.
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

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Just now';
    final dt = timestamp.toDate();
    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}';
  }

  Future<void> _markAllAsRead(String cleanHandle) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('targetHandle', isEqualTo: cleanHandle)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();

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

    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('targetHandle', isEqualTo: cleanHandle)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error clearing notifications: $e');
    }
  }

  void _onNotificationTapped(DocumentSnapshot doc, Map<String, dynamic> data) async {
    // Mark this notification as read
    try {
      if (doc.data() is Map && (doc.data() as Map)['isRead'] == false) {
        await doc.reference.update({'isRead': true});
      }
    } catch (_) {}

    final payloadData = (data['data'] as Map<String, dynamic>?) ?? {};
    if (mounted) {
      final routerData = Map<String, dynamic>.from(payloadData);
      NotificationService().navigateToScreen(routerData);
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
                      } else if (val == 'clear_all') {
                        _clearAllNotifications(cleanHandle);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'read_all',
                        child: Row(
                          children: [
                            Icon(Icons.done_all, size: 18, color: c.ink),
                            const SizedBox(width: 10),
                            Text('Mark all as read', style: TextStyle(color: c.ink, fontSize: 14)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'clear_all',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: c.danger),
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

            // Filter Chips
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: [
                  _buildFilterChip('All', NotificationFilter.all, c),
                  _buildFilterChip('Messages', NotificationFilter.chat, c),
                  _buildFilterChip('Requests', NotificationFilter.friends, c),
                  _buildFilterChip('Communities', NotificationFilter.community, c),
                  _buildFilterChip('Posts', NotificationFilter.post, c),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Notification Stream List
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .where('targetHandle', isEqualTo: cleanHandle)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(color: c.ink, strokeWidth: 2.5),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildEmptyState(c);
                  }

                  var docs = snapshot.data!.docs.toList();
                  // Sort in-memory to handle descending createdAt smoothly
                  docs.sort((a, b) {
                    final aTime = a.data()['createdAt'] as Timestamp?;
                    final bTime = b.data()['createdAt'] as Timestamp?;
                    if (aTime == null && bTime == null) return 0;
                    if (aTime == null) return 1;
                    if (bTime == null) return -1;
                    return bTime.compareTo(aTime);
                  });

                  // Filter by category
                  if (_selectedFilter != NotificationFilter.all) {
                    docs = docs.where((doc) {
                      final payload = (doc.data()['data'] as Map<String, dynamic>?) ?? {};
                      final type = payload['type'] as String?;
                      if (_selectedFilter == NotificationFilter.chat) {
                        return type == 'chat' || type == 'message';
                      } else if (_selectedFilter == NotificationFilter.friends) {
                        return type == 'friend_request';
                      } else if (_selectedFilter == NotificationFilter.community) {
                        return type == 'community_message' || type == 'community';
                      } else if (_selectedFilter == NotificationFilter.post) {
                        return type == 'post' || type == 'new_post';
                      }
                      return true;
                    }).toList();
                  }

                  if (docs.isEmpty) {
                    return _buildEmptyState(c);
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final title = data['title'] as String? ?? 'Nearhood';
                      final body = data['body'] as String? ?? '';
                      final isRead = data['isRead'] as bool? ?? true;
                      final timestamp = data['createdAt'] as Timestamp?;
                      final payload = (data['data'] as Map<String, dynamic>?) ?? {};
                      final type = payload['type'] as String?;
                      final sender = (payload['senderHandle'] ?? payload['partnerHandle'] as String?)?.replaceAll('@', '').trim();

                      return GestureDetector(
                        onTap: () => _onNotificationTapped(doc, data),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isRead ? c.bg : c.field,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isRead ? c.line : c.ink.withValues(alpha: 0.18),
                              width: isRead ? 1 : 1.3,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Leading Avatar / Icon
                              if (sender != null && sender.isNotEmpty)
                                UserAvatar(handle: sender, size: 40)
                              else
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: c.field,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _getCategoryIcon(type),
                                    size: 19,
                                    color: c.ink,
                                  ),
                                ),
                              const SizedBox(width: 12),

                              // Text details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                              color: c.ink,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatTime(timestamp),
                                          style: TextStyle(fontSize: 12, color: c.muted),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      body,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isRead ? c.muted : c.ink,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Unread blue dot
                              if (!isRead) ...[
                                const SizedBox(width: 8),
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: c.btn,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
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

  IconData _getCategoryIcon(String? type) {
    if (type == 'chat' || type == 'message') return Icons.chat_bubble_outline;
    if (type == 'friend_request') return Icons.person_add_outlined;
    if (type == 'community_message' || type == 'community') return Icons.groups_outlined;
    return Icons.notifications_none_outlined;
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
              Icons.notifications_none_outlined,
              size: 32,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: TextStyle(
              color: c.ink,
              fontWeight: FontWeight.w700,
              fontSize: 16.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "You're all caught up! Updates will appear here.",
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
