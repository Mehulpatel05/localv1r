import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/friend_repository.dart';
import '../../services/post_repository.dart';
import '../../models/friend_request_model.dart';
import '../../models/friendship_model.dart';
import '../chat/personal_chat_screen.dart';
import '../profile/other_user_profile_sheet.dart';

class FriendsScreen extends StatefulWidget {
  final FriendRepository repository;
  final String currentUserHandle;

  const FriendsScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Friends', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF3B82F6),
          labelColor: const Color(0xFF3B82F6),
          unselectedLabelColor: Colors.black54,
          tabs: [
            StreamBuilder<int>(
              stream: widget.repository.getPendingRequestCount(),
              builder: (context, snap) {
                final count = snap.data ?? 0;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Requests'),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const Tab(text: 'My Friends'),
            const Tab(text: 'Sent'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingRequests(),
          _buildFriendsList(),
          _buildSentRequests(),
        ],
      ),
    );
  }

  // ── Pending Requests Tab ──
  Widget _buildPendingRequests() {
    return StreamBuilder<List<FriendRequest>>(
      stream: widget.repository.getPendingRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)));
        }
        final requests = snapshot.data ?? [];
        if (requests.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_disabled, size: 48, color: Colors.white24),
                SizedBox(height: 12),
                Text('No pending requests', style: TextStyle(color: Colors.black54, fontSize: 15)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            return _buildRequestCard(req);
          },
        );
      },
    );
  }

  Widget _buildRequestCard(FriendRequest req) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                req.senderHandle.isNotEmpty ? req.senderHandle[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${req.senderHandle}',
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'Wants to be your friend',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          // Accept Button
          IconButton(
            onPressed: () => _acceptRequest(req.senderHandle),
            icon: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 32),
            tooltip: 'Accept',
          ),
          // Reject Button
          IconButton(
            onPressed: () => _rejectRequest(req.senderHandle),
            icon: const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 32),
            tooltip: 'Reject',
          ),
        ],
      ),
    );
  }

  Future<void> _acceptRequest(String senderHandle) async {
    try {
      await widget.repository.acceptFriendRequest(senderHandle);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You and @$senderHandle are now friends! \uD83C\uDF89'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _rejectRequest(String senderHandle) async {
    try {
      await widget.repository.rejectFriendRequest(senderHandle);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request rejected'), backgroundColor: Color(0xFF374151)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // ── Friends List Tab ──
  Widget _buildFriendsList() {
    return StreamBuilder<List<Friendship>>(
      stream: widget.repository.getFriendsList(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)));
        }
        final friendships = snapshot.data ?? [];
        if (friendships.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.group_off, size: 48, color: Colors.white24),
                SizedBox(height: 12),
                Text('No friends yet', style: TextStyle(color: Colors.black54, fontSize: 15)),
                SizedBox(height: 4),
                Text('Send friend requests from user profiles!', style: TextStyle(color: Colors.black38, fontSize: 12)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: friendships.length,
          itemBuilder: (context, index) {
            final friendship = friendships[index];
            final otherHandle = friendship.getOtherUser(widget.currentUserHandle);
            return _buildFriendTile(otherHandle, friendship);
          },
        );
      },
    );
  }

  Widget _buildFriendTile(String handle, Friendship friendship) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              handle.isNotEmpty ? handle[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
        title: Text('@$handle', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Message button
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF3B82F6), size: 22),
              onPressed: () {
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
            ),
            // More options
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black38),
              color: const Color(0xFFF8FAFC),
              onSelected: (value) {
                if (value == 'unfriend') _showUnfriendDialog(handle);
                if (value == 'block') _showBlockDialog(handle);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'unfriend',
                  child: Row(
                    children: [
                      Icon(Icons.person_remove, color: Colors.orangeAccent, size: 18),
                      SizedBox(width: 8),
                      Text('Unfriend', style: TextStyle(color: Colors.black87)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block, color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Text('Block', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => OtherUserProfileSheet(
              partnerHandle: handle,
              currentUserHandle: widget.currentUserHandle,
              repository: PostRepository(),
            ),
          );
        },
      ),
    );
  }

  void _showUnfriendDialog(String handle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Remove Friend', style: TextStyle(color: Colors.black87)),
        content: Text('Remove @$handle from your friends?', style: const TextStyle(color: Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.repository.unfriend(handle);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('@$handle removed from friends'), backgroundColor: const Color(0xFF374151)),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.orangeAccent)),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog(String handle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Block User', style: TextStyle(color: Colors.black87)),
        content: Text(
          'Block @$handle? They won\'t be able to send you friend requests or messages.',
          style: const TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.repository.blockUser(handle);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('@$handle has been blocked'), backgroundColor: Colors.redAccent),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            child: const Text('Block', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Sent Requests Tab ──
  Widget _buildSentRequests() {
    return StreamBuilder<List<FriendRequest>>(
      stream: widget.repository.getSentRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)));
        }
        final requests = snapshot.data ?? [];
        if (requests.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.send, size: 48, color: Colors.white24),
                SizedBox(height: 12),
                Text('No sent requests', style: TextStyle(color: Colors.black54, fontSize: 15)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        req.receiverHandle.isNotEmpty ? req.receiverHandle[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('@${req.receiverHandle}', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                        const Text('Request pending...', style: TextStyle(color: Colors.amber, fontSize: 12)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await widget.repository.cancelFriendRequest(req.receiverHandle);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Request cancelled'), backgroundColor: Color(0xFF374151)),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
                    child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
