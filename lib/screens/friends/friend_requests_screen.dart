import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/motion.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/friend_repository.dart';
import '../../services/post_repository.dart';
import '../../models/friend_request_model.dart';
import '../../core/services/name_cache_service.dart';
import '../profile/other_user_profile_sheet.dart';
import '../../core/widgets/verified_badge.dart';
import '../../theme/app_colors.dart';

enum FriendRequestsTab { requests, sent }

class FriendRequestsScreen extends StatefulWidget {
  final FriendRepository repository;
  final String currentUserHandle;
  final FriendRequestsTab initialTab;

  const FriendRequestsScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
    this.initialTab = FriendRequestsTab.requests,
  });

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  late FriendRequestsTab _activeTab;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
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
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

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
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
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

  Future<void> _acceptRequest(String senderHandle) async {
    try {
      await widget.repository.acceptFriendRequest(senderHandle);
      _showDarkPillToast(
        message: "You're now friends with ${getDisplayName(senderHandle)}",
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.primary,
      );
    } catch (e) {
      _showDarkPillToast(
        message: 'Error: $e',
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.error,
      );
    }
  }

  Future<void> _declineRequest(String senderHandle) async {
    try {
      await widget.repository.rejectFriendRequest(senderHandle);
      _showDarkPillToast(
        message: 'Request declined',
        icon: Icons.remove_circle_outline_rounded,
        iconColor: AppColors.textMuted,
      );
    } catch (e) {
      _showDarkPillToast(
        message: 'Error: $e',
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.error,
      );
    }
  }

  Future<void> _cancelSentRequest(String receiverHandle) async {
    try {
      await widget.repository.cancelFriendRequest(receiverHandle);
      _showDarkPillToast(
        message: 'Friend request cancelled',
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.textMuted,
      );
    } catch (e) {
      _showDarkPillToast(
        message: 'Error: $e',
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _searchQuery.isEmpty && !_searchFocusNode.hasFocus,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _searchController.clear();
        _searchFocusNode.unfocus();
        setState(() {
          _searchQuery = '';
        });
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () {
              if (_searchController.text.isNotEmpty || _searchFocusNode.hasFocus) {
                _searchController.clear();
                _searchFocusNode.unfocus();
                setState(() {
                  _searchQuery = '';
                });
              } else {
                Navigator.pop(context);
              }
            },
          ),
          titleSpacing: 0,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Friend Requests',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                'Manage incoming & sent neighbour requests',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    hintText: 'Filter requests by handle or name...',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                            onPressed: () {
                              _searchController.clear();
                              _searchFocusNode.unfocus();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: Container(
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: StreamBuilder<int>(
                        stream: widget.repository.getPendingRequestCount(),
                        builder: (context, snap) {
                          final count = snap.data ?? 0;
                          final isSelected = _activeTab == FriendRequestsTab.requests;
                          return _buildSegmentItem(
                            title: 'Received',
                            isSelected: isSelected,
                            badgeCount: count,
                            onTap: () => setState(() => _activeTab = FriendRequestsTab.requests),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: _buildSegmentItem(
                        title: 'Sent',
                        isSelected: _activeTab == FriendRequestsTab.sent,
                        onTap: () => setState(() => _activeTab = FriendRequestsTab.sent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _activeTab == FriendRequestsTab.requests
                  ? _buildRequestsTab()
                  : _buildSentTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentItem({
    required String title,
    required bool isSelected,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.durationMicro,
        curve: AppMotion.interactiveCurve,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
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
                          ? Colors.white
                          : AppColors.textMuted,
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  if (badgeCount > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
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
          if (_searchQuery.isNotEmpty) {
            return Center(
              child: Text(
                'No requests matching "$_searchQuery"',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
            );
          }
          return _buildEmptyState(
            icon: Icons.person_add_outlined,
            title: 'No new requests',
            subtitle: 'When someone wants to connect with you, their request will appear here.',
          );
        }

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          itemCount: requests.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
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
    final displayName = NameCacheService.instance.getDisplayName(handle, fallback: req.senderName);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              getDisplayName(handle, fallback: displayName),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          VerifiedBadge(handle: handle, size: 14),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Wants to connect with you',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'New neighbour',
                          style: TextStyle(
                            color: AppColors.textPrimary,
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
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
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
                    backgroundColor: AppColors.chipBg,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: const BorderSide(color: AppColors.divider),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => _declineRequest(handle),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Decline',
                      style: TextStyle(
                        color: AppColors.textPrimary,
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
          requests = requests.where((r) {
            final handle = r.receiverHandle;
            final name = r.receiverName ?? '';
            final cached = NameCacheService.instance.getCachedName(handle) ?? '';
            return handle.toLowerCase().contains(_searchQuery) ||
                name.toLowerCase().contains(_searchQuery) ||
                cached.toLowerCase().contains(_searchQuery);
          }).toList();
        }

        if (requests.isEmpty) {
          if (_searchQuery.isNotEmpty) {
            return Center(
              child: Text(
                'No sent requests matching "$_searchQuery"',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
            );
          }
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
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final req = requests[i];
            return _buildSentCard(req);
          },
        );
      },
    );
  }

  Widget _buildSentCard(FriendRequest req) {
    final handle = req.receiverHandle;
    final displayName = NameCacheService.instance.getDisplayName(handle, fallback: req.receiverName);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        getDisplayName(handle, fallback: displayName),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    VerifiedBadge(handle: handle, size: 14),
                  ],
                ),
                const SizedBox(height: 3),
                const Row(
                  children: [
                    Icon(Icons.circle, size: 7, color: Color(0xFFD97706)),
                    SizedBox(width: 4),
                    Text(
                      'Request pending',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.chipBg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              side: const BorderSide(color: AppColors.divider),
              shape: const StadiumBorder(),
            ),
            onPressed: () => _cancelSentRequest(handle),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.chipBg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.divider,
                ),
              ),
              child: Icon(icon, size: 38, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13.5,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      itemCount: 4,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: 78,
          decoration: BoxDecoration(
            color: AppColors.chipBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.error),
          const SizedBox(height: 12),
          const Text(
            'Unable to load requests',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {}),
            child: const Text('Try Again', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
