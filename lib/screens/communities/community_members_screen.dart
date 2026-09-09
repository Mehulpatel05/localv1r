import 'package:flutter/material.dart';
import '../../services/community_repository.dart';
import '../../models/community_model.dart';

/// Feature #10: Shows all members of a community
/// Feature #14: Admin can remove members
/// F5: Admin can transfer admin role
class CommunityMembersScreen extends StatefulWidget {
  final CommunityRepository repository;
  final CommunityModel community;

  const CommunityMembersScreen({
    super.key,
    required this.repository,
    required this.community,
  });

  @override
  State<CommunityMembersScreen> createState() => _CommunityMembersScreenState();
}

class _CommunityMembersScreenState extends State<CommunityMembersScreen> {
  bool get _isAdmin =>
      widget.community.adminHandle == widget.repository.currentUserHandle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          '${widget.community.name} — Members',
          style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 16),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: widget.repository.getCommunityMembers(widget.community.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // F3: Error state
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.black26),
                  const SizedBox(height: 12),
                  const Text('Could not load members.',
                      style: TextStyle(color: Colors.black54)),
                ],
              ),
            );
          }
          final members = snapshot.data ?? [];
          if (members.isEmpty) {
            return const Center(
              child: Text('No members found.',
                  style: TextStyle(color: Colors.black54)),
            );
          }
          return ListView.separated(
            itemCount: members.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 70),
            itemBuilder: (context, index) {
              final member = members[index];
              final handle = member['userHandle'] as String? ?? 'Unknown';
              final role = member['role'] as String? ?? 'member';
              final isCurrentUser = handle == widget.repository.currentUserHandle;
              final isThisAdmin = role == 'admin';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isThisAdmin
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF3B82F6),
                  child: Text(
                    handle.isNotEmpty ? handle[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  '@$handle',
                  style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  isThisAdmin ? 'Admin' : 'Member',
                  style: TextStyle(
                    color: isThisAdmin
                        ? const Color(0xFFEF4444)
                        : Colors.black54,
                    fontSize: 12,
                  ),
                ),
                // F5: Long press on any non-admin member shows admin actions
                onLongPress: _isAdmin && !isCurrentUser && !isThisAdmin
                    ? () => _showMemberOptions(context, handle)
                    : null,
                trailing: _isAdmin && !isCurrentUser && !isThisAdmin
                    ? PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.black38),
                        onSelected: (action) {
                          if (action == 'remove') {
                            _confirmRemove(context, handle);
                          } else if (action == 'make_admin') {
                            _confirmTransferAdmin(context, handle);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'make_admin',
                            child: Row(
                              children: [
                                Icon(Icons.admin_panel_settings,
                                    color: Color(0xFF3B82F6), size: 20),
                                SizedBox(width: 12),
                                Text('Make Admin'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Row(
                              children: [
                                Icon(Icons.person_remove,
                                    color: Colors.redAccent, size: 20),
                                SizedBox(width: 12),
                                Text('Remove',
                                    style: TextStyle(color: Colors.redAccent)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  // F5: Show bottom sheet with admin options
  void _showMemberOptions(BuildContext context, String handle) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF3B82F6),
                child: Icon(Icons.admin_panel_settings, color: Colors.white),
              ),
              title: const Text('Make Admin',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Transfer admin rights to @$handle'),
              onTap: () {
                Navigator.pop(context);
                _confirmTransferAdmin(context, handle);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.redAccent,
                child: Icon(Icons.person_remove, color: Colors.white),
              ),
              title: const Text('Remove Member',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.redAccent)),
              subtitle: Text('Remove @$handle from this community'),
              onTap: () {
                Navigator.pop(context);
                _confirmRemove(context, handle);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // F5: Confirm admin transfer dialog
  Future<void> _confirmTransferAdmin(BuildContext context, String handle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer Admin?'),
        content: Text(
            'Make @$handle the new admin?\n\nYou will become a regular member.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF3B82F6)),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.repository.transferAdmin(widget.community.id, handle);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('@$handle is now the admin.')),
        );
        Navigator.pop(context); // Go back — current user is no longer admin
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _confirmRemove(BuildContext context, String handle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member?'),
        content: Text('Remove @$handle from this community?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.repository.removeMember(widget.community.id, handle);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('@$handle removed successfully.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}