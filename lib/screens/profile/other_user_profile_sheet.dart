import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/post_repository.dart';
import '../../services/friend_repository.dart';
import '../chat/personal_chat_screen.dart';

/// Shows a bottom sheet with another user's profile
/// Called when tapping a username in the feed that is NOT the current user.
Future<void> showOtherUserProfileSheet(
  BuildContext context, {
  required String partnerHandle,
  required String currentUserHandle,
  required PostRepository repository,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => OtherUserProfileSheet(
      partnerHandle: partnerHandle,
      currentUserHandle: currentUserHandle,
      repository: repository,
    ),
  );
}

class OtherUserProfileSheet extends StatefulWidget {
  final String partnerHandle;
  final String currentUserHandle;
  final PostRepository repository;
  // Accept optional userHandle for backwards compatibility
  final String? userHandle;

  const OtherUserProfileSheet({
    super.key,
    String? partnerHandle,
    required this.currentUserHandle,
    PostRepository? repository,
    this.userHandle,
  })  : partnerHandle = partnerHandle ?? '',
        repository = repository ?? const _DummyRepo();

  @override
  State<OtherUserProfileSheet> createState() => _OtherUserProfileSheetState();
}

// Dummy repo for when repository is not passed (e.g. from FriendsScreen)
class _DummyRepo implements PostRepository {
  const _DummyRepo();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OtherUserProfileSheetState extends State<OtherUserProfileSheet> {
  Map<String, dynamic>? _userData;
  int _postCount = 0;
  bool _isLoading = true;
  RelationshipStatus _relationshipStatus = RelationshipStatus.none;
  bool _friendActionLoading = false;
  late final FriendRepository _friendRepo;
  late final String _targetHandle;

  @override
  void initState() {
    super.initState();
    _targetHandle = widget.userHandle ?? widget.partnerHandle;
    _friendRepo = FriendRepository()..currentUserHandle = widget.currentUserHandle;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Fetch user data from Firestore by handle
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('handle', isEqualTo: _targetHandle)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        _userData = query.docs.first.data();
      }

      // Fetch post count (only if real repository provided)
      try {
        final posts = await widget.repository.fetchPostsByUser(_targetHandle);
        _postCount = posts.length;
      } catch (_) {}

      // Check relationship status
      _relationshipStatus = await _friendRepo.getRelationshipStatus(_targetHandle);
    } catch (e) {
      debugPrint('Error loading other user profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFriendAction() async {
    setState(() => _friendActionLoading = true);
    try {
      switch (_relationshipStatus) {
        case RelationshipStatus.none:
          await _friendRepo.sendFriendRequest(_targetHandle);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Friend request sent to @$_targetHandle!'), backgroundColor: const Color(0xFF3B82F6)),
            );
          }
          break;
        case RelationshipStatus.requestReceivedByMe:
          await _friendRepo.acceptFriendRequest(_targetHandle);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('You and @$_targetHandle are now friends! 🎉'), backgroundColor: const Color(0xFF10B981)),
            );
          }
          break;
        case RelationshipStatus.requestSentByMe:
          await _friendRepo.cancelFriendRequest(_targetHandle);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Friend request cancelled'), backgroundColor: Color(0xFF374151)),
            );
          }
          break;
        default:
          break;
      }
      _relationshipStatus = await _friendRepo.getRelationshipStatus(_targetHandle);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _friendActionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF151D30),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
                )
              else ...[
                // Avatar
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _targetHandle.isNotEmpty
                          ? _targetHandle[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Handle
                Text(
                  '@$_targetHandle',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),

                // Bio
                if ((_userData?['bio'] as String?)?.isNotEmpty == true) ...[
                  Text(
                    _userData!['bio'] as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                ],

                // Stats chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F293D),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF374151)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.article_outlined, size: 14, color: Color(0xFF60A5FA)),
                      const SizedBox(width: 6),
                      Text(
                        '$_postCount posts',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Friend status button
                _buildFriendButton(),
                const SizedBox(height: 12),

                // Action buttons row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF374151)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Dismiss'),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                        label: const Text(
                          'Send Message',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PersonalChatScreen(
                                currentUserHandle: widget.currentUserHandle,
                                partnerHandle: _targetHandle,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                // Block user option
                const SizedBox(height: 12),
                if (_relationshipStatus != RelationshipStatus.blockedByMe)
                  TextButton.icon(
                    onPressed: () => _showBlockDialog(),
                    icon: const Icon(Icons.block, color: Colors.redAccent, size: 16),
                    label: const Text('Block User', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  )
                else
                  TextButton.icon(
                    onPressed: () async {
                      await _friendRepo.unblockUser(_targetHandle);
                      _relationshipStatus = await _friendRepo.getRelationshipStatus(_targetHandle);
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.lock_open, color: Colors.amber, size: 16),
                    label: const Text('Unblock User', style: TextStyle(color: Colors.amber, fontSize: 12)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendButton() {
    if (_friendActionLoading) {
      return const SizedBox(
        height: 36,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6))),
      );
    }

    switch (_relationshipStatus) {
      case RelationshipStatus.none:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.person_add, size: 18),
            label: const Text('Add Friend', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _handleFriendAction,
          ),
        );
      case RelationshipStatus.requestSentByMe:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.amber,
              side: const BorderSide(color: Colors.amber),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.hourglass_top, size: 18),
            label: const Text('Request Sent (Tap to Cancel)', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _handleFriendAction,
          ),
        );
      case RelationshipStatus.requestReceivedByMe:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Accept Friend Request', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _handleFriendAction,
          ),
        );
      case RelationshipStatus.friends:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
              SizedBox(width: 8),
              Text('Friends ✅', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        );
      case RelationshipStatus.blockedByMe:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, color: Colors.redAccent, size: 18),
              SizedBox(width: 8),
              Text('Blocked', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      case RelationshipStatus.blockedByThem:
        return const SizedBox.shrink();
    }
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151D30),
        title: const Text('Block User', style: TextStyle(color: Colors.white)),
        content: Text(
          'Block @$_targetHandle? They won\'t be able to send you friend requests or messages.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _friendRepo.blockUser(_targetHandle);
              _relationshipStatus = await _friendRepo.getRelationshipStatus(_targetHandle);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('@$_targetHandle has been blocked'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Block', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
