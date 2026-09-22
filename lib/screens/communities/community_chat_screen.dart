import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/motion.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/community_repository.dart';
import '../../models/community_model.dart';
import '../chat/widgets/image_group_bubble.dart';
import 'community_members_screen.dart';
import 'edit_community_screen.dart';
import 'package:intl/intl.dart';
import '../../services/notification_service.dart';

class CommunityChatScreen extends StatefulWidget {
  final CommunityRepository repository;
  final CommunityModel community;

  const CommunityChatScreen({
    super.key,
    required this.repository,
    required this.community,
  });

  @override
  State<CommunityChatScreen> createState() => _CommunityChatScreenState();
}

class _CommunityChatScreenState extends State<CommunityChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isMember = false;
  bool _isLoading = true;
  bool _isSendingImage = false;
  // B5: mutable local copy — updated after admin edits community
  late CommunityModel _community;

  // Feature #9: available emojis for reactions
  static const List<String> _quickEmojis = ['❤️', '😂', '👍', '😮', '😢', '🔥'];

  @override
  void initState() {
    super.initState();
    _community = widget.community; // B5: init from widget
    NotificationService().activeCommunityId = widget.community.id;
    final isAdmin = widget.community.adminHandle == widget.repository.currentUserHandle;
    _isMember = isAdmin;
    _isLoading = !isAdmin;
    _checkMembership();
  }

  @override
  void dispose() {
    if (NotificationService().activeCommunityId == widget.community.id) {
      NotificationService().activeCommunityId = null;
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkMembership() async {
    final isAdmin = _community.adminHandle == widget.repository.currentUserHandle;
    if (isAdmin) {
      if (mounted) {
        setState(() {
          _isMember = true;
          _isLoading = false;
        });
      }
      return;
    }
    try {
      final isMember = await widget.repository.isMember(widget.community.id);
      if (mounted) {
        setState(() {
          _isMember = isMember;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking membership: $e');
      if (mounted) {
        setState(() {
          _isMember = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _joinCommunity() async {
    setState(() {
      _isLoading = true;
      _isMember = true; // Optimistically unlock chat immediately
    });
    try {
      await widget.repository.joinCommunity(widget.community.id);
    } catch (e) {
      debugPrint('Error joining community: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Feature #15: Leave confirmation dialog
  Future<void> _leaveCommunity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Community?'),
        content: Text('Are you sure you want to leave "${_community.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    await widget.repository.leaveCommunity(widget.community.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteCommunity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Community?'),
        content: Text(
            'This will permanently delete "${_community.name}" and all its messages.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      await widget.repository.deleteCommunity(widget.community.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    HapticFeedback.lightImpact();

    // Smooth scroll down immediately
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: AppMotion.durationStandard,
        curve: AppMotion.enterCurve,
      );
    }

    try {
      await widget.repository.sendMessage(widget.community.id, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // F1: Show bottom sheet to choose Camera or Gallery (Multi-select)
  Future<void> _pickAndSendImage() async {
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
              width: 40, height: 4,
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
      await widget.repository.sendImageGroupMessage(
        widget.community.id,
        filesToUpload,
        caption: caption,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Image send failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSendingImage = false);
    }
  }

  // Feature #9 + F2: Long press → emoji reactions + copy text option
  void _showMessageOptions(BuildContext context, CommunityMessage msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Emoji reactions row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _quickEmojis.map((emoji) {
                  final alreadyReacted = (msg.reactions[emoji] ?? [])
                      .contains(widget.repository.currentUserHandle);
                  return GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      await widget.repository.toggleReaction(msg.id, emoji);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: alreadyReacted
                            ? const Color(0xFFEFF6FF)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: alreadyReacted
                            ? Border.all(color: const Color(0xFF3B82F6), width: 1.5)
                            : null,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  );
                }).toList(),
              ),
            ),
            // F2: Copy option — only shown when message has text content
            if (msg.content.isNotEmpty) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.copy_outlined, color: Colors.black54),
                title: const Text('Copy text',
                    style: TextStyle(color: Colors.black87, fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  // Copy to clipboard
                  final data = ClipboardData(text: msg.content);
                  Clipboard.setData(data);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin =
        _community.adminHandle == widget.repository.currentUserHandle;
    final canPost = !_isLoading &&
        _isMember &&
        (!_community.isChannel || isAdmin);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_community.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                )),
            Text(
              '${_community.isChannel ? 'Channel' : 'Group'} · ${widget.community.memberCount} members',
              style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9A9A9A) : Colors.black54),
            ),
          ],
        ),
        actions: [
          if (_isMember)
            IconButton(
              icon: Icon(Icons.people_outline, color: isDark ? const Color(0xFF9A9A9A) : Colors.black54),
              tooltip: 'Members',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityMembersScreen(
                    repository: widget.repository,
                    community: _community,
                  ),
                ),
              ),
            ),
          if (isAdmin)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: isDark ? const Color(0xFF9A9A9A) : Colors.black54),
              tooltip: 'Edit Community',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditCommunityScreen(
                      repository: widget.repository,
                      community: _community,
                    ),
                  ),
                );
              },
            ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              tooltip: 'Delete Community',
              onPressed: _deleteCommunity,
            )
          else if (_isMember)
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              tooltip: 'Leave Community',
              onPressed: _leaveCommunity,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<CommunityMessage>>(
              stream: widget.repository.getCommunityMessages(widget.community.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF3B82F6),
                      strokeWidth: 2.5,
                    ),
                  );
                }
                // F3: Error state — network/permission failure
                if (snapshot.hasError) {
                  debugPrint('Community chat error: ${snapshot.error}');
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off,
                            size: 48, color: Colors.black26),
                        const SizedBox(height: 12),
                        const Text('Could not load messages.',
                            style: TextStyle(color: Colors.black54)),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('No messages yet. Say hi!',
                        style: TextStyle(color: Colors.black54)),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics()),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  // F1: each message + possible date separator = 2 potential items per message
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe =
                        msg.authorHandle == widget.repository.currentUserHandle;
                    final bubble = _buildMessageBubble(msg, isMe);

                    // B5 fixed: reversed list — index+1 is OLDER message
                    // Separator should appear ABOVE older group.
                    // In a reversed ListView, "above" = rendered AFTER bubble in Column
                    final showDateSeparator = index == messages.length - 1 ||
                        !_isSameDay(msg.timestamp, messages[index + 1].timestamp);

                    if (showDateSeparator) {
                      return Column(
                        children: [
                          bubble,
                          _buildDateSeparator(msg.timestamp),
                        ],
                      );
                    }
                    return bubble;
                  },
                );
              },
            ),
          ),
          if (_isSendingImage)
            const LinearProgressIndicator(
              backgroundColor: Color(0xFFE2E8F0),
              color: Color(0xFF3B82F6),
            ),
          if (!_isMember && !_isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
              child: ElevatedButton(
                onPressed: _joinCommunity,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                    'Join ${_community.isChannel ? 'Channel' : 'Group'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            )
          else if (canPost)
            _buildMessageInput()
          else if (_community.isChannel && !isAdmin && _isMember)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: const Text(
                'Only admins can broadcast messages here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }

  // F1: Check if two timestamps are on the same calendar day
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // F1: Date separator pill — "Today", "Yesterday", or "8 Sep 2025"
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

  Widget _buildMessageBubble(CommunityMessage msg, bool isMe) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasReactions = msg.reactions.isNotEmpty;
    final timeStr = DateFormat('hh:mm a').format(msg.timestamp);

    final List<String> mediaUrls = [];
    if (msg.mediaUrls.isNotEmpty) {
      mediaUrls.addAll(msg.mediaUrls);
    } else if (msg.imageUrl != null && msg.imageUrl!.isNotEmpty) {
      mediaUrls.add(msg.imageUrl!);
    }

    final hasImages = mediaUrls.isNotEmpty;

    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
    );

    return GestureDetector(
      onLongPress: () => _showMessageOptions(context, msg), // Feature #9 + F2
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isMe && !widget.community.isChannel)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 8, 13, 2),
                      child: Text(
                        '@${msg.authorHandle}',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : const Color(0xFF0F172A),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                  if (hasImages)
                    ImageGroupBubble(
                      mediaUrls: mediaUrls,
                      caption: msg.content.isNotEmpty ? msg.content : null,
                      timeStr: timeStr,
                      isMe: isMe,
                      messageId: msg.id,
                      bubbleRadius: (!isMe && !widget.community.isChannel)
                          ? const BorderRadius.only(
                              bottomLeft: Radius.circular(4),
                              bottomRight: Radius.circular(18),
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(4),
                            )
                          : bubbleRadius,
                    )
                  else
                    // Pure Text Bubble
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 8),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.content,
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
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Feature #9: Show reaction counts below bubble
            if (hasReactions)
              Padding(
                padding: const EdgeInsets.only(
                    left: 16, right: 16, bottom: 4),
                child: Wrap(
                  spacing: 4,
                  children: msg.reactions.entries.map((entry) {
                    final emoji = entry.key;
                    final count = entry.value.length;
                    final iReacted = entry.value
                        .contains(widget.repository.currentUserHandle);
                    return GestureDetector(
                      onTap: () async {
                        await widget.repository
                            .toggleReaction(msg.id, emoji);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: iReacted
                              ? const Color(0xFFEFF6FF)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: iReacted
                              ? Border.all(
                                  color: const Color(0xFF2563EB),
                                  width: 1.5)
                              : null,
                        ),
                        child: Text(
                          '$emoji $count',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8).copyWith(
          bottom: MediaQuery.of(context).padding.bottom + 8),
      child: Row(
        children: [
          // Feature #11: Image attach button
          IconButton(
            icon: Icon(Icons.image_outlined, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E), size: 24),
            onPressed: _isSendingImage ? null : _pickAndSendImage,
            tooltip: 'Send Image',
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 15),
              textCapitalization: TextCapitalization.sentences,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: isDark ? const Color(0xFF6E6E6E) : Colors.black38, fontSize: 14),
                filled: true,
                fillColor: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: isDark ? Colors.white : Colors.black,
            shape: const CircleBorder(),
            elevation: 2,
            shadowColor: Colors.black.withOpacity(0.2),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sendMessage,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.send_rounded, color: isDark ? Colors.black : Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}