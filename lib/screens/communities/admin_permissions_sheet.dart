import 'package:flutter/material.dart';
import '../../models/community_model.dart';
import '../../services/community_repository.dart';

class AdminPermissionsSheet extends StatefulWidget {
  final CommunityModel community;
  final CommunityRepository repository;
  final String? targetAdminHandle; // If non-null, editing specific admin's permissions
  final Map<String, dynamic>? initialPermissions;

  const AdminPermissionsSheet({
    super.key,
    required this.community,
    required this.repository,
    this.targetAdminHandle,
    this.initialPermissions,
  });

  @override
  State<AdminPermissionsSheet> createState() => _AdminPermissionsSheetState();
}

class _AdminPermissionsSheetState extends State<AdminPermissionsSheet> {
  // Community general permissions
  late String _whoCanSend;
  late bool _allowPhotos;
  late bool _allowVideos;
  late bool _allowFiles;
  late bool _approveNewMembers;

  // Granular Admin permissions
  late bool _canAddMembers;
  late bool _canRemoveMembers;
  late bool _canEditInfo;
  late bool _canPinMessages;
  late bool _canDeleteMessages;
  late bool _canManageAdmins;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.community.settings;
    _whoCanSend = (settings['who_can_send'] as String?) ?? (widget.community.isChannel ? 'admins_only' : 'all');
    final media = settings['media_permissions'] as Map<String, dynamic>? ?? {};
    _allowPhotos = media['photo'] ?? true;
    _allowVideos = media['video'] ?? true;
    _allowFiles = media['file'] ?? true;
    _approveNewMembers = settings['approve_new_members'] == true;

    final perms = widget.initialPermissions ?? widget.community.myPermissions;
    _canAddMembers = perms['can_add_members'] ?? true;
    _canRemoveMembers = perms['can_remove_members'] ?? true;
    _canEditInfo = perms['can_edit_info'] ?? true;
    _canPinMessages = perms['can_pin_messages'] ?? true;
    _canDeleteMessages = perms['can_delete_messages'] ?? true;
    _canManageAdmins = perms['can_manage_admins'] ?? false;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      if (widget.targetAdminHandle != null) {
        // Saving granular permissions for a specific admin
        final perms = {
          'can_add_members': _canAddMembers,
          'can_remove_members': _canRemoveMembers,
          'can_edit_info': _canEditInfo,
          'can_pin_messages': _canPinMessages,
          'can_delete_messages': _canDeleteMessages,
          'can_manage_admins': _canManageAdmins,
        };
        await widget.repository.updateMemberRole(
          widget.community.id,
          widget.targetAdminHandle!,
          'admin',
          perms,
        );
      } else {
        // Saving community-wide permissions & settings
        final newSettings = {
          'who_can_send': _whoCanSend,
          'media_permissions': {
            'text': true,
            'photo': _allowPhotos,
            'video': _allowVideos,
            'file': _allowFiles,
            'call': true,
          },
          'approve_new_members': _approveNewMembers,
        };
        await widget.repository.updateCommunitySettings(
          communityId: widget.community.id,
          settings: newSettings,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissions updated successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSpecificAdmin = widget.targetAdminHandle != null;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 16,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isSpecificAdmin
                        ? 'Admin Permissions: @${widget.targetAdminHandle}'
                        : 'Community Permissions',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),

              if (!isSpecificAdmin && !widget.community.isChannel) ...[
                // Who can send messages
                const Text(
                  'Who can send messages',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  title: const Text('All members'),
                  value: 'all',
                  groupValue: _whoCanSend,
                  onChanged: (val) => setState(() => _whoCanSend = val!),
                ),
                RadioListTile<String>(
                  title: const Text('Admins only'),
                  value: 'admins_only',
                  groupValue: _whoCanSend,
                  onChanged: (val) => setState(() => _whoCanSend = val!),
                ),
                const SizedBox(height: 12),

                // Media & Files Gating
                const Text(
                  'Media & Files Allowed for Members',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                ),
                SwitchListTile(
                  title: const Text('Photos & Images'),
                  value: _allowPhotos,
                  onChanged: (val) => setState(() => _allowPhotos = val),
                ),
                SwitchListTile(
                  title: const Text('Videos'),
                  value: _allowVideos,
                  onChanged: (val) => setState(() => _allowVideos = val),
                ),
                SwitchListTile(
                  title: const Text('Files & Documents'),
                  value: _allowFiles,
                  onChanged: (val) => setState(() => _allowFiles = val),
                ),
                const SizedBox(height: 12),

                // Approve New Members Toggle
                const Text(
                  'Membership Approval',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                ),
                SwitchListTile(
                  title: const Text('Approve new members'),
                  subtitle: const Text('Require admin review before members can join'),
                  value: _approveNewMembers,
                  onChanged: (val) => setState(() => _approveNewMembers = val),
                ),
              ],

              if (isSpecificAdmin) ...[
                SwitchListTile(
                  title: const Text('Add members / approve requests'),
                  value: _canAddMembers,
                  onChanged: (val) => setState(() => _canAddMembers = val),
                ),
                SwitchListTile(
                  title: const Text('Remove members'),
                  value: _canRemoveMembers,
                  onChanged: (val) => setState(() => _canRemoveMembers = val),
                ),
                SwitchListTile(
                  title: const Text('Edit community info'),
                  value: _canEditInfo,
                  onChanged: (val) => setState(() => _canEditInfo = val),
                ),
                SwitchListTile(
                  title: const Text('Pin & unpin messages'),
                  value: _canPinMessages,
                  onChanged: (val) => setState(() => _canPinMessages = val),
                ),
                SwitchListTile(
                  title: const Text('Delete others\' messages'),
                  value: _canDeleteMessages,
                  onChanged: (val) => setState(() => _canDeleteMessages = val),
                ),
                if (widget.community.isOwner)
                  SwitchListTile(
                    title: const Text('Manage other admins'),
                    value: _canManageAdmins,
                    onChanged: (val) => setState(() => _canManageAdmins = val),
                  ),
              ],

              const SizedBox(height: 20),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
                      : const Text('Save Permissions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
