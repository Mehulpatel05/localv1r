import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/auth_repository.dart';
import '../../core/models/user_profile.dart';
import '../../features/auth/login_flow_page.dart';
import '../../screens/profile/blocked_users_screen.dart';
import '../../screens/profile/widgets/support_request_sheet.dart';
import 'widgets/account_info_sheet.dart';
import 'widgets/confirm_sheet.dart';
import 'widgets/notification_settings_sheet.dart';
import 'widgets/settings_group.dart';
import 'widgets/settings_tile.dart';
import 'widgets/shorebird_update_tile.dart';
import '../../screens/safety/legal_and_rules_screen.dart';
import '../../screens/admin/founding_admin_screen.dart';
import '../../services/post_repository.dart';
import '../../services/token_decision_engine.dart';
import '../../theme/app_colors.dart';
import '../account_deletion/account_deletion_coordinator.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.authRepository,
    required this.profile,
    this.city = 'Vadodara',
  });

  final AuthRepository authRepository;
  final UserProfile profile;
  final String city;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {


  void _navigateToLogin(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginFlowPage(
          authRepository: widget.authRepository,
          postRepository: PostRepository.instance,
        ),
      ),
      (route) => false,
    );
  }

  void _openAccountInfo(BuildContext context) {
    showAccountInfoSheet(context, profile: widget.profile);
  }

  void _openLogoutSheet(BuildContext context) {
    showConfirmSheet(
      context,
      title: 'Log out?',
      body: 'You can log back in anytime with your mobile number.',
      confirmLabel: 'Log Out',
      cancelLabel: 'Cancel',
      isDanger: false,
      onConfirm: () async {
        await widget.authRepository.logout();
        if (context.mounted) {
          Navigator.of(context).pop();
          _navigateToLogin(context);
        }
      },
    );
  }

  void _openDeleteSheet(BuildContext context) {
    AccountDeletionCoordinator.startDeletionFlow(
      context,
      authRepository: widget.authRepository,
    );
  }

  void _shareApp(BuildContext context) {
    SharePlus.instance.share(
      ShareParams(
        text:
            'Join me on Nearhood, your neighborhood hub for local news, events, and marketplace! Download now at https://nearhood.in',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18).copyWith(bottom: 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Back to profile',
                    child: _CircleButton(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Settings',
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

            SettingsGroup(
              label: 'Account',
              isFirst: true,
              tiles: [
                SettingsTile(
                  icon: Icons.person_outline,
                  title: 'Account Info',
                  description: 'View your handle, phone & join date',
                  onTap: () => _openAccountInfo(context),
                  semanticsLabel:
                      'Account Info, View your handle, phone and join date, button',
                ),
                SettingsTile(
                  icon: Icons.block_outlined,
                  title: 'Blocked Users',
                  description: "Manage users you've blocked",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const BlockedUsersScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),

            SettingsGroup(
              label: 'Preferences',
              tiles: [
                SettingsTile(
                  icon: Icons.notifications_none_outlined,
                  title: 'Notification Alerts',
                  description: 'Manage push and chat alerts',
                  onTap: () => showNotificationSettingsSheet(context),
                  semanticsLabel:
                      'Notification Alerts, Manage push and chat alerts, button',
                ),
              ],
            ),

            SettingsGroup(
              label: 'Help & Support',
              tiles: [
                SettingsTile(
                  icon: Icons.support_agent_rounded,
                  title: 'Help & Support Desk',
                  description: 'Contact Vadodara support or report an issue',
                  onTap: () {
                    SupportRequestSheet.show(
                      context,
                      userHandle: widget.profile.handle,
                      initialPhone: widget.profile.phone,
                    );
                  },
                  semanticsLabel: 'Help and Support Desk, button',
                ),
                SettingsTile(
                  icon: Icons.share_outlined,
                  title: 'Share Nearhood',
                  description: 'Invite your neighbors to join',
                  onTap: () => _shareApp(context),
                ),
              ],
            ),

            SettingsGroup(
              label: 'Legal & Safety',
              tiles: [
                SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Community Guidelines',
                  description: 'Vadodara neighborhood house rules & standards',
                  onTap: () => LegalAndRulesScreen.open(context, initialTab: 0),
                  semanticsLabel: 'Community Guidelines, button',
                ),
                SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of Service',
                  description: 'Intermediary safe harbor & legal agreement',
                  onTap: () => LegalAndRulesScreen.open(context, initialTab: 1),
                  semanticsLabel: 'Terms of Service, button',
                ),
                SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  description: 'DPDP Act 2023 compliance & GPS privacy',
                  onTap: () => LegalAndRulesScreen.open(context, initialTab: 2),
                  semanticsLabel: 'Privacy Policy, button',
                ),
              ],
            ),

            if (TokenDecisionEngine.instance.canSeeAdminPanel()) ...[
              SettingsGroup(
                label: 'Administration',
                tiles: [
                  SettingsTile(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Founding Badge Approvals',
                    description: 'Review & manage area founding neighbour requests',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const FoundingAdminScreen(),
                        ),
                      );
                    },
                    semanticsLabel: 'Founding Badge Approvals, button',
                  ),
                ],
              ),
            ],

            const SizedBox(height: 26),

            const ShorebirdUpdateTile(),

            const SizedBox(height: 14),

            _ActionButton(
              label: 'Log Out',
              icon: Icons.logout,
              onTap: () => _openLogoutSheet(context),
              semanticsLabel: 'Log Out',
            ),

            const SizedBox(height: 10),

            _ActionButton(
              label: 'Delete My Account',
              icon: Icons.delete_outline,
              onTap: () => _openDeleteSheet(context),
              isDanger: true,
              semanticsLabel: 'Delete My Account',
            ),

            Padding(
              padding: const EdgeInsets.only(top: 26),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      'Nearhood · ${widget.city}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version 1.0.1 (Vadodara Live)',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatefulWidget {
  const _CircleButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Focus(
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) {
              setState(() => _pressed = false);
              widget.onTap();
            },
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedContainer(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 80),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _pressed ? AppColors.divider : AppColors.chipBg,
                shape: BoxShape.circle,
                border: hasFocus
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
              ),
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDanger = false,
    this.semanticsLabel,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDanger;
  final String? semanticsLabel;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    final Color bg = widget.isDanger
        ? AppColors.errorSoft
        : (_pressed ? AppColors.divider : AppColors.surface);

    final Color fg = widget.isDanger ? const Color(0xFFB3262A) : AppColors.textPrimary;

    final Border border = widget.isDanger
        ? Border.all(color: const Color(0xFFFCA5A5), width: 1.5)
        : Border.all(color: AppColors.divider);

    final scale = (_pressed && !disableAnimations) ? 0.985 : 1.0;

    return Semantics(
      button: true,
      label: widget.semanticsLabel ?? widget.label,
      child: Focus(
        child: Builder(
          builder: (ctx) {
            final hasFocus = Focus.of(ctx).hasFocus;
            return AnimatedScale(
              scale: scale,
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 100),
              child: GestureDetector(
                onTapDown: (_) => setState(() => _pressed = true),
                onTapUp: (_) {
                  setState(() => _pressed = false);
                  widget.onTap();
                },
                onTapCancel: () => setState(() => _pressed = false),
                child: AnimatedContainer(
                  duration: disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 100),
                  height: 54,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                    border: hasFocus
                        ? Border.all(color: AppColors.primary, width: 2)
                        : border,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.icon, size: 20, color: fg),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
