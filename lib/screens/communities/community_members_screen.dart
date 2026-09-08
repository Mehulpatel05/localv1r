import 'package:flutter/material.dart';
import '../../services/community_repository.dart';
import '../../models/community_model.dart';

/// Feature #10: Shows all members of a community
/// Feature #14: Admin can remove members from here
class CommunityMembersScreen extends StatelessWidget {
  final CommunityRepository repository;
  final CommunityModel community;

  const CommunityMembersScreen({
    super.key,
    required this.repository,
    required this.community,
  });

  bool get isAdmin =>
      community.adminHandle == repository.currentUserHandle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          '${community.name} — Members',
          style: const TextStyle(
              color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: repository.getCommunityMembers(community.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
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
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 70),
            itemBuilder: (context, index) {
              final member = members[index];
              final handle = member['userHandle'] as String? ?? 'Unknown';
              final role = member['role'] as String? ?? 'member';
              final isCurrentUser = handle == repository.currentUserHandle;
              final isThisAdmin = role == 'admin';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isThisAdmin
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF3B82F6),
                  child: Text(
                    handle.isNotEmpty
                        ? handle[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  '@$handle',
                  style: const TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.w600),
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
                trailing: _isAdmin && !isCurrentUser && !isThisAdmin
                    ? IconButton(
                        icon: const Icon(Icons.person_remove,
                            color: Colors.redAccent),
                        tooltip: 'Remove member',
                        onPressed: () =>
                            _confirmRemove(context, handle),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  // Feature #14: Confirm and remove a member
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
      await repository.removeMember(community.id, handle);
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