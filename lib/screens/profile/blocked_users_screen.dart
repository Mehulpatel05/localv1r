import 'package:flutter/material.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/block_model.dart';
import '../../services/friend_repository.dart';
import '../../core/action_state/action_state_provider.dart';
import '../../services/user_action_state_service.dart';
import '../../core/services/name_cache_service.dart';
import '../../theme/app_colors.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<BlockEntry> _blockedUsers = [];
  bool _isLoading = true;
  final Set<String> _unblockingHandles = {};

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() => _isLoading = true);
    try {
      final list = await FriendRepository().fetchBlocked();
      if (mounted) {
        setState(() {
          _blockedUsers = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load blocked users: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load blocked users: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _unblockUser(BlockEntry entry) async {
    final handle = entry.blockedHandle;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.divider),
        ),
        title: Text(
          'Unblock ${getDisplayName(handle)}?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Text(
          '${getDisplayName(handle)} will be able to see your posts and message you again.',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _unblockingHandles.add(handle));
    try {
      await FriendRepository().unblockUser(handle);
      ActionStateProvider.instance.toggleBlocked(handle);
      UserActionStateService.instance.setActionState(
        targetId: handle,
        targetType: 'user',
        isBlocked: false,
      );

      if (mounted) {
        setState(() {
          _blockedUsers.removeWhere((u) => u.blockedHandle == handle);
        });
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '${getDisplayName(handle)} has been unblocked',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
                textAlign: TextAlign.center,
              ),
              shape: const StadiumBorder(),
              backgroundColor: AppColors.textPrimary,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(milliseconds: 1800),
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unblock: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _unblockingHandles.remove(handle));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  Semantics(
                    label: 'Back',
                    button: true,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: AppColors.chipBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          size: 19,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Blocked Users',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.03 * 22,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2.5,
                      ),
                    )
                  : _blockedUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: AppColors.chipBg,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.block_outlined,
                                  size: 32,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No blocked users',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Users you block will appear here.',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadBlockedUsers,
                          color: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
                            itemCount: _blockedUsers.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final user = _blockedUsers[index];
                              final handle = user.blockedHandle;
                              final isUnblocking = _unblockingHandles.contains(handle);

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.divider),
                                ),
                                child: Row(
                                  children: [
                                    UserAvatar(
                                      handle: handle,
                                      size: 42,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            getDisplayName(handle),
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          const Text(
                                            'Blocked',
                                            style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      height: 36,
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.textPrimary,
                                          backgroundColor: AppColors.chipBg,
                                          side: const BorderSide(color: AppColors.divider, width: 1.2),
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        onPressed: isUnblocking ? null : () => _unblockUser(user),
                                        child: isUnblocking
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: AppColors.primary,
                                                ),
                                              )
                                            : const Text(
                                                'Unblock',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
