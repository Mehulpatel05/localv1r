import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/motion.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/telegram_storage_service.dart';
import '../../services/presence_service.dart';
import '../../services/notification_service.dart';
import '../../models/call_model.dart';
import '../../services/webrtc_call_service.dart';
import 'call_screen.dart';
import '../profile/other_user_profile_sheet.dart';
import 'widgets/image_group_bubble.dart';

class PersonalChatScreen extends StatefulWidget {
  final String currentUserHandle;
  final String partnerHandle;

  const PersonalChatScreen({
    super.key,
    required this.currentUserHandle,
    required this.partnerHandle,
  });

  @override
  State<PersonalChatScreen> createState() => _PersonalChatScreenState();
}

class _PersonalChatScreenState extends State<PersonalChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late String _chatId;
  int _messageLimit = 40;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  bool _isSending = false;
  bool _isSendingImage = false;
  StreamSubscription<QuerySnapshot>? _messagesSubscription;

  @override
  void initState() {
    super.initState();
    _chatId = _getChatId(widget.currentUserHandle, widget.partnerHandle);
    NotificationService().activeChatPartnerHandle = widget.partnerHandle.replaceAll('@', '').trim();
    _scrollController.addListener(_scrollListener);
    _markChatAsRead();
    _listenForUnreadMessages();
  }

  void _listenForUnreadMessages() {
    final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();
    _messagesSubscription?.cancel();
    _messagesSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final unreadFromPartner = snapshot.docs.where((doc) {
          final data = doc.data();
          final sender = (data['senderHandle'] ?? '').toString().replaceAll('@', '').trim();
          return sender != cleanMe;
        }).toList();

        if (unreadFromPartner.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          for (final doc in unreadFromPartner) {
            batch.update(doc.reference, {
              'isRead': true,
              'status': 'read',
              'readAt': FieldValue.serverTimestamp(),
            });
          }
          batch.commit().catchError((_) {});

          // Also reset chat unreadCounts for me
          FirebaseFirestore.instance
              .collection('chats')
              .doc(_chatId)
              .update({
            'unreadCounts.$cleanMe': 0,
          }).catchError((_) {});
        }
      }
    }, onError: (e) {
      debugPrint('Error listening for unread messages: $e');
    });
  }

  void _scrollListener() {
    if (_scrollController.hasClients &&
        !_isLoadingMore &&
        _hasMoreMessages &&
        _scrollController.position.maxScrollExtent > 200 &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100) {
      _loadMoreMessages();
    }
  }

  void _loadMoreMessages() {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    setState(() {
      _messageLimit += 30;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _isLoadingMore = false;
      }
    });
  }

  @override
  void dispose() {
    final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
    if (NotificationService().activeChatPartnerHandle == cleanPartner) {
      NotificationService().activeChatPartnerHandle = null;
    }
    _messagesSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getChatId(String user1, String user2) {
    final u1 = user1.replaceAll('@', '').trim();
    final u2 = user2.replaceAll('@', '').trim();
    final users = [u1, u2];
    users.sort();
    return users.join('_');
  }

  Future<void> _markChatAsRead() async {
    try {
      final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);
      final doc = await chatRef.get();
      if (doc.exists) {
        await chatRef.update({
          'unreadCounts.$cleanMe': 0,
          'unreadCounts.${widget.currentUserHandle}': 0,
        }).catchError((_) {});
      }

      // Mark unread messages sent by partner as read
      final unreadSnapshot = await chatRef
          .collection('messages')
          .where('isRead', isEqualTo: false)
          .limit(100)
          .get();

      final partnerDocs = unreadSnapshot.docs.where((d) {
        final data = d.data();
        final sender = (data['senderHandle'] ?? '').toString().replaceAll('@', '').trim();
        return sender != cleanMe;
      }).toList();

      if (partnerDocs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in partnerDocs) {
          batch.update(d.reference, {
            'isRead': true,
            'status': 'read',
            'readAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } catch (_) {}
  }

  Future<void> _startCall(CallType type) async {
    final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
    if (cleanPartner.isEmpty) return;

    HapticFeedback.lightImpact();

    try {
      final call = await WebRtcCallService.instance.makeCall(
        callerHandle: widget.currentUserHandle,
        receiverHandle: cleanPartner,
        callType: type,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            call: call,
            currentUserHandle: widget.currentUserHandle,
            isCaller: true,
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start call: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    _messageController.clear();
    setState(() => _isSending = true);
    HapticFeedback.lightImpact();

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: AppMotion.durationStandard,
        curve: AppMotion.enterCurve,
      );
    }

    try {
      final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
      final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();

      final partnerProfile = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(cleanPartner)
          .get();
      final partnerUid = partnerProfile.data()?['ownerUid'];
      final myUid = FirebaseAuth.instance.currentUser?.uid;

      final chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);
      final messageRef = chatRef.collection('messages').doc();

      final now = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.set(messageRef, {
          'senderHandle': cleanMe,
          'senderUid': myUid,
          'content': text,
          'type': 'text',
          'timestamp': now,
          'status': 'sent',
          'isRead': false,
        });

        transaction.set(chatRef, {
          'participants': [cleanMe, cleanPartner],
          'participantsUids': [
            ?myUid,
            ?partnerUid,
          ],
          'lastMessage': text,
          'lastSenderHandle': cleanMe,
          'updatedAt': now,
          'unreadCounts': {
            cleanMe: 0,
            cleanPartner: FieldValue.increment(1),
          },
        }, SetOptions(merge: true));
      });

      // Dispatch notification to partner
      NotificationService().sendNotification(
        targetHandle: cleanPartner,
        targetUid: partnerUid as String?,
        title: '@$cleanMe',
        body: text,
        data: {
          'type': 'chat',
          'senderHandle': cleanMe,
          'partnerHandle': cleanMe,
          'chatId': _chatId,
        },
      );
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickAndSendImages() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF2563EB),
                child: Icon(Icons.camera_alt_rounded, color: Colors.white),
              ),
              title: const Text('Camera', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Take a new photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF2563EB),
                child: Icon(Icons.photo_library_rounded, color: Colors.white),
              ),
              title: const Text('Gallery (Multi-select)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Choose multiple photos as an album'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;

    final picker = ImagePicker();
    List<File> filesToUpload = [];

    if (choice == 'camera') {
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (picked != null) filesToUpload.add(File(picked.path));
    } else {
      final pickedList = await picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (pickedList.isNotEmpty) {
        filesToUpload = pickedList.map((x) => File(x.path)).toList();
      }
    }

    if (filesToUpload.isEmpty) return;

    final caption = _messageController.text.trim();
    _messageController.clear();
    setState(() => _isSendingImage = true);

    try {
      // Parallel upload of all selected images
      final uploadFutures = filesToUpload.map((f) => TelegramStorageService.uploadImage(f));
      final uploadedUrls = await Future.wait(uploadFutures);
      final validUrls = uploadedUrls.whereType<String>().toList();

      if (validUrls.isEmpty) throw Exception('Image upload failed.');

      final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
      final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();

      final partnerProfile = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(cleanPartner)
          .get();
      final partnerUid = partnerProfile.data()?['ownerUid'];
      final myUid = FirebaseAuth.instance.currentUser?.uid;

      final chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);
      final messageRef = chatRef.collection('messages').doc();
      final now = FieldValue.serverTimestamp();

      final isGroup = validUrls.length > 1;
      final summaryText = caption.isNotEmpty
          ? caption
          : (isGroup ? '📷 ${validUrls.length} photos' : '📷 Photo');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.set(messageRef, {
          'senderHandle': cleanMe,
          'senderUid': myUid,
          'content': caption,
          'imageUrl': validUrls.first,
          'mediaUrls': validUrls,
          'type': isGroup ? 'image_group' : 'image',
          'timestamp': now,
          'status': 'sent',
          'isRead': false,
        });

        transaction.set(chatRef, {
          'participants': [cleanMe, cleanPartner],
          'participantsUids': [
            ?myUid,
            ?partnerUid,
          ],
          'lastMessage': summaryText,
          'lastSenderHandle': cleanMe,
          'updatedAt': now,
          'unreadCounts': {
            cleanMe: 0,
            cleanPartner: FieldValue.increment(1),
          },
        }, SetOptions(merge: true));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingImage = false);
    }
  }

  DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is DateTime) return timestamp;
    return DateTime.now();
  }

  String _formatMsgTime(dynamic timestamp) {
    if (timestamp == null) return '';
    final dt = _parseTimestamp(timestamp);
    return DateFormat('hh:mm a').format(dt);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(msgDay).inDays;

    String label;
    if (diff == 0) {
      label = 'Today';
    } else if (diff == 1) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMMM d, y').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(BuildContext context, Map<String, dynamic> msg) {
    final text = (msg['content'] ?? '') as String;
    if (text.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: Color(0xFF334155)),
                title: const Text('Copy message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied to clipboard'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallLogBubble(Map<String, dynamic> msg, bool isMe) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final callType = (msg['callType'] ?? 'audio').toString().toLowerCase();
    final callStatus = (msg['callStatus'] ?? 'ended').toString().toLowerCase();
    final durationSeconds = (msg['durationSeconds'] as num?)?.toInt() ?? 0;
    final isVideo = callType == 'video';
    final timeStr = _formatMsgTime(msg['timestamp']);

    final isMissed = callStatus == 'missed' || callStatus == 'declined';
    final isOutgoing = isMe;

    String title;
    if (callStatus == 'missed') {
      title = isOutgoing
          ? 'Cancelled ${isVideo ? 'video' : 'voice'} call'
          : 'Missed ${isVideo ? 'video' : 'voice'} call';
    } else if (callStatus == 'declined') {
      title = 'Declined ${isVideo ? 'video' : 'voice'} call';
    } else {
      title = isVideo ? 'Video call' : 'Voice call';
    }

    String subtitle = timeStr;
    if (durationSeconds > 0) {
      final m = durationSeconds ~/ 60;
      final s = durationSeconds % 60;
      final durStr = m > 0 ? '${m}m ${s}s' : '${s}s';
      subtitle = '$timeStr • $durStr';
    }

    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMissed
                ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isMissed
                    ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                    : const Color(0xFF22C55E).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVideo
                    ? (isMissed ? Icons.videocam_off_rounded : Icons.videocam_rounded)
                    : (isMissed
                        ? Icons.phone_missed_rounded
                        : (isOutgoing
                            ? Icons.phone_forwarded_rounded
                            : Icons.phone_callback_rounded)),
                color: isMissed ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            InkWell(
              onTap: () => _startCall(isVideo ? CallType.video : CallType.audio),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Call back',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, String msgId, bool isMe) {
    if (msg['type'] == 'call_log') {
      return _buildCallLogBubble(msg, isMe);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = (msg['content'] ?? '') as String;
    final imageUrl = msg['imageUrl'] as String?;
    final rawMediaUrls = msg['mediaUrls'];
    final timeStr = _formatMsgTime(msg['timestamp']);

    final List<String> mediaUrls = [];
    if (rawMediaUrls is List) {
      for (final u in rawMediaUrls) {
        if (u != null && u.toString().isNotEmpty) {
          mediaUrls.add(u.toString());
        }
      }
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      mediaUrls.add(imageUrl);
    }

    final hasImages = mediaUrls.isNotEmpty;

    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
    );

    final isRead = msg['isRead'] == true || msg['status'] == 'read';
    final status = (msg['status'] ?? 'sent') as String;

    return GestureDetector(
      onLongPress: () => _showMessageOptions(context, msg),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3.5),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * (hasImages ? 0.70 : 0.78),
          ),
          decoration: BoxDecoration(
            color: isMe
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF4F4F4)),
            borderRadius: bubbleRadius,
            border: Border.all(
              color: isMe
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                offset: const Offset(0, 1),
                blurRadius: 3,
              ),
            ],
          ),
          child: hasImages
              ? ImageGroupBubble(
                  mediaUrls: mediaUrls,
                  caption: content.isNotEmpty ? content : null,
                  timeStr: timeStr,
                  isMe: isMe,
                  messageId: msgId,
                  bubbleRadius: bubbleRadius,
                  isRead: isRead,
                  status: status,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  child: Column(
                    crossAxisAlignment:
                        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(
                        content,
                        style: TextStyle(
                          color: isMe
                              ? (isDark ? Colors.black : Colors.white)
                              : (isDark ? Colors.white : const Color(0xFF0F172A)),
                          fontSize: 14.5,
                          height: 1.35,
                        ),
                      ),
                      if (timeStr.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeStr,
                              style: TextStyle(
                                color: isMe
                                    ? (isDark ? Colors.black54 : Colors.white70)
                                    : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8)),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                isRead
                                    ? Icons.done_all_rounded
                                    : (status == 'delivered'
                                        ? Icons.done_all_rounded
                                        : Icons.done_rounded),
                                size: 14,
                                color: isRead
                                    ? const Color(0xFF93C5FD)
                                    : Colors.white.withValues(alpha: 0.75),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildEmptyChatPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFF2563EB),
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Say hi to @${widget.partnerHandle.replaceAll('@', '')}!',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Send a message to start connecting with your neighbor.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(List<QueryDocumentSnapshot> messages) {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final doc = messages[index];
        final msg = doc.data() as Map<String, dynamic>;
        final isMe = msg['senderHandle'] == widget.currentUserHandle;
        final bubble = _buildMessageBubble(msg, doc.id, isMe);

        final currentTimestamp = _parseTimestamp(msg['timestamp']);
        final showDateSeparator = index == messages.length - 1 ||
            !_isSameDay(
              currentTimestamp,
              _parseTimestamp(
                (messages[index + 1].data() as Map<String, dynamic>)['timestamp'],
              ),
            );

        if (showDateSeparator) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              bubble,
              _buildDateSeparator(currentTimestamp),
            ],
          );
        }
        return bubble;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: InkWell(
          onTap: () {
            showOtherUserProfileSheet(
              context,
              partnerHandle: widget.partnerHandle,
              currentUserHandle: widget.currentUserHandle,
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                UserAvatar(
                  handle: widget.partnerHandle,
                  size: 38,
                  fontSize: 15,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StreamBuilder<UserPresence>(
                    stream: PresenceService.instance.getPresenceStream(widget.partnerHandle),
                    initialData: PresenceService.instance.getCachedPresence(widget.partnerHandle),
                    builder: (context, snapshot) {
                      final presence = snapshot.data;
                      final statusText = PresenceService.formatLastSeen(presence);
                      final isOnline = presence?.isOnline == true;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '@${widget.partnerHandle.replaceAll('@', '')}',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              if (isOnline) ...[
                                Container(
                                  width: 7,
                                  height: 7,
                                  margin: const EdgeInsets.only(right: 5),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF16A34A),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                              Flexible(
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    color: isOnline ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                    fontSize: 11.5,
                                    fontWeight: isOnline ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.call_outlined,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              size: 22,
            ),
            tooltip: 'Voice Call',
            onPressed: () => _startCall(CallType.audio),
          ),
          IconButton(
            icon: Icon(
              Icons.videocam_outlined,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              size: 24,
            ),
            tooltip: 'Video Call',
            onPressed: () => _startCall(CallType.video),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .limit(_messageLimit)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                  );
                }

                if (snapshot.hasError) {
                  debugPrint('Personal chat messages stream error: ${snapshot.error}');
                  // Fallback without server orderBy in case of indexing delay
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(_chatId)
                        .collection('messages')
                        .limit(_messageLimit)
                        .snapshots(),
                    builder: (ctx, fbSnap) {
                      if (fbSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)));
                      }
                      final rawDocs = fbSnap.data?.docs ?? [];
                      if (rawDocs.isEmpty) {
                        return _buildEmptyChatPlaceholder();
                      }
                      final sortedDocs = List<QueryDocumentSnapshot>.from(rawDocs);
                      sortedDocs.sort((a, b) {
                        final aData = a.data() as Map<String, dynamic>? ?? {};
                        final bData = b.data() as Map<String, dynamic>? ?? {};
                        final aTs = aData['timestamp'];
                        final bTs = bData['timestamp'];
                        DateTime aTime = DateTime.fromMillisecondsSinceEpoch(0);
                        DateTime bTime = DateTime.fromMillisecondsSinceEpoch(0);
                        if (aTs is Timestamp) aTime = aTs.toDate();
                        if (bTs is Timestamp) bTime = bTs.toDate();
                        return bTime.compareTo(aTime);
                      });
                      _hasMoreMessages = sortedDocs.length >= _messageLimit;
                      return _buildMessagesList(sortedDocs);
                    },
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyChatPlaceholder();
                }

                final messages = snapshot.data!.docs;
                _hasMoreMessages = messages.length >= _messageLimit;
                return _buildMessagesList(messages);
              },
            ),
          ),
          if (_isSendingImage)
            LinearProgressIndicator(
              backgroundColor: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0),
              color: isDark ? Colors.white : Colors.black,
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              border: Border(top: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9), width: 1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.photo_library_outlined, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E), size: 24),
                    onPressed: _isSendingImage ? null : _pickAndSendImages,
                    tooltip: 'Send Photos',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 14.5),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: isDark ? const Color(0xFF6E6E6E) : const Color(0xFF94A3B8), fontSize: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF141414) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white : Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.send_rounded, color: isDark ? Colors.black : Colors.white, size: 19),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

