import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/motion.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/friend_repository.dart';
import '../../services/post_repository.dart';
import '../../models/friend_request_model.dart';
import '../../models/friendship_model.dart';
import '../chat/personal_chat_screen.dart';
import '../profile/other_user_profile_sheet.dart';

enum FriendsTab { requests, friends, sent }

/// Completely upgraded Friends & Connections Screen matching Images 1, 2, & 3
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

class _FriendsScreenState extends State<FriendsScreen> {
  FriendsTab _activeTab = FriendsTab.requests;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchOpen = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();
    if (cleanHandle.isNotEmpty) {
      widget.repository.currentUserHandle = cleanHandle;
    }
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

  // ── Custom Dark Pill Feedback Toast (Image 3 Row 4) ──────────────────────
  void _showDarkPillToast({
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B), // Dark navy
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom Sheets: Menu & Confirmations (Image 3 Row 3) ───────────────────
  void _showFriendMoreMenu(String handle) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_remove_outlined, color: Color(0xFF1E293B), size: 20),
                ),
                title: const Text(
                  'Unfriend',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showUnfriendConfirmationSheet(handle);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.block_flipped, color: Color(0xFFEF4444), size: 20),
                ),
                title: const Text(
                  'Block',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showBlockConfirmationSheet(handle);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnfriendConfirmationSheet(String handle) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Remove friend?',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '@$handle will be removed from your friends.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await widget.repository.unfriend(handle);
                          _showDarkPillToast(
                            message: '@$handle removed from your friends',
                            icon: Icons.check_circle_rounded,
                            iconColor: const Color(0xFFF59E0B),
                          );
                        } catch (e) {
                          _showDarkPillToast(
                            message: 'Error: $e',
                            icon: Icons.error_outline_rounded,
                            iconColor: const Color(0xFFEF4444),
                          );
                        }
                      },
                      child: const Text(
                        'Remove',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBlockConfirmationSheet(String handle) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Block @$handle?',
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "They won't be able to send you friend requests or messages.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await widget.repository.blockUser(handle);
                          _showDarkPillToast(
                            message: '@$handle has been blocked',
                            icon: Icons.check_circle_rounded,
                            iconColor: const Color(0xFFEF4444),
                          );
                        } catch (e) {
                          _showDarkPillToast(
                            message: 'Error: $e',
                            icon: Icons.error_outline_rounded,
                            iconColor: const Color(0xFFEF4444),
                          );
                        }
                      },
                      child: const Text(
                        'Block',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Actions: Accept / Decline / Cancel ────────────────────────────────────
  Future<void> _acceptRequest(String senderHandle) async {
    try {
      await widget.repository.acceptFriendRequest(senderHandle);
      _showDarkPillToast(
        message: "You're now friends with @$senderHandle",
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF10B981),
      );
    } catch (e) {
      _showDarkPillToast(
        message: 'Error: $e',
        icon: Icons.error_outline_rounded,
        iconColor: const Color(0xFFEF4444),
      );
    }
  }

  Future<void> _declineRequest(String senderHandle) async {
    try {
      await widget.repository.rejectFriendRequest(senderHandle);
      _showDarkPillToast(
        message: 'Request declined',
        icon: Icons.remove_circle_outline_rounded,
        iconColor: const Color(0xFF94A3B8),
      );
    } catch (e) {
      _showDarkPillToast(
        message: 'Error: $e',
        icon: Icons.error_outline_rounded,
        iconColor: const Color(0xFFEF4444),
      );
    }
  }

  Future<void> _cancelSentRequest(String receiverHandle) async {
    try {
      await widget.repository.cancelFriendRequest(receiverHandle);
      _showDarkPillToast(
        message: 'Friend request cancelled',
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF94A3B8),
      );
    } catch (e) {
      _showDarkPillToast(
        message: 'Error: $e',
        icon: Icons.error_outline_rounded,
        iconColor: const Color(0xFFEF4444),
      );
    }
  }

  // ── Header & Main Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Friends',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'Your Nearhood connections',
              style: TextStyle(
                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          // Search Toggle Button
          IconButton(
            icon: Icon(
              _isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
            onPressed: () {
              setState(() {
                _isSearchOpen = !_isSearchOpen;
                if (!_isSearchOpen) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          // 3-Dots More Options
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, color: isDark ? Colors.white : const Color(0xFF1E293B)),
            color: isDark ? const Color(0xFF141414) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
            ),
            onSelected: (val) {
              if (val == 'discover') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Browse posts or profiles to connect with more locals!')),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'discover',
                child: Row(
                  children: [
                    Icon(Icons.explore_outlined, color: isDark ? Colors.white : Colors.black, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Discover People',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // Expandable Search Bar
          if (_isSearchOpen)
            Container(
              color: isDark ? Colors.black : Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141414) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Filter by handle...',
                    hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: isDark ? Colors.white60 : const Color(0xFF94A3B8)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),

          // ── Segmented Navigation Capsule (Image 1 Header) ────────
          Container(
            color: isDark ? Colors.black : Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141414) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
              ),
              child: Row(
                children: [
                  // Tab 1: Requests
                  Expanded(
                    child: StreamBuilder<int>(
                      stream: widget.repository.getPendingRequestCount(),
                      builder: (context, snap) {
                        final count = snap.data ?? 0;
                        final isSelected = _activeTab == FriendsTab.requests;
                        return _buildSegmentItem(
                          title: 'Requests',
                          isSelected: isSelected,
                          badgeCount: count,
                          onTap: () => setState(() => _activeTab = FriendsTab.requests),
                        );
                      },
                    ),
                  ),
                  // Tab 2: Friends
                  Expanded(
                    child: _buildSegmentItem(
                      title: 'Friends',
                      isSelected: _activeTab == FriendsTab.friends,
                      onTap: () => setState(() => _activeTab = FriendsTab.friends),
                    ),
                  ),
                  // Tab 3: Sent
                  Expanded(
                    child: _buildSegmentItem(
                      title: 'Sent',
                      isSelected: _activeTab == FriendsTab.sent,
                      onTap: () => setState(() => _activeTab = FriendsTab.sent),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Active Tab View ──────────────────────────────────────
          Expanded(
            child: _buildCurrentTabContent(),
          ),
        ],
      ),
    );
  }

  // ── Segment Navigation Pill Item ──────────────────────────────────────────
  Widget _buildSegmentItem({
    required String title,
    required bool isSelected,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.durationMicro,
        curve: AppMotion.interactiveCurve,
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : Colors.black)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? (isDark ? Colors.black : Colors.white)
                          : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B)),
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  if (badgeCount > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_activeTab) {
      case FriendsTab.requests:
        return _buildRequestsTab();
      case FriendsTab.friends:
        return _buildFriendsTab();
      case FriendsTab.sent:
        return _buildSentTab();
    }
  }

  // ── Tab 1: Requests (Incoming Requests - Image 1) ──────────────────────────
  Widget _buildRequestsTab() {
    return StreamBuilder<List<FriendRequest>>(
      stream: widget.repository.getPendingRequests(limit: 100),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Error loading incoming friend requests: ${snapshot.error}');
          return _buildErrorState();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingSkeleton();
        }

        var requests = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          requests = requests
              .where((r) => r.senderHandle.toLowerCase().contains(_searchQuery))
              .toList();
        }

        if (requests.isEmpty) {
          return _buildEmptyState(
            icon: Icons.person_add_outlined,
            title: 'No new requests',
            subtitle: 'When someone wants to connect with you, their request will appear here.',
            actionLabel: 'Discover people',
            onAction: () {
              Navigator.pop(context);
            },
          );
        }

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final req = requests[i];
            return _buildRequestCard(req);
          },
        );
      },
    );
  }

  Widget _buildRequestCard(FriendRequest req) {
    final handle = req.senderHandle;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Info Row
          InkWell(
            onTap: () {
              showOtherUserProfileSheet(
                context,
                partnerHandle: handle,
                currentUserHandle: widget.currentUserHandle,
                repository: context.read<PostRepository>(),
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                // Circular Avatar with Photo/Gradient
                UserAvatar(
                  handle: handle,
                  size: 52,
                  fontSize: 18,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@$handle',
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Wants to connect with you',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Monochrome Pill Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF262626) : const Color(0xFFF4F4F4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'New connection',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Action Buttons: Accept & Decline
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.white : Colors.black,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => _acceptRequest(handle),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Accept',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0)),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => _declineRequest(handle),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Decline',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Friends (Image 2 Left) ─────────────────────────────────────────
  Widget _buildFriendsTab() {
    return StreamBuilder<List<Friendship>>(
      stream: widget.repository.getFriendsList(limit: 200),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Error loading friends list: ${snapshot.error}');
          return _buildErrorState();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingSkeleton();
        }

        var friendships = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          friendships = friendships.where((f) {
            final other = f.getOtherUser(widget.currentUserHandle);
            return other.toLowerCase().contains(_searchQuery);
          }).toList();
        }

        if (friendships.isEmpty) {
          return _buildEmptyState(
            icon: Icons.people_outline_rounded,
            title: 'Build your local network',
            subtitle: 'Connect with people from your community and start conversations.',
            actionLabel: 'Find people',
            onAction: () => Navigator.pop(context),
          );
        }

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          itemCount: friendships.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final friendship = friendships[i];
            final otherHandle = friendship.getOtherUser(widget.currentUserHandle);
            return _buildFriendCard(otherHandle);
          },
        );
      },
    );
  }

  Widget _buildFriendCard(String handle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          UserAvatar(
            handle: handle,
            size: 48,
            fontSize: 16.5,
            onTap: () {
              showOtherUserProfileSheet(
                context,
                partnerHandle: handle,
                currentUserHandle: widget.currentUserHandle,
                repository: context.read<PostRepository>(),
              );
            },
          ),
          const SizedBox(width: 12),

          // Text details
          Expanded(
            child: GestureDetector(
              onTap: () {
                showOtherUserProfileSheet(
                  context,
                  partnerHandle: handle,
                  currentUserHandle: widget.currentUserHandle,
                  repository: context.read<PostRepository>(),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@$handle',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your friend',
                    style: TextStyle(
                      color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Message Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.white : Colors.black,
              foregroundColor: isDark ? Colors.black : Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
            label: const Text(
              'Message',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
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
          const SizedBox(width: 2),

          // 3-Dots Action Button
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 18),
            onPressed: () => _showFriendMoreMenu(handle),
          ),
        ],
      ),
    );
  }

  // ── Tab 3: Sent (Image 2 Right) ───────────────────────────────────────────
  Widget _buildSentTab() {
    return StreamBuilder<List<FriendRequest>>(
      stream: widget.repository.getSentRequests(limit: 100),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Error loading sent friend requests: ${snapshot.error}');
          return _buildErrorState();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingSkeleton();
        }

        var requests = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          requests = requests
              .where((r) => r.receiverHandle.toLowerCase().contains(_searchQuery))
              .toList();
        }

        if (requests.isEmpty) {
          return _buildEmptyState(
            icon: Icons.access_time_rounded,
            title: 'No pending requests',
            subtitle: 'Friend requests you send will appear here.',
          );
        }

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final req = requests[i];
            return _buildSentCard(req.receiverHandle);
          },
        );
      },
    );
  }

  Widget _buildSentCard(String handle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          UserAvatar(
            handle: handle,
            size: 48,
            fontSize: 16.5,
            onTap: () {
              showOtherUserProfileSheet(
                context,
                partnerHandle: handle,
                currentUserHandle: widget.currentUserHandle,
                repository: context.read<PostRepository>(),
              );
            },
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@$handle',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 7, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(
                      'Request pending',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Cancel Outlined Button
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0)),
              shape: const StadiumBorder(),
            ),
            onPressed: () => _cancelSentRequest(handle),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF475569),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Supporting States: Empty, Skeleton, Error (Image 3) ───────────────────
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular Icon Badge
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: isDark ? Colors.white : Colors.black,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : Colors.black,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: const StadiumBorder(),
                ),
                onPressed: onAction,
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141414) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 110,
                      height: 13,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 160,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 70,
                height: 32,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFEF4444),
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "Couldn't load connections",
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              style: TextStyle(
                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: const StadiumBorder(),
              ),
              onPressed: () => setState(() {}),
              child: const Text(
                'Try again',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helper: Avatar Gradient from Handle ───────────────────────────────────
  LinearGradient _getAvatarGradient(String handle) {
    final gradients = [
      const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1E40AF)]), // Blue
      const LinearGradient(colors: [Color(0xFF991B1B), Color(0xFF7F1D1D)]), // Crimson maroon
      const LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF172554)]), // Navy
      const LinearGradient(colors: [Color(0xFF0D9488), Color(0xFF0F766E)]), // Teal
      const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)]), // Purple
      const LinearGradient(colors: [Color(0xFFC026D3), Color(0xFFA21CAF)]), // Fuchsia
    ];
    final hash = handle.hashCode.abs();
    return gradients[hash % gradients.length];
  }
}
