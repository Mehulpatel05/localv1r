import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../../services/friend_repository.dart';
import '../chat/personal_chat_screen.dart';

/// Shows a bottom sheet with another user's profile
/// Called when tapping a username in the feed that is NOT the current user.
Future<void> showOtherUserProfileSheet(
  BuildContext context, {
  required String partnerHandle,
  required String currentUserHandle,
  PostRepository? repository,
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

// Dummy repo for when repository is not passed (e.g. from FriendsScreen or ChatScreen)
class _DummyRepo implements PostRepository {
  const _DummyRepo();
  @override
  int getTotalUpvotesForUser(String handle) => 0;
  @override
  Future<List<Post>> fetchPostsByUser(String handle) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OtherUserProfileSheetState extends State<OtherUserProfileSheet> {
  Map<String, dynamic>? _userData;
  int _postCount = 0;
  int _upvoteCount = 0;
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
      // 1. Fetch user data from Firestore by handle
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('handle', isEqualTo: _targetHandle)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        _userData = query.docs.first.data();
      } else {
        // Fallback to profiles collection
        final profDoc = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(_targetHandle)
            .get();
        if (profDoc.exists) {
          _userData = profDoc.data();
        }
      }

      // 2. Fetch post count & upvotes
      try {
        if (widget.repository is! _DummyRepo) {
          final posts = await widget.repository.fetchPostsByUser(_targetHandle);
          _postCount = posts.length;
          int totalUpvotes = 0;
          for (final p in posts) {
            totalUpvotes += (p.upvotes > 0 ? p.upvotes : 0);
          }
          _upvoteCount = totalUpvotes;
        } else {
          // Direct Firestore query fallback for posts by user
          final postDocs = await FirebaseFirestore.instance
              .collection('posts')
              .where('authorHandle', isEqualTo: _targetHandle)
              .limit(50)
              .get();
          _postCount = postDocs.docs.length;
          int totalUpvotes = 0;
          for (final doc in postDocs.docs) {
            final up = doc.data()['upvotes'];
            if (up is int && up > 0) totalUpvotes += up;
          }
          _upvoteCount = totalUpvotes;
        }
      } catch (_) {}

      // 3. Check relationship status
      _relationshipStatus = await _friendRepo.getRelationshipStatus(_targetHandle);
    } catch (e) {
      debugPrint('Error loading other user profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendFriendRequest() async {
    setState(() => _friendActionLoading = true);
    try {
      await _friendRepo.sendFriendRequest(_targetHandle);
      _relationshipStatus = RelationshipStatus.requestSentByMe;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Friend request sent to @$_targetHandle!'),
            backgroundColor: const Color(0xFF3B82F6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _friendActionLoading = false);
    }
  }

  Future<void> _acceptFriendRequest() async {
    setState(() => _friendActionLoading = true);
    try {
      await _friendRepo.acceptFriendRequest(_targetHandle);
      _relationshipStatus = RelationshipStatus.friends;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You and @$_targetHandle are now friends! 🎉'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _friendActionLoading = false);
    }
  }

  Future<void> _cancelFriendRequest() async {
    setState(() => _friendActionLoading = true);
    try {
      await _friendRepo.cancelFriendRequest(_targetHandle);
      _relationshipStatus = RelationshipStatus.none;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request cancelled'),
            backgroundColor: Color(0xFF475569),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _friendActionLoading = false);
    }
  }

  Future<void> _unfriendUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Unfriend @$_targetHandle?',
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Are you sure you want to remove this person from your friends list?',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unfriend'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _friendActionLoading = true);
    try {
      await _friendRepo.unfriend(_targetHandle);
      _relationshipStatus = RelationshipStatus.none;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed @$_targetHandle from friends'),
            backgroundColor: const Color(0xFF475569),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _friendActionLoading = false);
    }
  }

  Future<void> _unblockUser() async {
    setState(() => _friendActionLoading = true);
    try {
      await _friendRepo.unblockUser(_targetHandle);
      _relationshipStatus = RelationshipStatus.none;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('@$_targetHandle has been unblocked'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _friendActionLoading = false);
    }
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Block @$_targetHandle?',
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Block @$_targetHandle? They won\'t be able to send you friend requests or messages.',
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _friendActionLoading = true);
              try {
                await _friendRepo.blockUser(_targetHandle);
                _relationshipStatus = RelationshipStatus.blockedByMe;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('@$_targetHandle has been blocked'),
                      backgroundColor: const Color(0xFFEF4444),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error blocking user: $e'),
                      backgroundColor: const Color(0xFFEF4444),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _friendActionLoading = false);
              }
            },
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _showMoreActionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (_relationshipStatus == RelationshipStatus.blockedByMe) ...[
              ListTile(
                leading: const Icon(Icons.lock_open_rounded, color: Color(0xFF10B981)),
                title: const Text('Unblock User', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _unblockUser();
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.block_rounded, color: Color(0xFFEF4444)),
                title: Text('Block @$_targetHandle', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showBlockDialog();
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Color(0xFFF59E0B)),
              title: Text('Report @$_targetHandle', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Report submitted. Our team will review this user.'),
                    backgroundColor: Color(0xFF10B981),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: const Color(0xFFF1F5F9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(String handle) {
    if (handle.isEmpty) return 'U';
    final clean = handle.replaceAll('@', '').replaceAll('.', ' ').trim();
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(_targetHandle);
    final bio = ((_userData?['bio'] as String?) ?? '').trim();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Top Drag Handle & 3-Dots Action Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF64748B), size: 24),
                    onPressed: _showMoreActionsMenu,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              if (_isLoading) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
                ),
              ] else ...[
                // Glowing Avatar
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF818CF8).withValues(alpha: 0.5),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E3A8A),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Handle & Subtitle
                Text(
                  '@$_targetHandle',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Vadodara Neighbor',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),

                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  // Bio Text
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      bio,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Stats Row (Posts & Upvotes)
                ListenableBuilder(
                  listenable: widget.repository is! _DummyRepo ? widget.repository : ValueNotifier(0),
                  builder: (context, _) {
                    int displayUpvotes = _upvoteCount;
                    if (widget.repository is! _DummyRepo) {
                      try {
                        final live = widget.repository.getTotalUpvotesForUser(_targetHandle);
                        displayUpvotes = live;
                      } catch (_) {}
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Text(
                                '$_postCount Posts',
                                style: const TextStyle(
                                  color: Color(0xFF1E293B),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Container(height: 14, width: 1, color: const Color(0xFFCBD5E1)),
                          const SizedBox(width: 16),
                          Row(
                            children: [
                              const Icon(Icons.arrow_upward_rounded, size: 15, color: Color(0xFF10B981)),
                              const SizedBox(width: 4),
                              Text(
                                '$displayUpvotes Upvotes',
                                style: const TextStyle(
                                  color: Color(0xFF1E293B),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 22),

                // Dynamic Relationship Button (6 exact states from image 2)
                _buildRelationshipButton(),

                const SizedBox(height: 10),

                // Message Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: const Text(
                      'Message',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    onPressed: _relationshipStatus == RelationshipStatus.blockedByMe ||
                            _relationshipStatus == RelationshipStatus.blockedByThem
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Cannot message a blocked user.'),
                                backgroundColor: Color(0xFFEF4444),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        : () {
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
            ],
          ),
        ),
      ),
    );
  }

  /// 6 Dynamic Relationship Button States
  Widget _buildRelationshipButton() {
    if (_friendActionLoading) {
      return Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF3B82F6),
          ),
        ),
      );
    }

    switch (_relationshipStatus) {
      // 1. No Relationship -> + Add Friend (Blue)
      case RelationshipStatus.none:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Add Friend',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
            onPressed: _sendFriendRequest,
          ),
        );

      // 2. Request Sent -> ✓ Request Sent (White/Slate border)
      case RelationshipStatus.requestSentByMe:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.check_rounded, size: 18, color: Color(0xFF64748B)),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Request Sent (Tap to Cancel)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF475569),
                ),
              ),
            ),
            onPressed: _cancelFriendRequest,
          ),
        );

      // 3. Request Received -> ✓ Accept Friend Request (Blue)
      case RelationshipStatus.requestReceivedByMe:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Accept Friend Request',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
            onPressed: _acceptFriendRequest,
          ),
        );

      // 4. Friends -> ✓ Friends (Soft Green)
      case RelationshipStatus.friends:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFFECFDF5),
              foregroundColor: const Color(0xFF059669),
              side: const BorderSide(color: Color(0xFFA7F3D0), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Friends (Tap to Manage)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF059669),
                ),
              ),
            ),
            onPressed: _unfriendUser,
          ),
        );

      // 5. Blocked by Me -> ⊘ Blocked (Soft Red)
      case RelationshipStatus.blockedByMe:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFFFEF2F2),
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.block_rounded, color: Color(0xFFEF4444), size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Blocked (Tap to Unblock)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
            onPressed: _unblockUser,
          ),
        );

      // 6. Blocked by Them -> Unavailable (Soft Grey)
      case RelationshipStatus.blockedByThem:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.do_not_disturb_on_rounded, color: Color(0xFF94A3B8), size: 18),
              SizedBox(width: 8),
              Text(
                'Unavailable',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
    }
  }
}
