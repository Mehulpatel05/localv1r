import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth_repository.dart';
import '../../core/models/user_profile.dart';
import '../../core/theme.dart';
import '../../features/auth/login_flow_page.dart';
import '../../screens/profile/blocked_users_screen.dart';
import 'feedback_support_page.dart';
import 'widgets/account_info_sheet.dart';
import 'widgets/confirm_sheet.dart';
import 'widgets/notification_settings_sheet.dart';
import 'widgets/settings_group.dart';
import 'widgets/settings_tile.dart';

/// Full-page Settings screen matching the Nearhood Black & White design spec.
///
/// Pushed as a [MaterialPageRoute] from the profile screen.
/// No bottom navigation bar (above the main shell).
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.authRepository,
    required this.profile,
    this.city = 'Vadodara',
  });

  final AuthRepository authRepository;
  final UserProfile profile;

  /// City name shown in the footer. Defaults to 'Vadodara'.
  final String city;

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _navigateToLogin(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginFlowPage(
          authRepository: authRepository,
        ),
      ),
      (route) => false,
    );
  }

  // ── Sheet launchers ───────────────────────────────────────────────────────

  void _openAccountInfo(BuildContext context) {
    showAccountInfoSheet(context, profile: profile);
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
        await authRepository.logout();
        if (context.mounted) {
          Navigator.of(context).pop(); // close sheet
          _navigateToLogin(context);
        }
      },
    );
  }

  void _openDeleteSheet(BuildContext context) {
    showConfirmSheet(
      context,
      title: 'Delete your account?',
      body:
          'Your profile, posts and messages will be removed permanently. This cannot be undone.',
      confirmLabel: 'Delete My Account',
      cancelLabel: 'Keep my account',
      isDanger: true,
      onConfirm: () async {
        await authRepository.deleteAccount();
        if (context.mounted) {
          Navigator.of(context).pop(); // close sheet
          _navigateToLogin(context);
        }
      },
    );
  }

  void _shareApp(BuildContext context) {
    // TODO(dev): replace the store link with the real Play Store / App Store URL.
    SharePlus.instance.share(
      ShareParams(
        text:
            'Join me on Nearhood, the app for every local need. [Store link coming soon]',
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.nearhoodColors;

    return Scaffold(
      backgroundColor: c.bg,
      // No default AppBar — we build a custom top bar inside the body.
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18).copyWith(bottom: 40),
          children: [
            // ── Custom top bar ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
              child: Row(
                children: [
                  // Back button
                  Semantics(
                    label: 'Back',
                    button: true,
                    child: _CircleButton(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.arrow_back,
                        size: 19,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Title
                  Text(
                    'Settings',
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

            // ── Account group ───────────────────────────────────────────────
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
                  icon: Icons.headset_mic_outlined,
                  title: 'Feedback & Support',
                  description: 'Rate, report bugs or suggest features',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => FeedbackSupportPage(
                          profile: profile,
                        ),
                      ),
                    );
                  },
                ),
                SettingsTile(
                  icon: Icons.block,
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

            // ── Preferences group ───────────────────────────────────────────
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

            // ── More group ──────────────────────────────────────────────────
            SettingsGroup(
              label: 'More',
              tiles: [
                SettingsTile(
                  icon: Icons.share_outlined,
                  title: 'Share Nearhood',
                  description: 'Invite your neighbors to join',
                  onTap: () => _shareApp(context),
                ),
              ],
            ),

            // ── Action buttons ──────────────────────────────────────────────
            const SizedBox(height: 26),

            // Log Out
            _ActionButton(
              label: 'Log Out',
              icon: Icons.logout,
              onTap: () => _openLogoutSheet(context),
              semanticsLabel: 'Log Out',
            ),

            const SizedBox(height: 10),

            // Delete My Account
            _ActionButton(
              label: 'Delete My Account',
              icon: Icons.delete_outline,
              onTap: () => _openDeleteSheet(context),
              isDanger: true,
              semanticsLabel: 'Delete My Account',
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 26),
              child: Center(
                child: Text(
                  'Nearhood · $city',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Private reusable widgets ─────────────────────────────────────────────────

/// 40×40 circle button (back button in the top bar).
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
    final c = context.nearhoodColors;
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
                color: _pressed ? c.field2 : c.field,
                shape: BoxShape.circle,
                border: hasFocus
                    ? Border.all(color: c.ink, width: 2)
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

/// Full-width action button used for Log Out and Delete My Account.
///
/// Spec: height 54, radius 16, icon + text (gap 8), scale press 0.985.
/// Danger variant: bg = danger@9%, text+icon = danger, border 1.5px danger@35%.
/// Normal variant: bg = field, text+icon = ink.
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
    final c = context.nearhoodColors;
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    final Color bg = widget.isDanger
        ? c.danger.withValues(alpha: 0.09)
        : (_pressed ? c.field2 : c.field);

    final Color fg = widget.isDanger ? c.danger : c.ink;

    final Border? border = widget.isDanger
        ? Border.all(color: c.danger.withValues(alpha: 0.35), width: 1.5)
        : null;

    final scale = (_pressed && !disableAnimations) ? 0.985 : 1.0;

    return Semantics(
      button: true,
      label: widget.semanticsLabel ?? widget.label,
      // Delete button should not be first in focus order — handled by placement
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
                      : const Duration(milliseconds: 80),
                  height: 54,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                    border: hasFocus
                        ? Border.all(color: c.ink, width: 2)
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
                          fontSize: 16,
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
