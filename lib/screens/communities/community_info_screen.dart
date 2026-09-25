import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/community_model.dart';
import '../../services/community_repository.dart';
import 'admin_permissions_sheet.dart';
import 'community_chat_screen.dart';
import 'edit_community_screen.dart';
import 'join_requests_screen.dart';

class CommunityInfoScreen extends StatefulWidget {
  final CommunityModel community;
  final CommunityRepository repository;

  const CommunityInfoScreen({
    super.key,
    required this.community,
    required this.repository,
  });

  @override
  State<CommunityInfoScreen> createState() => _CommunityInfoScreenState();
}

class _CommunityInfoScreenState extends State<CommunityInfoScreen> {
  late CommunityModel _community;
  bool _isPendingRequested = false;

  @override
  void initState() {
    super.initState();
    _community = widget.community;
    _refreshCommunityDetails();
  }

  Future<void> _refreshCommunityDetails() async {
    final updated = await widget.repository.getCommunityById(_community.id, forceRefresh: true);
    if (updated != null && mounted) {
      setState(() {
        _community = updated;
      });
    }
  }

  String _formatMemberCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    final typeStr = _community.isChannel ? 'channel' : 'group';
    final visStr = _community.isPrivate ? 'Private' : 'Public';
    final subtitle = '$visStr $typeStr · ${_formatMemberCount(_community.memberCount)} ${_community.isChannel ? 'subscribers' : 'members'}';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_community.isAdmin)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: textColor),
              tooltip: 'Edit Community',
              onPressed: () async {
                final updated = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditCommunityScreen(
                      community: _community,
                      repository: widget.repository,
                    ),
                  ),
                );
                if (updated == true && mounted) {
                  _refreshCommunityDetails();
                }
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          children: [
            // ── Top Center Logo ──
            _buildCenterLogo(size: 76),
            const SizedBox(height: 14),

            // ── Title & Subtitle ──
            Text(
              _community.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: textColor,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),

            if (_community.username != null && _community.username!.isNotEmpty) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: 'app://c/${_community.username}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Public link copied to clipboard!')),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '@${_community.username}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF3B82F6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF3B82F6)),
                  ],
                ),
              ),
            ] else if (_community.inviteLink != null && _community.inviteLink!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: 'app://c/join/${_community.inviteLink}'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invite link copied to clipboard!')),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link_rounded, size: 15, color: Color(0xFF3B82F6)),
                        const SizedBox(width: 4),
                        Text(
                          'join/${_community.inviteLink}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF3B82F6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF3B82F6)),
                      ],
                    ),
                  ),
                  if (_community.isAdmin) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _regenerateInviteLink,
                      child: const Tooltip(
                        message: 'Revoke old link & generate new one',
                        child: Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ],
              ),
            ],

            if (_community.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _community.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                  height: 1.4,
                ),
              ),
            ],

            const SizedBox(height: 22),

            // ── Quick Actions / Join Button ──
            if (widget.repository.isMemberCached(_community.id) || _community.isMember) ...[
              _buildQuickActionsRow(cardBg, textColor, isDark),
              const SizedBox(height: 20),

              // ── Join Requests Tile (If Admin/Owner) ──
              if (_community.isAdmin) ...[
                _buildJoinRequestsBanner(cardBg, textColor, isDark),
                const SizedBox(height: 16),
              ],

              // ── PERMISSIONS Card (Matching Image 1) ──
              _buildPermissionsCard(cardBg, textColor, isDark),

              const SizedBox(height: 20),

              // ── MEMBERS List (Matching Image 1) ──
              _buildMembersSection(cardBg, textColor, isDark),
            ] else ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: _isPendingRequested
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFD97706), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706)),
                        label: const Text(
                          'Join Request Pending Review',
                          style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Join request already submitted. Awaiting admin approval.')),
                          );
                        },
                      )
                    : ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.group_add_rounded, color: Colors.white),
                        label: Text(
                          'Join ${_community.isChannel ? 'Channel' : 'Group'}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(context);
                          try {
                            final res = await widget.repository.joinCommunity(_community.id);
                            if (res.status == JoinStatus.pending) {
                              if (mounted) {
                                setState(() => _isPendingRequested = true);
                              }
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Join request submitted for review!')),
                              );
                            } else if (res.status == JoinStatus.joined) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('Joined ${_community.name}!')),
                              );
                              nav.pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => CommunityChatScreen(
                                    community: _community.copyWith(myRole: 'member'),
                                    repository: widget.repository,
                                  ),
                                ),
                              );
                            } else if (res.status == JoinStatus.error) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(res.message.isNotEmpty ? res.message : 'Failed to join community')),
                              );
                            }
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Failed to join: $e')),
                            );
                          }
                        },
                      ),
              ),
              const SizedBox(height: 20),
            ],

            if (_community.isOwner) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444)),
                  label: const Text(
                    'Delete Community',
                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                  ),
                  onPressed: _confirmDeleteCommunity,
                ),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Rounded-Rect Logo ──
  Widget _buildCenterLogo({double size = 76}) {
    final isChannel = _community.isChannel;
    final bgColor = isChannel ? const Color(0xFFE0F2FE) : const Color(0xFFDCFCE7);
    final iconColor = isChannel ? const Color(0xFF0284C7) : const Color(0xFF16A34A);
    final defaultIcon = isChannel ? Icons.campaign_rounded : Icons.group_rounded;

    if (_community.imageUrl != null && _community.imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          _community.imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _buildFallbackBox(size, bgColor, defaultIcon, iconColor),
        ),
      );
    }
    return _buildFallbackBox(size, bgColor, defaultIcon, iconColor);
  }

  Widget _buildFallbackBox(double size, Color bgColor, IconData icon, Color iconColor) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(
        icon,
        color: iconColor,
        size: size * 0.52,
      ),
    );
  }

  // ── Quick Actions Row ──
  Widget _buildQuickActionsRow(Color cardBg, Color textColor, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCircularActionButton(
          icon: _community.isMuted ? Icons.notifications_off_rounded : Icons.notifications_none_rounded,
          label: _community.isMuted ? 'Muted' : 'Mute',
          isActive: _community.isMuted,
          onTap: () {
            if (_community.isMuted) {
              widget.repository.muteCommunity(_community.id, 0);
              setState(() {
                _community = _community.copyWith(isMuted: false, mutedUntil: 0);
              });
            } else {
              _showMuteOptions();
            }
          },
        ),
        _buildCircularActionButton(
          icon: _community.isArchived ? Icons.unarchive_rounded : Icons.archive_outlined,
          label: _community.isArchived ? 'Archived' : 'Archive',
          isActive: _community.isArchived,
          onTap: () {
            final newArchived = !_community.isArchived;
            widget.repository.archiveCommunity(_community.id, newArchived);
            setState(() {
              _community = _community.copyWith(isArchived: newArchived);
            });
          },
        ),
        _buildCircularActionButton(
          icon: Icons.search_rounded,
          label: 'Search',
          onTap: () {
            Navigator.pop(context);
          },
        ),
        _buildCircularActionButton(
          icon: Icons.logout_rounded,
          label: 'Leave',
          isDestructive: true,
          onTap: _confirmLeave,
        ),
      ],
    );
  }

  Widget _buildCircularActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    bool isDestructive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDestructive
        ? const Color(0xFFEF4444)
        : (isActive ? const Color(0xFF3B82F6) : (isDark ? Colors.white : const Color(0xFF0F172A)));
    final bgColor = isDestructive
        ? const Color(0xFFFEE2E2)
        : (isActive
            ? const Color(0xFFDBEAFE)
            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)));

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Join Requests Banner ──
  Widget _buildJoinRequestsBanner(Color cardBg, Color textColor, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: ListTile(
        leading: const Icon(Icons.how_to_reg_rounded, color: Color(0xFFD97706)),
        title: const Text(
          'Join Requests',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
        ),
        subtitle: const Text(
          'Review pending member requests',
          style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFD97706)),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JoinRequestsScreen(
                community: _community,
                repository: widget.repository,
              ),
            ),
          );
          _refreshCommunityDetails();
        },
      ),
    );
  }

  // ── Permissions Card (Exact match to Image 1) ──
  Widget _buildPermissionsCard(Color cardBg, Color textColor, bool isDark) {
    final whoCanSend = _community.whoCanSend == 'admins_only' ? 'Admins only' : 'All members';
    final mediaAllowed = _community.canSendMedia ? 'All members' : 'Admins only';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PERMISSIONS',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              if (_community.isAdmin)
                InkWell(
                  onTap: _showPermissionsEditor,
                  child: const Text(
                    'Edit',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Row 1: Who can send messages
          _buildPermissionItem(
            label: 'Who can send messages',
            value: whoCanSend,
            textColor: textColor,
          ),
          const Divider(height: 20),

          // Row 2: Media & files
          _buildPermissionItem(
            label: 'Media & files',
            value: mediaAllowed,
            textColor: textColor,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionItem({
    required String label,
    required String value,
    required Color textColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // ── Members Section (Matching Image 1) ──
  Widget _buildMembersSection(Color cardBg, Color textColor, bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              _community.isChannel
                  ? 'SUBSCRIBERS · ${_community.memberCount}'
                  : 'MEMBERS · ${_community.memberCount}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: widget.repository.getCommunityMembers(_community.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final rawMembers = snapshot.data ?? [];
              // For channels, non-admins only see owner & admins
              final members = (_community.isChannel && !_community.isAdmin)
                  ? rawMembers.where((m) => (m['role'] == 'owner' || m['role'] == 'admin')).toList()
                  : rawMembers;

              if (members.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No members found', style: TextStyle(color: Color(0xFF64748B))),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: members.length,
                separatorBuilder: (context, index) => const Divider(height: 1, indent: 64),
                itemBuilder: (context, index) {
                  final member = members[index];
                  final handle = (member['userHandle'] ?? '').toString().replaceAll('@', '');
                  final role = (member['role'] ?? 'member').toString().toLowerCase();

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF3B82F6),
                      child: Text(
                        handle.isNotEmpty ? handle[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      '@$handle',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    trailing: _buildRoleBadge(role),
                    onTap: () {
                      if (_community.isAdmin) {
                        _showMemberActionSheet(member);
                      }
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Role Pill (Owner blue, Admin green, Member gray) ──
  Widget _buildRoleBadge(String role) {
    Color bg;
    Color fg;
    String label;

    switch (role) {
      case 'owner':
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0284C7);
        label = 'Owner';
        break;
      case 'admin':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        label = 'Admin';
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
        label = 'Member';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  void _showPermissionsEditor() async {
    final updated = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdminPermissionsSheet(
        community: _community,
        repository: widget.repository,
      ),
    );
    if (updated == true && mounted) {
      _refreshCommunityDetails();
    }
  }

  void _showMemberActionSheet(Map<String, dynamic> member) {
    final handle = member['userHandle']?.toString() ?? '';
    final role = (member['role'] ?? 'member').toString().toLowerCase();
    final isTargetOwner = role == 'owner';
    final isTargetAdmin = role == 'admin';

    final myRole = _community.myRole.toLowerCase();
    final myPerms = _community.myPermissions;
    final canManageAdmins = myRole == 'owner' || (myRole == 'admin' && (myPerms['can_manage_admins'] == true));
    final canRemoveMembers = myRole == 'owner' || (myRole == 'admin' && (myPerms['can_remove_members'] == true));
    final canKickTarget = isTargetAdmin ? canManageAdmins : canRemoveMembers;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Manage @$handle',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),

            if (!isTargetOwner) ...[
              if (isTargetAdmin && canManageAdmins) ...[
                ListTile(
                  leading: const Icon(Icons.security_rounded),
                  title: const Text('Edit Admin Permissions'),
                  onTap: () {
                    Navigator.pop(ctx);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => AdminPermissionsSheet(
                        community: _community,
                        repository: widget.repository,
                        targetAdminHandle: handle,
                        initialPermissions: member['permissions'] as Map<String, dynamic>?,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_downward_rounded, color: Colors.orange),
                  title: const Text('Dismiss Admin (Demote to Member)'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await widget.repository.updateMemberRole(_community.id, handle, 'member', null);
                    _refreshCommunityDetails();
                  },
                ),
              ] else if (!isTargetAdmin && canManageAdmins) ...[
                ListTile(
                  leading: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF16A34A)),
                  title: const Text('Promote to Admin'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await widget.repository.updateMemberRole(_community.id, handle, 'admin', null);
                    _refreshCommunityDetails();
                  },
                ),
              ],

              if (_community.isOwner)
                ListTile(
                  leading: const Icon(Icons.stars_rounded, color: Color(0xFF0284C7)),
                  title: const Text('Transfer Ownership'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmTransferOwnership(handle);
                  },
                ),

              if (canKickTarget)
                ListTile(
                  leading: const Icon(Icons.person_remove_rounded, color: Colors.red),
                  title: const Text('Remove from Community', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await widget.repository.removeMember(_community.id, handle);
                    _refreshCommunityDetails();
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmTransferOwnership(String newOwnerHandle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Transfer Ownership to @$newOwnerHandle?'),
        content: const Text(
          'You will be demoted to an Admin. Only the new owner will be able to delete this community or transfer ownership again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.repository.transferOwnership(_community.id, newOwnerHandle);
                _refreshCommunityDetails();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            child: const Text('Transfer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showMuteOptions() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Mute notifications for...'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              widget.repository.muteCommunity(_community.id, now + 3600);
              setState(() => _community = _community.copyWith(isMuted: true));
            },
            child: const Text('1 Hour'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              widget.repository.muteCommunity(_community.id, now + 28800);
              setState(() => _community = _community.copyWith(isMuted: true));
            },
            child: const Text('8 Hours'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              widget.repository.muteCommunity(_community.id, now + 604800);
              setState(() => _community = _community.copyWith(isMuted: true));
            },
            child: const Text('1 Week'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              widget.repository.muteCommunity(_community.id, -1);
              setState(() => _community = _community.copyWith(isMuted: true));
            },
            child: const Text('Always'),
          ),
        ],
      ),
    );
  }

  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave ${_community.name}?'),
        content: Text(
          _community.isOwner && _community.memberCount > 1
              ? 'You are the owner of this community. You must transfer ownership to another member before leaving.'
              : 'Are you sure you want to leave this ${_community.isChannel ? 'channel' : 'group'}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          if (_community.isOwner && _community.memberCount > 1)
            const SizedBox.shrink()
          else
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(ctx); // dialog
                Navigator.pop(context); // screen
                try {
                  await widget.repository.leaveCommunity(_community.id);
                } catch (e) {
                  // Handled
                }
              },
              child: const Text('Leave'),
            ),
        ],
      ),
    );
  }

  void _regenerateInviteLink() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Invite Link?'),
        content: const Text(
          'This will permanently deactivate the previous invite link. Anyone using the old link will no longer be able to join.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate New Link', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final newLink = await widget.repository.regenerateInviteLink(_community.id);
        if (mounted) {
          setState(() {
            _community = _community.copyWith(inviteLink: newLink);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('New invite link generated!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to regenerate invite link: $e')),
          );
        }
      }
    }
  }

  void _confirmDeleteCommunity() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${_community.name}"?'),
        content: const Text(
          'Are you sure you want to permanently delete this community? All messages, members, and files will be removed. This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              try {
                await widget.repository.deleteCommunity(_community.id);
                if (mounted) {
                  Navigator.pop(context, true); // Close Info screen
                  Navigator.pop(context, true); // Close Chat screen
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete community: $e')),
                  );
                }
              }
            },
            child: const Text('Delete Permanently', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
