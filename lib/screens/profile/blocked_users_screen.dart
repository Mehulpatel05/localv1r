import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/block_model.dart';
import '../../services/friend_repository.dart';

/// Screen displaying all users blocked by the current user with unblock capability.
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
        final c = context.nearhoodColors;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load blocked users: $e', style: TextStyle(color: c.btnink)),
            backgroundColor: c.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _unblockUser(BlockEntry entry) async {
    final c = context.nearhoodColors;
    final handle = entry.blockedHandle;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.line),
        ),
        title: Text(
          'Unblock @$handle?',
          style: TextStyle(
            color: c.ink,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Text(
          '@$handle will be able to see your posts and message you again.',
          style: TextStyle(
            color: c.muted,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: c.muted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.btn,
              foregroundColor: c.btnink,
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

      if (mounted) {
        setState(() {
          _blockedUsers.removeWhere((u) => u.blockedHandle == handle);
        });
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '@$handle has been unblocked',
                style: TextStyle(color: c.btnink, fontWeight: FontWeight.w600, fontSize: 13.5),
                textAlign: TextAlign.center,
              ),
              shape: const StadiumBorder(),
              backgroundColor: c.btn,
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
            content: Text('Failed to unblock: $e', style: TextStyle(color: c.btnink)),
            backgroundColor: c.danger,
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
    final c = context.nearhoodColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
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
                        decoration: BoxDecoration(
                          color: c.field,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          size: 19,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Blocked Users',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.03 * 22,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: c.ink,
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
                                  color: c.field,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.block_outlined,
                                  size: 32,
                                  color: c.muted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No blocked users',
                                style: TextStyle(
                                  color: c.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Users you block will appear here.',
                                style: TextStyle(
                                  color: c.muted,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadBlockedUsers,
                          color: c.ink,
                          backgroundColor: c.bg,
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
                                  color: c.bg,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: c.line),
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
                                            '@$handle',
                                            style: TextStyle(
                                              color: c.ink,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Blocked',
                                            style: TextStyle(
                                              color: c.muted,
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
                                          foregroundColor: c.ink,
                                          side: BorderSide(color: c.line, width: 1.2),
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        onPressed: isUnblocking ? null : () => _unblockUser(user),
                                        child: isUnblocking
                                            ? SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: c.ink,
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
