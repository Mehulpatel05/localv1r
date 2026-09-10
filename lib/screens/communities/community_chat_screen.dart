import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/community_repository.dart';
import '../../models/community_model.dart';
import 'community_members_screen.dart';
import 'edit_community_screen.dart';
import 'full_screen_image_viewer.dart';
import 'package:intl/intl.dart';

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
  int _messageLimit = 30;
  // B1: debounce flag — prevents repeated setState when scrolled to bottom
  bool _isLoadingMoreMessages = false;
  // B5: mutable local copy — updated after admin edits community
  late CommunityModel _community;

  // Feature #9: available emojis for reactions
  static const List<String> _quickEmojis = ['❤️', '😂', '👍', '😮', '😢', '🔥'];

  @override
  void initState() {
    super.initState();
    _community = widget.community; // B5: init from widget
    final isAdmin = widget.community.adminHandle == widget.repository.currentUserHandle;
    _isMember = isAdmin;
    _isLoading = !isAdmin;
    _checkMembership();
    _scrollController.addListener(_scrollListener);
  }

  // B1 fixed: guard with _isLoadingMoreMessages flag so setState only fires once per threshold cross
  void _scrollListener() {
    if (!_isLoadingMoreMessages &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _isLoadingMoreMessages = true;
      setState(() => _messageLimit += 30);
      // Reset flag after a short delay so it can trigger again if user scrolls further
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _isLoadingMoreMessages = false;
      });
    }
  }

  @override
  void dispose() {
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
    final isMember = await widget.repository.isMember(widget.community.id);
    if (mounted) {
      setState(() {
        _isMember = isMember;
        _isLoading = false;
      });
    }
  }

  Future<void> _joinCommunity() async {
    setState(() => _isLoading = true);
    await widget.repository.joinCommunity(widget.community.id);
    await _checkMembership();
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
    if (_messageController.text.trim().isEmpty) return;
    final text = _messageController.text;
    _messageController.clear();
    await widget.repository.sendMessage(widget.community.id, text);
  }

  // F1: Show bottom sheet to choose Camera or Gallery
  Future<void> _pickAndSendImage() async {
    final source = await showModalBottomSheet<ImageSource>(
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
                backgroundColor: Color(0xFF3B82F6),
                child: Icon(Icons.camera_alt, color: Colors.white),
              ),
              title: const Text('Camera', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Take a new photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF3B82F6),
                child: Icon(Icons.photo_library, color: Colors.white),
              ),
              title: const Text('Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Choose from your photos'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _sendImage(source);
  }

  // Feature #11: Pick and send image using existing Telegram CDN
  Future<void> _sendImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _isSendingImage = true);
    try {
      await widget.repository.sendImageMessage(
        widget.community.id,
        File(picked.path),
        caption: _messageController.text.trim(),
      );
      _messageController.clear();
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
    final isAdmin =
        _community.adminHandle == widget.repository.currentUserHandle;
    final canPost = !_isLoading &&
        _isMember &&
        (!_community.isChannel || isAdmin);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_community.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              '${_community.isChannel ? 'Channel' : 'Group'} · ${widget.community.memberCount} members',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          if (_isMember)
            IconButton(
              icon: const Icon(Icons.people_outline, color: Colors.black54),
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
              icon: const Icon(Icons.edit_outlined, color: Colors.black54),
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
              stream: widget.repository.getCommunityMessages(
                  widget.community.id, limit: _messageLimit),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                // F3: Error state — network/permission failure
                if (snapshot.hasError) {
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
              color: Colors.white,
              child: ElevatedButton(
                onPressed: _joinCommunity,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6)),
                child: Text(
                    'Join ${_community.isChannel ? 'Channel' : 'Group'}'),
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
      label = DateFormat('d MMM y').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(CommunityMessage msg, bool isMe) {
    final hasReactions = msg.reactions.isNotEmpty;

    return GestureDetector(
      onLongPress: () => _showMessageOptions(context, msg), // Feature #9 + F2
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF3B82F6) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isMe
                      ? const Radius.circular(0)
                      : const Radius.circular(16),
                  bottomLeft: isMe
                      ? const Radius.circular(16)
                      : const Radius.circular(0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe && !widget.community.isChannel)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Text(
                        '@${msg.authorHandle}',
                        style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),

                  // Feature #11 + F6: Show image, tap to open full-screen viewer
                  if (msg.imageUrl != null)
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullScreenImageViewer(
                            imageUrl: msg.imageUrl!,
                            heroTag: msg.id,
                          ),
                        ),
                      ),
                      child: Hero(
                        tag: msg.id,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            msg.imageUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                height: 180,
                                color: Colors.black12,
                                child: const Center(
                                    child: CircularProgressIndicator()),
                              );
                            },
                            errorBuilder: (_, _, _) => Container(
                              height: 120,
                              color: Colors.black12,
                              child: const Icon(Icons.broken_image,
                                  color: Colors.black38),
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (msg.content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                      child: Text(
                        msg.content,
                        // Bug #2 fixed: white text on blue bubble
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                    ),

                  // F6: Tap timestamp to see full date + time
                  GestureDetector(
                    onTap: () {
                      final full = DateFormat('EEE, d MMM · hh:mm a')
                          .format(msg.timestamp);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(full,
                              style: const TextStyle(fontSize: 13)),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                          width: 220,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                      child: Text(
                        DateFormat('hh:mm a').format(msg.timestamp),
                        style: TextStyle(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.7)
                              : Colors.black87.withValues(alpha: 0.5),
                          fontSize: 9,
                        ),
                      ),
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
                                  color: const Color(0xFF3B82F6),
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
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8).copyWith(
          bottom: MediaQuery.of(context).padding.bottom + 8),
      child: Row(
        children: [
          // Feature #11: Image attach button
          IconButton(
            icon: const Icon(Icons.image_outlined, color: Color(0xFF3B82F6)),
            onPressed: _isSendingImage ? null : _pickAndSendImage,
            tooltip: 'Send Image',
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.black87),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: const TextStyle(color: Colors.black38),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF3B82F6),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}