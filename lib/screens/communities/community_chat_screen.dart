import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/motion.dart';
import '../../core/widgets/media_attachment_picker.dart';
import '../../models/community_model.dart';
import '../../services/community_repository.dart';
import '../../services/notification_service.dart';
import '../chat/widgets/image_group_bubble.dart';
import 'community_info_screen.dart';

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
  late CommunityModel _community;

  static const List<String> _quickEmojis = ['❤️', '😂', '👍', '😮', '😢', '🔥'];

  @override
  void initState() {
    super.initState();
    _community = widget.community;
    NotificationService().activeCommunityId = widget.community.id;
    final currentHandle = widget.repository.currentUserHandle.toLowerCase().replaceAll('@', '');
    final adminHandle = widget.community.adminHandle.toLowerCase().replaceAll('@', '');
    final isAdmin = adminHandle.isNotEmpty && adminHandle == currentHandle;
    final isCachedMember = widget.repository.isMemberCached(widget.community.id);
    _isMember = isAdmin || isCachedMember || widget.community.isMember;
    _isLoading = false;
    _checkMembership();
    _refreshCommunity();
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

  Future<void> _refreshCommunity() async {
    final updated = await widget.repository.getCommunityById(_community.id);
    if (updated != null && mounted) {
      setState(() {
        _community = updated;
        if (updated.isMember) _isMember = true;
      });
    }
  }

  Future<void> _checkMembership() async {
    final currentHandle = widget.repository.currentUserHandle.toLowerCase().replaceAll('@', '');
    final adminHandle = _community.adminHandle.toLowerCase().replaceAll('@', '');
    if (adminHandle.isNotEmpty && adminHandle == currentHandle) {
      if (mounted && !_isMember) {
        setState(() => _isMember = true);
      }
      return;
    }
    try {
      final isMem = await widget.repository.isMember(widget.community.id);
      if (mounted && _isMember != isMem) {
        setState(() => _isMember = isMem);
      }
    } catch (_) {}
  }

  Future<void> _joinCommunity() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.repository.joinCommunity(_community.id);
      if (mounted) {
        if (res.status == JoinStatus.pending) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Join request submitted for admin review!')),
          );
        } else if (res.status == JoinStatus.joined) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Joined ${_community.name}!')),
          );
          setState(() {
            _isMember = true;
            _community = _community.copyWith(myRole: 'member');
          });
          _refreshCommunity();
        } else if (res.status == JoinStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res.message.isNotEmpty ? res.message : 'Failed to join community')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    HapticFeedback.lightImpact();

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: AppMotion.durationStandard,
        curve: AppMotion.enterCurve,
      );
    }

    try {
      await widget.repository.sendMessage(_community.id, text);
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

  Future<void> _pickAndSendMedia() async {
    final filesToUpload = await MediaAttachmentPicker.showPickerSheet(
      context: context,
      maxFiles: 8,
    );

    if (filesToUpload.isEmpty) return;

    final caption = _messageController.text.trim();
    _messageController.clear();
    setState(() => _isSendingImage = true);

    try {
      await widget.repository.sendImageGroupMessage(
        _community.id,
        filesToUpload,
        caption: caption,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Media send failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingImage = false);
    }
  }

  void _showMessageOptions(BuildContext context, CommunityMessage msg) {
    final myHandle = widget.repository.currentUserHandle;
    final canEdit = msg.canEdit(myHandle);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
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
                  final alreadyReacted = (msg.reactions[emoji] ?? []).contains(myHandle);
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
            const Divider(height: 16),

            // Copy text
            if (msg.content.isNotEmpty && !msg.deletedForEveryone)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy text'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: msg.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),

            // Edit message (Own message within 48h)
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit message'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditMessageDialog(msg);
                },
              ),

            // Pin / Unpin (Admins/Owner)
            if (_community.isAdmin && !msg.isSystem && !msg.deletedForEveryone)
              ListTile(
                leading: Icon(msg.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                title: Text(msg.pinned ? 'Unpin message' : 'Pin message'),
                onTap: () async {
                  Navigator.pop(context);
                  await widget.repository.pinMessage(_community.id, msg.id, !msg.pinned);
                },
              ),

            // Delete Message
            if (!msg.isSystem && !msg.deletedForEveryone)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('Delete message', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteMessage(msg);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showEditMessageDialog(CommunityMessage msg) {
    final editController = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: editController,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Edit message content...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
            onPressed: () async {
              final newContent = editController.text.trim();
              if (newContent.isNotEmpty && newContent != msg.content) {
                Navigator.pop(ctx);
                await widget.repository.editMessage(_community.id, msg.id, newContent);
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteMessage(CommunityMessage msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This will delete the message for everyone in this community.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.repository.deleteMessage(_community.id, msg.id, mode: 'everyone');
            },
            child: const Text('Delete for Everyone'),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year && localA.month == localB.month && localA.day == localB.day;
  }

  String _formatDateSeparator(DateTime dt) {
    final localDt = dt.toLocal();
    final now = DateTime.now();
    if (_isSameDay(localDt, now)) return 'Today';
    if (_isSameDay(localDt, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('MMMM d, y').format(localDt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    final canPost = !_isLoading && _isMember && _community.canPost;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CommunityInfoScreen(
                  community: _community,
                  repository: widget.repository,
                ),
              ),
            );
            _refreshCommunity();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                _buildAppBarLogo(size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _community.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      Row(
                        children: [
                          if (!_isMember) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PREVIEW',
                                style: TextStyle(
                                  color: Color(0xFFB45309),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                          Text(
                            '${_community.isChannel ? 'Channel' : 'Group'} · ${_community.memberCount} ${_community.isChannel ? 'subscribers' : 'members'}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline_rounded, color: textColor),
            tooltip: 'Info',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityInfoScreen(
                    community: _community,
                    repository: widget.repository,
                  ),
                ),
              );
              _refreshCommunity();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Messages Stream ──
          Expanded(
            child: StreamBuilder<List<CommunityMessage>>(
              stream: widget.repository.getCommunityMessages(_community.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  );
                }

                final messages = snapshot.data ?? [];
                final pinnedMessages = messages.where((m) => m.pinned && !m.deletedForEveryone).toList();

                return Column(
                  children: [
                    // ── Pinned Message Banner ──
                    if (pinnedMessages.isNotEmpty)
                      _buildPinnedBanner(pinnedMessages.first, isDark),

                    // Messages List
                    Expanded(
                      child: messages.isEmpty
                          ? Center(
                              child: Text(
                                _community.isChannel
                                    ? 'No announcements yet.'
                                    : 'No messages yet. Say hi!',
                                style: const TextStyle(color: Color(0xFF94A3B8)),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final msg = messages[index];
                                final isMe = msg.authorHandle.toLowerCase().replaceAll('@', '') ==
                                    widget.repository.currentUserHandle.toLowerCase().replaceAll('@', '');

                                final bubble = _buildMessageBubble(msg, isMe, isDark);

                                final showDateSeparator = index == messages.length - 1 ||
                                    !_isSameDay(msg.timestamp, messages[index + 1].timestamp);

                                if (showDateSeparator) {
                                  return Column(
                                    children: [
                                      _buildDateSeparator(msg.timestamp, isDark),
                                      bubble,
                                    ],
                                  );
                                }
                                return bubble;
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),

          if (_isSendingImage)
            const LinearProgressIndicator(
              backgroundColor: Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
            ),

          // ── Bottom Input Bar / Join Bar ──
          _buildBottomInputArea(canPost, cardBg, textColor, isDark),
        ],
      ),
    );
  }

  Widget _buildAppBarLogo({double size = 38}) {
    final isChannel = _community.isChannel;
    final bgColor = isChannel ? const Color(0xFFE0F2FE) : const Color(0xFFDCFCE7);
    final iconColor = isChannel ? const Color(0xFF0284C7) : const Color(0xFF16A34A);

    if (_community.imageUrl != null && _community.imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          _community.imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _buildFallbackBox(size, bgColor, isChannel ? Icons.campaign_rounded : Icons.group_rounded, iconColor),
        ),
      );
    }
    return _buildFallbackBox(size, bgColor, isChannel ? Icons.campaign_rounded : Icons.group_rounded, iconColor);
  }

  Widget _buildFallbackBox(double size, Color bgColor, IconData icon, Color iconColor) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: iconColor, size: size * 0.52),
    );
  }

  // ── Pinned Message Banner ──
  Widget _buildPinnedBanner(CommunityMessage msg, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFDBEAFE),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin_rounded, size: 16, color: Color(0xFF3B82F6)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Pinned Message',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3B82F6),
                  ),
                ),
                Text(
                  msg.content.isNotEmpty ? msg.content : 'Photo/Media',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Message Bubble ──
  Widget _buildMessageBubble(CommunityMessage msg, bool isMe, bool isDark) {
    if (msg.isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            msg.content,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
        ),
      );
    }

    final isTombstone = msg.deletedForEveryone;

    return GestureDetector(
      onLongPress: () => _showMessageOptions(context, msg),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isTombstone
                ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))
                : (isMe
                    ? const Color(0xFF3B82F6)
                    : (isDark ? const Color(0xFF1E293B) : Colors.white)),
            borderRadius: BorderRadius.circular(16),
            border: !isMe && !isTombstone
                ? Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author header for non-me messages in groups
              if (!isMe && !_community.isChannel) ...[
                Text(
                  '@${msg.authorHandle}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(height: 4),
              ],

              // Tombstone vs Content
              if (isTombstone)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.block_rounded, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 6),
                    Text(
                      'This message was deleted',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                )
              else ...[
                if (msg.mediaUrls.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ImageGroupBubble(
                      mediaUrls: msg.mediaUrls,
                      caption: msg.content.isNotEmpty ? msg.content : null,
                      timeStr: DateFormat('h:mm a').format(msg.timestamp),
                      isMe: isMe,
                      messageId: msg.id,
                      bubbleRadius: BorderRadius.circular(16),
                    ),
                  )
                else if (msg.imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        msg.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                      ),
                    ),
                  ),

                if (msg.content.isNotEmpty)
                  Text(
                    msg.content,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: isMe ? Colors.white : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    ),
                  ),
              ],

              const SizedBox(height: 4),

              // Time + Edited + Pinned indicators
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (msg.pinned) ...[
                    const Icon(Icons.push_pin_rounded, size: 11, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                  ],
                  if (msg.isEdited) ...[
                    Text(
                      'edited',
                      style: TextStyle(
                        fontSize: 10,
                        color: isMe ? Colors.white70 : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    DateFormat('h:mm a').format(msg.timestamp.toLocal()),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white70 : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),

              // Reactions
              if (msg.reactions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: msg.reactions.entries.map((entry) {
                    final emoji = entry.key;
                    final count = entry.value.length;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$emoji $count',
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSeparator(DateTime dt, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _formatDateSeparator(dt),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  // ── Bottom Input Area ──
  Widget _buildBottomInputArea(bool canPost, Color cardBg, Color textColor, bool isDark) {
    if (!_isMember) {
      final isChannel = _community.isChannel;
      final btnLabel = _community.approveNewMembers
          ? 'Request to Join'
          : (isChannel ? 'JOIN CHANNEL' : 'JOIN GROUP');

      return Container(
        decoration: BoxDecoration(
          color: cardBg,
          boxShadow: [
            const BoxShadow(
              color: Color(0x0F000000),
              offset: Offset(0, -3),
              blurRadius: 10,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SafeArea(
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isLoading ? null : _joinCommunity,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.group_add_rounded, color: Colors.white, size: 20),
              label: Text(
                _isLoading ? 'Joining...' : btnLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.3),
              ),
            ),
          ),
        ),
      );
    }

    if (!canPost) {
      return Container(
        color: cardBg,
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Center(
            child: Text(
              _community.isChannel
                  ? 'Only channel admins can post.'
                  : 'Only admins can send messages in this group.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ),
        ),
      );
    }

    return Container(
      color: cardBg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        child: Row(
          children: [
            if (_community.canSendMedia)
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF3B82F6)),
                onPressed: _pickAndSendMedia,
              ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _messageController,
                  maxLines: 4,
                  minLines: 1,
                  style: TextStyle(color: textColor, fontSize: 14.5),
                  decoration: const InputDecoration(
                    hintText: 'Message...',
                    hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF3B82F6),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}