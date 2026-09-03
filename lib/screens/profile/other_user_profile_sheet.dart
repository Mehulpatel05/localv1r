import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/post_repository.dart';
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

  const OtherUserProfileSheet({
    super.key,
    required this.partnerHandle,
    required this.currentUserHandle,
    required this.repository,
  });

  @override
  State<OtherUserProfileSheet> createState() => _OtherUserProfileSheetState();
}

class _OtherUserProfileSheetState extends State<OtherUserProfileSheet> {
  Map<String, dynamic>? _userData;
  int _postCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Fetch user data from Firestore by handle
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('handle', isEqualTo: widget.partnerHandle)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        _userData = query.docs.first.data();
      }

      // Fetch post count
      final posts = await widget.repository.fetchPostsByUser(widget.partnerHandle);
      _postCount = posts.length;
    } catch (e) {
      debugPrint('Error loading other user profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                      widget.partnerHandle.isNotEmpty
                          ? widget.partnerHandle[0].toUpperCase()
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
                  '@${widget.partnerHandle}',
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
                const SizedBox(height: 28),

                // Action buttons
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
                                partnerHandle: widget.partnerHandle,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
