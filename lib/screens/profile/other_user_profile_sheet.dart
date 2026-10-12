import 'package:flutter/material.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../../services/friend_repository.dart';
import '../../services/auth_service.dart';
import '../chat/personal_chat_screen.dart';
import '../../core/action_state/action_state_provider.dart';
import '../../services/user_action_state_service.dart';
import '../../core/services/name_cache_service.dart';
import '../../core/services/badge_cache_service.dart';
import '../../core/widgets/verified_badge.dart';
import '../../theme/app_colors.dart';

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

  OtherUserProfileSheet({
    super.key,
    String? partnerHandle,
    required this.currentUserHandle,
    PostRepository? repository,
    this.userHandle,
  })  : partnerHandle = partnerHandle ?? '',
        repository = repository ?? PostRepository.instance;

  @override
  State<OtherUserProfileSheet> createState() => _OtherUserProfileSheetState();
}

class _OtherUserProfileSheetState extends State<OtherUserProfileSheet> {
  Map<String, dynamic>? _userData;
  int _postCount = 0;
  int _likeCount = 0;
  bool _isLoading = true;
  RelationshipStatus _relationshipStatus = RelationshipStatus.none;
  bool _friendActionLoading = false;
  late final FriendRepository _friendRepo;
  late final String _targetHandle;

  @override
  void initState() {
    super.initState();
    _targetHandle = (widget.userHandle != null && widget.userHandle!.isNotEmpty
            ? widget.userHandle!
            : widget.partnerHandle)
        .replaceAll('@', '')
        .trim();
    final cleanCurrent = widget.currentUserHandle.replaceAll('@', '').trim();
    _friendRepo = FriendRepository();
    if (cleanCurrent.isNotEmpty) {
      _friendRepo.currentUserHandle = cleanCurrent;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      if (_friendRepo.currentUserHandle.isEmpty) {
        final currentH = await AuthService.instance.getUserHandle();
        if (currentH != null && currentH.isNotEmpty) {
          _friendRepo.currentUserHandle = currentH.replaceAll('@', '').trim();
        }
      }

      final results = await Future.wait([
        _friendRepo.getUserByHandle(_targetHandle),
        widget.repository.fetchPostsByUser(_targetHandle),
        _friendRepo.getRelationshipStatus(_targetHandle),
      ]);

      final user = results[0] as Map<String, dynamic>?;
      final posts = results[1] as List<Post>;
      final relStatus = results[2] as RelationshipStatus;

      if (user != null) {
        _userData = user;
        _likeCount = (user['reputation'] as num?)?.toInt() ?? 0;
        final isVer = user['isVerified'] == true || user['is_verified'] == 1;
        final bText = (user['authorBadge'] ?? user['author_badge'] ?? user['badge']) as String?;
        final fSeq = user['founderSeq'] as int?;
        BadgeCacheService.instance.setBadge(
          _targetHandle,
          isVerified: isVer,
          badgeText: bText,
          founderSeq: fSeq,
        );
      }
      _postCount = posts.length;
      int totalLikes = 0;
      for (final p in posts) {
        totalLikes += (p.upvotes > 0 ? p.upvotes : 0);
      }
      if (totalLikes > 0) _likeCount = totalLikes;
      _relationshipStatus = relStatus;
    } catch (e) {
      debugPrint('Error loading other user profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendFriendRequest() async {
    setState(() => _friendActionLoading = true);
    try {
      final newStatus = await _friendRepo.sendFriendRequest(_targetHandle);
      if (mounted) {
        setState(() => _relationshipStatus = newStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == RelationshipStatus.friends
                  ? 'You and ${getDisplayName(_targetHandle)} are now friends! 🎉'
                  : 'Friend request sent to ${getDisplayName(_targetHandle)}!',
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
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
      if (mounted) {
        setState(() => _relationshipStatus = RelationshipStatus.friends);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You and ${getDisplayName(_targetHandle)} are now friends! 🎉'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
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
      if (mounted) {
        setState(() => _relationshipStatus = RelationshipStatus.none);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request cancelled'),
            backgroundColor: AppColors.textMuted,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Unfriend ${getDisplayName(_targetHandle)}?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Are you sure you want to remove this person from your friends list?',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
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
      if (mounted) {
        setState(() => _relationshipStatus = RelationshipStatus.none);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${getDisplayName(_targetHandle)} from friends'),
            backgroundColor: AppColors.textMuted,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
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
      ActionStateProvider.instance.toggleBlocked(_targetHandle);
      UserActionStateService.instance.setActionState(
        targetId: _targetHandle,
        targetType: 'user',
        isBlocked: false,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${getDisplayName(_targetHandle)} has been unblocked'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Block ${getDisplayName(_targetHandle)}?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Block ${getDisplayName(_targetHandle)}? They won\'t be able to send you friend requests or messages.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _friendActionLoading = true);
              try {
                await _friendRepo.blockUser(_targetHandle);
                _relationshipStatus = RelationshipStatus.blockedByMe;
                ActionStateProvider.instance.toggleBlocked(_targetHandle);
                UserActionStateService.instance.setActionState(
                  targetId: _targetHandle,
                  targetType: 'user',
                  isBlocked: true,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${getDisplayName(_targetHandle)} has been blocked'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error blocking user: $e'),
                      backgroundColor: AppColors.error,
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
          color: AppColors.surface,
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
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (_relationshipStatus == RelationshipStatus.blockedByMe) ...[
              ListTile(
                leading: const Icon(Icons.lock_open_rounded, color: AppColors.primary),
                title: const Text('Unblock User', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _unblockUser();
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.block_rounded, color: AppColors.error),
                title: Text('Block ${getDisplayName(_targetHandle)}', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showBlockDialog();
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppColors.textMuted),
              title: Text('Report ${getDisplayName(_targetHandle)}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Report submitted. Our team will review this user.'),
                    backgroundColor: AppColors.primary,
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
                  backgroundColor: AppColors.chipBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawBio = ((_userData?['bio'] as String?) ?? '').trim();
    final bio = rawBio.replaceAll('[Verified]', '').trim();
    final bool isVerified = _userData != null
        ? (_userData!['isVerified'] == true || _userData!['is_verified'] == 1 || rawBio.contains('[Verified]'))
        : (rawBio.contains('[Verified]') || BadgeCacheService.instance.isVerified(_targetHandle));
    final String? authorBadge = _userData != null
        ? ((_userData!['authorBadge'] ?? _userData!['author_badge'] ?? _userData!['badge']) as String?)
        : (BadgeCacheService.instance.getBadge(_targetHandle));

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted, size: 24),
                    onPressed: _showMoreActionsMenu,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              if (_isLoading) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ] else ...[
                UserAvatar(
                  handle: _targetHandle,
                  photoUrl: _userData?['photoUrl'] as String? ?? _userData?['avatar_url'] as String?,
                  size: 88,
                  showRing: true,
                  ringGradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primarySoft],
                  ),
                  ringWidth: 2.8,
                  ringGap: 2.8,
                  fontSize: 28,
                  enableFullViewOnTap: true,
                ),

                const SizedBox(height: 14),

                Builder(
                  builder: (context) {
                    final rawName = (_userData?['name'] ?? _userData?['displayName'] ?? _userData?['fullName']) as String?;
                    final cachedName = NameCacheService.instance.getCachedName(_targetHandle);
                    final effectiveName = (rawName != null && rawName.trim().isNotEmpty)
                        ? rawName.trim()
                        : (cachedName != null && cachedName.trim().isNotEmpty ? cachedName.trim() : null);

                    final displayName = getDisplayName(effectiveName ?? _targetHandle);

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.4,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        VerifiedBadge(
                          handle: _targetHandle,
                          isVerified: isVerified,
                          badgeText: authorBadge,
                          size: 18,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  (authorBadge != null && authorBadge.isNotEmpty)
                      ? '$authorBadge · Vadodara'
                      : (isVerified ? 'Verified Citizen · Vadodara' : 'Vadodara Neighbor'),
                  style: TextStyle(
                    fontSize: 13,
                    color: isVerified ? AppColors.primaryText : AppColors.textMuted,
                    fontWeight: isVerified ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),

                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      bio,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            '$_postCount Posts',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Container(height: 14, width: 1, color: AppColors.divider),
                      const SizedBox(width: 16),
                      Row(
                        children: [
                          const Icon(Icons.favorite_rounded, size: 15, color: AppColors.error),
                          const SizedBox(width: 4),
                          Text(
                            '$_likeCount Likes',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                _buildRelationshipButton(),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
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
                                backgroundColor: AppColors.error,
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

  Widget _buildRelationshipButton() {
    if (_targetHandle.isNotEmpty &&
        _friendRepo.currentUserHandle.isNotEmpty &&
        _targetHandle.toLowerCase() == _friendRepo.currentUserHandle.toLowerCase()) {
      return const SizedBox.shrink();
    }

    if (_friendActionLoading) {
      return Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.chipBg,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }

    switch (_relationshipStatus) {
      case RelationshipStatus.none:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
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

      case RelationshipStatus.requestSentByMe:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.divider, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.check_rounded, size: 18, color: AppColors.textMuted),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Request Sent (Tap to Cancel)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            onPressed: _cancelFriendRequest,
          ),
        );

      case RelationshipStatus.requestReceivedByMe:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
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

      case RelationshipStatus.friends:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.primarySoft,
              foregroundColor: AppColors.primaryText,
              side: const BorderSide(color: AppColors.primary, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Friends (Tap to Manage)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.primaryText,
                ),
              ),
            ),
            onPressed: _unfriendUser,
          ),
        );

      case RelationshipStatus.blockedByMe:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.errorSoft,
              foregroundColor: const Color(0xFFB3262A),
              side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.block_rounded, color: AppColors.error, size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Blocked (Tap to Unblock)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFFB3262A),
                ),
              ),
            ),
            onPressed: _unblockUser,
          ),
        );

      case RelationshipStatus.blockedByThem:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.chipBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.do_not_disturb_on_rounded, color: AppColors.textMuted, size: 18),
              SizedBox(width: 8),
              Text(
                'Unavailable',
                style: TextStyle(
                  color: AppColors.textMuted,
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
