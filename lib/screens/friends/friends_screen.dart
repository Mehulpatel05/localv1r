import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/friend_repository.dart';
import '../../services/post_repository.dart';
import '../../models/friendship_model.dart';
import '../../models/friend_request_model.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/name_cache_service.dart';
import '../chat/personal_chat_screen.dart';
import '../profile/other_user_profile_sheet.dart';
import 'discover_people_screen.dart';
import 'friend_requests_screen.dart';
import '../rewards/invite_earn_screen.dart';
import '../../core/widgets/verified_badge.dart';
import '../../theme/app_colors.dart';

enum FriendsTab { requests, friends, sent }

class FriendsScreen extends StatefulWidget {
  final FriendRepository repository;
  final String currentUserHandle;
  final FriendsTab initialTab;
  final bool showTabBar;

  const FriendsScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
    this.initialTab = FriendsTab.friends,
    this.showTabBar = true,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Set<String> _processingHandles = {};
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
    widget.repository.refreshAll();
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

  Future<void> _acceptInlineRequest(FriendRequest req) async {
    final handle = req.senderHandle;
    if (_processingHandles.contains(handle)) return;

    setState(() {
      _processingHandles.add(handle);
    });

    try {
      await widget.repository.acceptFriendRequest(handle);
      _showDarkPillToast(
        message: "You're now friends with ${getDisplayName(handle)}",
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.primary,
      );
    } catch (e) {
      _showDarkPillToast(
        message: 'Failed to accept: $e',
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingHandles.remove(handle);
        });
      }
    }
  }

  Future<void> _declineInlineRequest(FriendRequest req) async {
    final handle = req.senderHandle;
    if (_processingHandles.contains(handle)) return;

    setState(() {
      _processingHandles.add(handle);
    });

    try {
      await widget.repository.rejectFriendRequest(handle);
      _showDarkPillToast(
        message: 'Request removed',
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.textMuted,
      );
    } catch (e) {
      _showDarkPillToast(
        message: 'Failed to ignore: $e',
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingHandles.remove(handle);
        });
      }
    }
  }

  void _showFriendMoreMenu(String handle) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: AppColors.chipBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_remove_outlined, color: AppColors.textPrimary, size: 20),
                ),
                title: const Text(
                  'Unfriend',
                  style: TextStyle(
                    color: AppColors.textPrimary,
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
                    color: AppColors.errorSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.block_flipped, color: AppColors.error, size: 20),
                ),
                title: const Text(
                  'Block',
                  style: TextStyle(
                    color: AppColors.error,
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
      backgroundColor: AppColors.surface,
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
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Remove friend?',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${handle.displayHandle} will be removed from your friends.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
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
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textPrimary,
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
                        backgroundColor: AppColors.error,
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
                            message: '${handle.displayHandle} removed from your friends',
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
      backgroundColor: AppColors.surface,
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
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Block ${getDisplayName(handle)}?',
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "They won't be able to send you friend requests or messages.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
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
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textPrimary,
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
                        backgroundColor: AppColors.error,
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
                            message: '${handle.displayHandle} has been blocked',
                            icon: Icons.check_circle_rounded,
                            iconColor: AppColors.error,
                          );
                        } catch (e) {
                          _showDarkPillToast(
                            message: 'Error: $e',
                            icon: Icons.error_outline_rounded,
                            iconColor: AppColors.error,
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

  void _openDiscoverPeople({String? initialQuery}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoverPeopleScreen(
          repository: widget.repository,
          currentUserHandle: widget.currentUserHandle,
          initialQuery: initialQuery,
        ),
      ),
    ).then((_) {
      widget.repository.refreshAll();
    });
  }

  void _openFriendRequestsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendRequestsScreen(
          repository: widget.repository,
          currentUserHandle: widget.currentUserHandle,
        ),
      ),
    ).then((_) {
      widget.repository.refreshAll();
    });
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
                'Friends',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                'Your Nearhood neighbours',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.card_giftcard_rounded,
                color: Color(0xFFD97706),
                size: 22,
              ),
              tooltip: 'Invite friends & earn points',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InviteEarnScreen(currentUserHandle: widget.currentUserHandle),
                  ),
                );
              },
            ),
            StreamBuilder<List<FriendRequest>>(
              stream: widget.repository.getPendingRequests(limit: 100),
              builder: (context, snapshot) {
                final count = snapshot.data?.length ?? 0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      tooltip: 'Search new people',
                      onPressed: () => _openDiscoverPeople(),
                    ),
                    if (count > 0)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surface,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Column(
          children: [
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                    hintText: 'Search friends, handle or name...',
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
            Expanded(
              child: _buildFriendsTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsTab() {
    return StreamBuilder<List<FriendRequest>>(
      stream: widget.repository.getPendingRequests(limit: 100),
      builder: (context, reqSnapshot) {
        final pendingRequests = reqSnapshot.data ?? [];

        return StreamBuilder<List<Friendship>>(
          stream: widget.repository.getFriendsList(limit: 200),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              debugPrint('Error loading friends list: ${snapshot.error}');
              return _buildErrorState();
            }
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return _buildLoadingSkeleton();
            }

            var friendships = snapshot.data ?? [];
            if (_searchQuery.isNotEmpty) {
              friendships = friendships.where((f) {
                final other = f.getOtherUser(widget.currentUserHandle);
                final otherName = f.getOtherUserName(widget.currentUserHandle);
                final cachedName = NameCacheService.instance.getCachedName(other) ?? '';
                return other.toLowerCase().contains(_searchQuery) ||
                    otherName.toLowerCase().contains(_searchQuery) ||
                    cachedName.toLowerCase().contains(_searchQuery);
              }).toList();
            }

            final hasInlineRequests = _searchQuery.isEmpty && pendingRequests.isNotEmpty;

            if (friendships.isEmpty) {
              if (_searchQuery.isNotEmpty) {
                return ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                  children: [
                    _buildSearchDiscoverPrompt(),
                  ],
                );
              }
              if (hasInlineRequests) {
                return ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                  children: [
                    _buildInlineRequestsSection(pendingRequests),
                    const SizedBox(height: 12),
                    _buildEmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'No friends yet',
                      subtitle: 'Accept incoming requests above or find new neighbors to connect with.',
                      actionLabel: 'Find people',
                      onAction: _openDiscoverPeople,
                    ),
                  ],
                );
              }
              return _buildEmptyState(
                icon: Icons.people_outline_rounded,
                title: 'Build your local network',
                subtitle: 'Connect with people from your community and start conversations.',
                actionLabel: 'Find people',
                onAction: _openDiscoverPeople,
              );
            }

            final totalItems = (hasInlineRequests ? 1 : 0) + 1 + friendships.length + (_searchQuery.isNotEmpty ? 1 : 0);

            return ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
              itemCount: totalItems,
              separatorBuilder: (_, index) {
                if (hasInlineRequests && index == 0) {
                  return const SizedBox(height: 6);
                }
                if ((hasInlineRequests && index == 1) || (!hasInlineRequests && index == 0)) {
                  return const SizedBox(height: 10);
                }
                return const SizedBox(height: 10);
              },
              itemBuilder: (context, i) {
                int cursor = 0;
                if (hasInlineRequests) {
                  if (i == cursor) {
                    return _buildInlineRequestsSection(pendingRequests);
                  }
                  cursor++;
                }

                if (i == cursor) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2, top: 4),
                    child: Text(
                      _searchQuery.isEmpty
                          ? 'Your friends · ${friendships.length}'
                          : 'Matching friends · ${friendships.length}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }
                cursor++;

                final friendIndex = i - cursor;
                if (friendIndex < friendships.length) {
                  final friendship = friendships[friendIndex];
                  return _buildFriendCard(friendship);
                }

                return _buildSearchDiscoverPrompt();
              },
            );
          },
        );
      },
    );
  }

  Widget _buildInlineRequestsSection(List<FriendRequest> requests) {
    if (requests.isEmpty || _searchQuery.isNotEmpty) {
      return const SizedBox.shrink();
    }

    final displayRequests = requests.take(3).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Friend requests',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${requests.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _openFriendRequestsScreen,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View all',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.primary,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            children: displayRequests.map((req) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildInlineRequestRow(req),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineRequestRow(FriendRequest req) {
    final handle = req.senderHandle;
    final displayName = NameCacheService.instance.getDisplayName(
      handle,
      fallback: req.senderName,
    );
    final isProcessing = _processingHandles.contains(handle);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.divider,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              showOtherUserProfileSheet(
                context,
                partnerHandle: handle,
                currentUserHandle: widget.currentUserHandle,
                repository: context.read<PostRepository>(),
              );
            },
            child: UserAvatar(
              handle: handle,
              size: 44,
              fontSize: 15.5,
            ),
          ),
          const SizedBox(width: 12),
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          getDisplayName(handle, fallback: displayName),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14.5,
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
                    'Wants to connect',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isProcessing)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.primary,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => _acceptInlineRequest(req),
                  child: const Text(
                    'Accept',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                  onPressed: () => _declineInlineRequest(req),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSearchDiscoverPrompt() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_search_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search "$_searchQuery" on Nearhood',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Find new neighbors to connect with',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _openDiscoverPeople(initialQuery: _searchQuery),
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text(
                'Search new people',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendCard(Friendship friendship) {
    final handle = friendship.getOtherUser(widget.currentUserHandle);
    final displayName = NameCacheService.instance.getDisplayName(
      handle,
      fallback: friendship.otherUserName,
    );

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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          getDisplayName(handle, fallback: displayName),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14.5,
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
                    'Friend',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
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

          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 18),
            onPressed: () => _showFriendMoreMenu(handle),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.chipBg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.divider,
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
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
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.chipBg,
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
                        color: AppColors.chipBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 160,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.chipBg,
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
                  color: AppColors.chipBg,
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
                color: AppColors.errorSoft,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Couldn't load neighbours",
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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
}
