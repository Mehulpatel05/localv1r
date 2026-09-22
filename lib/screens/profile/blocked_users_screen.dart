import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/auth_service.dart';

/// Screen displaying all users blocked by the current user with unblock capability.
/// Strictly follows the Nearhood Black & White design tokens.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;
  final Set<String> _unblockingIds = {};

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final storedUid = await AuthService.instance.getUserId();
      final effectiveUid = user?.uid ?? storedUid;
      final rawHandle = await AuthService.instance.getUserHandle();
      final cleanHandle = (rawHandle ?? '').replaceAll('@', '').trim();

      final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> docsMap = {};

      // 1. Query by blockerUid if available
      if (effectiveUid != null && effectiveUid.isNotEmpty) {
        try {
          final snapByUid = await FirebaseFirestore.instance
              .collection('blocks')
              .where('blockerUid', isEqualTo: effectiveUid)
              .get();
          for (final doc in snapByUid.docs) {
            docsMap[doc.id] = doc;
          }
        } catch (e) {
          debugPrint('Error querying blocks by uid: $e');
        }
      }

      // 2. Query by blockerHandle if available
      if (cleanHandle.isNotEmpty) {
        try {
          final snapByHandle = await FirebaseFirestore.instance
              .collection('blocks')
              .where('blockerHandle', isEqualTo: cleanHandle)
              .get();
          for (final doc in snapByHandle.docs) {
            docsMap[doc.id] = doc;
          }
        } catch (e) {
          debugPrint('Error querying blocks by handle: $e');
        }
      }

      final List<Map<String, dynamic>> users = [];

      for (final doc in docsMap.values) {
        final data = doc.data();
        final blockedUid = (data['blockedUid'] as String?)?.trim() ?? '';
        String blockedHandle = (data['blockedHandle'] as String?)?.replaceAll('@', '').trim() ?? '';
        String photoUrl = '';

        // If blockedHandle is empty, extract from docId pattern "${me}_${them}"
        if (blockedHandle.isEmpty && doc.id.contains('_')) {
          final parts = doc.id.split('_');
          if (parts.length >= 2) {
            blockedHandle = parts.sublist(1).join('_').trim();
          }
        }

        // Try fetching user profile from profiles collection or users collection
        if (blockedHandle.isNotEmpty) {
          try {
            final pDoc = await FirebaseFirestore.instance
                .collection('profiles')
                .doc(blockedHandle)
                .get();
            if (pDoc.exists && pDoc.data() != null) {
              photoUrl = (pDoc.data()?['photoUrl'] as String?) ?? '';
            }
          } catch (_) {}
        }

        if (photoUrl.isEmpty && blockedUid.isNotEmpty) {
          try {
            final uDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(blockedUid)
                .get();
            if (uDoc.exists && uDoc.data() != null) {
              photoUrl = (uDoc.data()?['photoUrl'] as String?) ?? '';
              if (blockedHandle.isEmpty) {
                blockedHandle = (uDoc.data()?['handle'] as String?)?.replaceAll('@', '').trim() ?? '';
              }
            }
          } catch (_) {}
        }

        users.add({
          'docId': doc.id,
          'blockedUid': blockedUid,
          'handle': blockedHandle.isNotEmpty ? blockedHandle : 'User',
          'photoUrl': photoUrl,
        });
      }

      if (mounted) {
        setState(() {
          _blockedUsers = users;
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
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unblockUser(Map<String, dynamic> user) async {
    final c = context.nearhoodColors;
    final docId = user['docId'] as String;
    final handle = user['handle'] as String;

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

    setState(() => _unblockingIds.add(docId));
    try {
      final me = (await AuthService.instance.getUserHandle() ?? '').replaceAll('@', '').trim();
      await FirebaseFirestore.instance.collection('blocks').doc(docId).delete();
      if (me.isNotEmpty && handle.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('blocks').doc('${me}_$handle').delete();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _blockedUsers.removeWhere((u) => u['docId'] == docId);
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
      if (mounted) setState(() => _unblockingIds.remove(docId));
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
                              final docId = user['docId'] as String;
                              final handle = user['handle'] as String;
                              final photoUrl = user['photoUrl'] as String;
                              final isUnblocking = _unblockingIds.contains(docId);

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
                                      photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
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
