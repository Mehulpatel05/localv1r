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
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isMember = false;
  bool _isLoading = true;
  int _messageLimit = 30;

  @override
  void initState() {
    super.initState();
    _checkMembership();
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      setState(() {
        _messageLimit += 30;
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

  Future<void> _leaveCommunity() async {
    setState(() => _isLoading = true);
    await widget.repository.leaveCommunity(widget.community.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteCommunity() async {
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

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.community.adminHandle == widget.repository.currentUserHandle;
    final canPost = !_isLoading && _isMember && (!widget.community.isChannel || isAdmin);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.community.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              widget.community.isChannel ? 'Channel' : 'Group',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              tooltip: 'Delete Community',
              onPressed: () => _deleteCommunity(),
            )
          else if (_isMember)
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              tooltip: 'Leave Community',
              onPressed: () => _leaveCommunity(),
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<CommunityMessage>>(
              stream: widget.repository.getCommunityMessages(widget.community.id, limit: _messageLimit),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('No messages yet. Say hi!', style: TextStyle(color: Colors.black54)),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
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
              color: Colors.white,
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
              color: Colors.white,
              child: const Text(
                'Only admins can broadcast messages here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
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
          color: isMe ? const Color(0xFF3B82F6) : const Color(0xFFF1F5F9),
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
                style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 4),
            Text(msg.content, style: const TextStyle(color: Colors.black87, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              DateFormat('hh:mm a').format(msg.timestamp),
              style: TextStyle(color: Colors.black87.withOpacity(0.5), fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8).copyWith(bottom: MediaQuery.of(context).padding.bottom + 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: const TextStyle(color: Colors.black38),
                filled: true,
                fillColor: Colors.white,
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
