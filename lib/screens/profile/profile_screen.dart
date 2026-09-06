import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../auth/google_login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const ProfileScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  List<Post> _userPosts = [];
  bool _isLoading = true;
  bool _isSavingBio = false;
  bool _isEditingBio = false;
  late TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    _bioController = TextEditingController();
    _loadProfileData();
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    try {
      // ── Load Firestore user doc ────────────────────────────────────────────
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = doc.data() ?? {};
        _userData = {
          'handle': data['handle'] ?? widget.currentUserHandle,
          'email': data['email'] ?? user.email ?? '',
          'bio': data['bio'] ?? '',
          'createdAt': data['createdAt'],
        };
        _bioController.text = _userData!['bio'] as String;
      }

      // ── Wait for repository to finish its initial post load ───────────────
      // If the feed hasn't loaded yet, wait up to 3 seconds so in-memory
      // list is populated before we filter it.
      int waited = 0;
      while (widget.repository.isLoading && waited < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        waited++;
      }

      // ── Fetch this user's posts (in-memory filter → backend fallback) ─────
      _userPosts = await widget.repository.fetchPostsByUser(widget.currentUserHandle);
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveBio() async {
    setState(() => _isSavingBio = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'bio': _bioController.text.trim(),
        });
        setState(() {
          _userData!['bio'] = _bioController.text.trim();
          _isEditingBio = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF10B981),
              content: Text('Bio saved!'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save bio: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingBio = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Sign Out?', style: TextStyle(color: Colors.black87)),
        content: const Text(
          'You will be returned to the login screen.',
          style: TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => GoogleLoginScreen(repository: widget.repository),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  int get _totalUpvotes => _userPosts.fold(0, (sum, p) => sum + p.upvotes);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
          : RefreshIndicator(
              onRefresh: _loadProfileData,
              color: const Color(0xFF3B82F6),
              backgroundColor: Colors.white,
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    backgroundColor: Colors.white,
                    elevation: 0,
                    pinned: true,
                    title: const Text('Profile', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.share, color: Color(0xFF3B82F6)),
                        onPressed: () {
                          Share.share('Hey! Join me on Vadodara Local. My username is @${widget.currentUserHandle}. Download the app now to connect!');
                        },
                      ),
                    ],
                  ),
                  // ── Header / Hero ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Colors.black12),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                      child: Column(
                        children: [
                          // Avatar
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF3B82F6).withOpacity(0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                widget.currentUserHandle.isNotEmpty
                                    ? widget.currentUserHandle[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Handle
                          Text(
                            '@${widget.currentUserHandle}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Email
                          Text(
                            _userData?['email'] as String? ?? '',
                            style: const TextStyle(color: Colors.black54, fontSize: 13),
                          ),
                          const SizedBox(height: 20),

                          // Stats Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStat('${_userPosts.length}', 'Posts'),
                              Container(width: 1, height: 32, color: Colors.black12),
                              _buildStat('$_totalUpvotes', 'Upvotes'),
                              Container(width: 1, height: 32, color: Colors.black12),
                              _buildStat(
                                _userData?['createdAt'] != null
                                    ? _formatDate((_userData!['createdAt'] as dynamic).toDate())
                                    : '—',
                                'Joined',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Bio Section ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline, color: Color(0xFF60A5FA), size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Bio',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              if (!_isEditingBio)
                                GestureDetector(
                                  onTap: () => setState(() => _isEditingBio = true),
                                  child: const Text(
                                    'Edit',
                                    style: TextStyle(color: Color(0xFF3B82F6), fontSize: 13),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_isEditingBio) ...[
                            TextField(
                              controller: _bioController,
                              style: const TextStyle(color: Colors.black87),
                              maxLines: 3,
                              maxLength: 160,
                              decoration: InputDecoration(
                                hintText: 'Tell the city something about yourself...',
                                hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.black12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF1F5F9),
                                counterStyle: const TextStyle(color: Colors.black38),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => setState(() => _isEditingBio = false),
                                  child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B82F6),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  ),
                                  onPressed: _isSavingBio ? null : _saveBio,
                                  child: _isSavingBio
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                                        )
                                      : const Text('Save', style: TextStyle(color: Colors.black87)),
                                ),
                              ],
                            ),
                          ] else
                            Text(
                              (_userData?['bio'] as String?)?.isNotEmpty == true
                                  ? _userData!['bio'] as String
                                  : 'No bio yet. Tap Edit to add one.',
                              style: TextStyle(
                                color: (_userData?['bio'] as String?)?.isNotEmpty == true
                                    ? Colors.black54
                                    : Colors.black38,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // ── My Posts Header ──────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.article_outlined, color: Color(0xFF60A5FA), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'My Posts (${_userPosts.length})',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── My Posts List ────────────────────────────────────────
                  _userPosts.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                const Icon(Icons.edit_note, size: 48, color: Colors.black26),
                                const SizedBox(height: 12),
                                const Text(
                                  'No posts yet.',
                                  style: TextStyle(color: Colors.black54, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildPostCard(_userPosts[index]),
                            childCount: _userPosts.length,
                          ),
                        ),

                  // ── Sign Out ────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _signOut,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.black54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildPostCard(Post post) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.black12),
                ),
                child: Text(
                  '${post.category.icon} ${post.category.label}',
                  style: const TextStyle(color: Colors.black54, fontSize: 11),
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(post.createdAt),
                style: const TextStyle(color: Colors.black38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            post.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black, fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.arrow_upward, size: 14, color: Color(0xFF10B981)),
              const SizedBox(width: 3),
              Text('${post.upvotes}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_downward, size: 14, color: Colors.black38),
              const SizedBox(width: 3),
              Text('${post.downvotes}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(width: 12),
              const Icon(Icons.location_on, size: 13, color: Color(0xFF60A5FA)),
              const SizedBox(width: 3),
              Text('Vadodara', style: const TextStyle(color: Colors.black54, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}
