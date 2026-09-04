import 'package:flutter/material.dart';
import '../../services/community_repository.dart';
import '../../models/community_model.dart';
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
  final _messageController = TextEditingController();
  bool _isMember = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkMembership();
  }

  Future<void> _checkMembership() async {
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

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    final text = _messageController.text;
    _messageController.clear();
    await widget.repository.sendMessage(widget.community.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.community.adminHandle == widget.repository.currentUserHandle;
    final canPost = !_isLoading && _isMember && (!widget.community.isChannel || isAdmin);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D30),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.community.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              widget.community.isChannel ? 'Channel' : 'Group',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<CommunityMessage>>(
              stream: widget.repository.getCommunityMessages(widget.community.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('No messages yet. Say hi!', style: TextStyle(color: Colors.white54)),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.authorHandle == widget.repository.currentUserHandle;
                    return _buildMessageBubble(msg, isMe);
                  },
                );
              },
            ),
          ),
          if (!_isMember && !_isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF151D30),
              child: ElevatedButton(
                onPressed: _joinCommunity,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                child: Text('Join ${widget.community.isChannel ? 'Channel' : 'Group'}'),
              ),
            )
          else if (canPost)
            _buildMessageInput()
          else if (widget.community.isChannel && !isAdmin && _isMember)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF151D30),
              child: const Text(
                'Only admins can broadcast messages here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildMessageBubble(CommunityMessage msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF3B82F6) : const Color(0xFF1F293D),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && !widget.community.isChannel)
              Text(
                msg.authorHandle,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 4),
            Text(msg.content, style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              DateFormat('hh:mm a').format(msg.timestamp),
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      color: const Color(0xFF151D30),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8).copyWith(bottom: MediaQuery.of(context).padding.bottom + 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0B0F19),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
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
