import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  int _messageLimit = 30;

  @override
  void initState() {
    super.initState();
    _chatId = _getChatId(widget.currentUserHandle, widget.partnerHandle);
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

  String _getChatId(String user1, String user2) {
    final users = [user1, user2];
    users.sort();
    return users.join('_');
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    final chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);
    final messageRef = chatRef.collection('messages').doc();

    final now = FieldValue.serverTimestamp();

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      transaction.set(messageRef, {
        'senderHandle': widget.currentUserHandle,
        'senderUid': FirebaseAuth.instance.currentUser?.uid,
        'content': text,
        'timestamp': now,
      });

      transaction.set(chatRef, {
        'participants': [widget.currentUserHandle, widget.partnerHandle],
        'lastMessage': text,
        'updatedAt': now,
      }, SetOptions(merge: true));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF3B82F6).withOpacity(0.2),
              child: Text(
                widget.partnerHandle.isNotEmpty ? widget.partnerHandle[0].toUpperCase() : '?',
                style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              widget.partnerHandle,
              style: const TextStyle(color: Colors.black87, fontSize: 16),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
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
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet. Say hi!',
                      style: TextStyle(color: Colors.black54),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index].data() as Map<String, dynamic>;
                    final isMe = msg['senderHandle'] == widget.currentUserHandle;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF3B82F6) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                          ),
                        ),
                        child: Text(
                          msg['content'] ?? '',
                          style: TextStyle(color: isMe ? Colors.white : Colors.black87),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.black12)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: const TextStyle(color: Colors.black38),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF3B82F6),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
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
