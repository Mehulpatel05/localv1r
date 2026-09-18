import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/chat_conversation_model.dart';
import '../../models/friendship_model.dart';
import '../../services/friend_repository.dart';
import 'personal_chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  final String currentUserHandle;

  const ChatListScreen({super.key, required this.currentUserHandle});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late final FriendRepository _friendRepo;

  @override
  void initState() {
    super.initState();
    _friendRepo = FriendRepository()..currentUserHandle = widget.currentUserHandle;
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _getChatsStream() {
    final rawHandle = widget.currentUserHandle.trim();
    final cleanHandle = rawHandle.replaceAll('@', '');
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    final handles = <String>{
      rawHandle,
      cleanHandle,
      '@$cleanHandle',
      rawHandle.toLowerCase(),
      cleanHandle.toLowerCase(),
      '@${cleanHandle.toLowerCase()}',
      if (myUid != null && myUid.isNotEmpty) myUid,
    }.where((h) => h.isNotEmpty).toList();

    if (handles.isEmpty) {
      if (myUid != null && myUid.isNotEmpty) {
        return FirebaseFirestore.instance
            .collection('chats')
            .where('participantsUids', arrayContains: myUid)
            .snapshots();
      }
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContainsAny: handles)
        .snapshots();
  }

  String _formatTimestamp(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0 && now.day == dateTime.day) {
      return DateFormat('hh:mm a').format(dateTime);
    } else if (difference.inDays == 1 || (difference.inDays == 0 && now.day != dateTime.day)) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('E').format(dateTime); // e.g. Mon, Tue
    } else {
      return DateFormat('d MMM').format(dateTime); // e.g. 14 Sep
    }
  }

  void _showHelpDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: const [
                Icon(Icons.lock_outline_rounded, color: Color(0xFF3B82F6), size: 22),
                SizedBox(width: 8),
                Text(
                  'Neighborhood Messaging',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '• Messages are strictly private between you and your neighbor.\n• You can message any friend or neighbor directly.\n• Be respectful and follow community safety guidelines.\n• You can block or report any user at any time from their profile.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewChatPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewChatFriendPickerSheet(
        currentUserHandle: widget.currentUserHandle,
        friendRepo: _friendRepo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: const Text(
          'Messages',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Help',
            icon: const Icon(
              Icons.help_outline_rounded,
              color: Color(0xFF64748B),
              size: 22,
            ),
            onPressed: _showHelpDialog,
          ),
          IconButton(
            tooltip: 'New Message',
            icon: const Icon(
              Icons.edit_note_rounded,
              color: Color(0xFF0F172A),
              size: 26,
            ),
            onPressed: _showNewChatPicker,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF3B82F6),
        elevation: 3,
        shape: const CircleBorder(),
        onPressed: _showNewChatPicker,
        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
      ),
      body: Column(
        children: [
          // Search Input matching Image
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Search conversations',
                  hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF94A3B8),
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),

          // Messages List with Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getChatsStream(),
              builder: (context, snapshot) {
                // 1. Loading Skeleton State
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildSkeletonLoading();
                }

                // 2. Error / Offline State
                if (snapshot.hasError) {
                  debugPrint('Chat stream error: ${snapshot.error}');
                  final myUid = FirebaseAuth.instance.currentUser?.uid;
                  if (myUid != null && myUid.isNotEmpty) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('chats')
                          .where('participantsUids', arrayContains: myUid)
                          .snapshots(),
                      builder: (ctx, uidSnap) {
                        if (uidSnap.connectionState == ConnectionState.waiting) {
                          return _buildSkeletonLoading();
                        }
                        if (uidSnap.hasData && uidSnap.data!.docs.isNotEmpty) {
                          final convs = <ChatConversation>[];
                          for (final doc in uidSnap.data!.docs) {
                            try {
                              convs.add(ChatConversation.fromFirestore(doc));
                            } catch (_) {}
                          }
                          convs.sort((a, b) {
                            final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                            final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                            return bTime.compareTo(aTime);
                          });
                          final filtered = convs.where((conv) {
                            if (_searchQuery.isEmpty) return true;
                            final partner = conv.getPartnerHandle(widget.currentUserHandle).toLowerCase();
                            final snippet = conv.lastMessage.toLowerCase();
                            return partner.contains(_searchQuery) || snippet.contains(_searchQuery);
                          }).toList();
                          if (filtered.isEmpty && _searchQuery.isNotEmpty) {
                            return _buildSearchEmptyState();
                          }
                          return ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) => const Divider(
                              height: 1,
                              indent: 76,
                              endIndent: 16,
                              color: Color(0xFFF1F5F9),
                            ),
                            itemBuilder: (context, index) => _buildConversationTile(filtered[index]),
                          );
                        }
                        return _buildEmptyState();
                      },
                    );
                  }
                  return _buildErrorState(snapshot.error.toString());
                }

                final rawDocs = snapshot.data?.docs ?? [];
                final conversations = <ChatConversation>[];
                for (final doc in rawDocs) {
                  try {
                    conversations.add(ChatConversation.fromFirestore(doc));
                  } catch (e) {
                    debugPrint('Error parsing chat conversation: $e');
                  }
                }

                // Sort by updatedAt descending in memory (zero composite index required)
                conversations.sort((a, b) {
                  final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return bTime.compareTo(aTime);
                });

                // 3. Filter by search query if present
                final filtered = conversations.where((conv) {
                  if (_searchQuery.isEmpty) return true;
                  final partner = conv.getPartnerHandle(widget.currentUserHandle).toLowerCase();
                  final snippet = conv.lastMessage.toLowerCase();
                  return partner.contains(_searchQuery) || snippet.contains(_searchQuery);
                }).toList();

                // 4. Empty States
                if (conversations.isEmpty) {
                  return _buildEmptyState();
                }

                if (filtered.isEmpty && _searchQuery.isNotEmpty) {
                  return _buildSearchEmptyState();
                }

                // 5. Conversation List
                return ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF1F5F9),
                    indent: 80,
                  ),
                  itemBuilder: (context, index) {
                    final conv = filtered[index];
                    return _buildConversationTile(conv);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Conversation Tile matching Image 1
  Widget _buildConversationTile(ChatConversation conv) {
    final partner = conv.getPartnerHandle(widget.currentUserHandle);
    final cleanHandle = partner.replaceAll('@', '');
    final initial = cleanHandle.isNotEmpty ? cleanHandle[0].toUpperCase() : '?';
    final unreadCount = conv.getUnreadCount(widget.currentUserHandle);
    final hasUnread = unreadCount > 0;
    final timeStr = _formatTimestamp(conv.updatedAt);

    return Material(
      color: hasUnread ? const Color(0xFFEFF6FF) : Colors.white,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PersonalChatScreen(
                currentUserHandle: widget.currentUserHandle,
                partnerHandle: cleanHandle,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar with Online Status Dot
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDBEAFE),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Color(0xFF1E40AF),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  // Online green dot indicator (Active status)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // Handle & Last Message Snippet
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            '@$cleanHandle',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (timeStr.isNotEmpty)
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                              color: hasUnread ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conv.lastMessage.isNotEmpty
                                ? conv.lastMessage
                                : 'Drafted message',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                              color: hasUnread ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 1. Shimmer Loading Skeleton
  Widget _buildSkeletonLoading() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 7,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFFF1F5F9),
        indent: 80,
      ),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 120,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        Container(
                          width: 45,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 2. Empty State
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 36,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No conversations yet',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Connect and chat with neighbors and friends in Vadodara.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Start a Conversation', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: _showNewChatPicker,
            ),
          ],
        ),
      ),
    );
  }

  // 3. Search Empty State
  Widget _buildSearchEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              'No conversations for "$_searchQuery"',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Check your spelling or start a new chat with a friend.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _searchController.clear(),
              child: const Text('Clear search', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // 4. Error State
  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            const Text(
              'Could not load messages',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please check your network connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => setState(() {}),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom Sheet to pick a friend and initiate a 1-on-1 chat
class _NewChatFriendPickerSheet extends StatefulWidget {
  final String currentUserHandle;
  final FriendRepository friendRepo;

  const _NewChatFriendPickerSheet({
    required this.currentUserHandle,
    required this.friendRepo,
  });

  @override
  State<_NewChatFriendPickerSheet> createState() => _NewChatFriendPickerSheetState();
}

class _NewChatFriendPickerSheetState extends State<_NewChatFriendPickerSheet> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      setState(() => _filter = _filterController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle & Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'New Message',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Search Friend Filter
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextField(
                      controller: _filterController,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                      decoration: const InputDecoration(
                        hintText: 'Search friends...',
                        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                        prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 18),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // Friends List Stream
            Expanded(
              child: StreamBuilder<List<Friendship>>(
                stream: widget.friendRepo.getFriendsList(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)));
                  }

                  final friendships = snapshot.data ?? [];
                  final friendHandles = friendships
                      .map((f) => f.getOtherUser(widget.currentUserHandle))
                      .where((h) => h.toLowerCase().contains(_filter))
                      .toList();

                  if (friendHandles.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_outline_rounded, size: 40, color: Color(0xFF94A3B8)),
                            const SizedBox(height: 10),
                            Text(
                              _filter.isEmpty
                                  ? 'No friends yet'
                                  : 'No friends matching "$_filter"',
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Add neighbors as friends from the feed to start chatting!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: friendHandles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 68, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final handle = friendHandles[index];
                      final initial = handle.isNotEmpty ? handle[0].toUpperCase() : '?';

                      return ListTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: Color(0xFFDBEAFE),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        title: Text(
                          '@$handle',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: const Text(
                          'Vadodara Neighbor',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFCBD5E1)),
                        onTap: () {
                          Navigator.pop(context); // Close sheet
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PersonalChatScreen(
                                currentUserHandle: widget.currentUserHandle,
                                partnerHandle: handle,
                              ),
                            ),
                          );
                        },
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
}
