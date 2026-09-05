import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'personal_chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  final String currentUserHandle;

  const ChatListScreen({super.key, required this.currentUserHandle});

  String _getChatPartner(List<dynamic> participants) {
    return participants.firstWhere((p) => p != currentUserHandle, orElse: () => 'Unknown');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: currentUserHandle)
            .orderBy('updatedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)));
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading chats: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Colors.black26),
                  SizedBox(height: 16),
                  Text(
                    'No messages yet',
                    style: TextStyle(color: Colors.black54, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start a conversation by tapping a username\non the home feed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black38, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          final chats = snapshot.data!.docs;

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chatData = chats[index].data() as Map<String, dynamic>;
              final participants = chatData['participants'] as List<dynamic>? ?? [];
              final lastMessage = chatData['lastMessage'] as String? ?? '';
              final partnerHandle = _getChatPartner(participants);

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF3B82F6).withOpacity(0.2),
                  child: Text(
                    partnerHandle.isNotEmpty ? partnerHandle[0].toUpperCase() : '?',
                    style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  partnerHandle,
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PersonalChatScreen(
                        currentUserHandle: currentUserHandle,
                        partnerHandle: partnerHandle,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
