import 'package:flutter/material.dart';
import '../../../core/models/user_profile.dart';
import '../../../screens/friends/friend_requests_screen.dart';
import '../../../services/friend_repository.dart';
import '../../../theme/app_colors.dart';

class AccountInfoSheet extends StatelessWidget {
  const AccountInfoSheet({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(22, 10, 22, 22 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'Account Info',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.02 * 20,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.divider, width: 1),
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (profile.hasCustomName) ...[
                  _InfoRow(
                    label: 'Name',
                    value: profile.displayName!,
                  ),
                  const Divider(height: 1, thickness: 1, color: AppColors.divider),
                ],
                _InfoRow(
                  label: 'Username',
                  value: profile.displayHandle,
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                _InfoRow(
                  label: 'Phone',
                  value: _formatPhone(profile.phone),
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                _InfoRow(
                  label: 'Joined',
                  value: profile.joinedFormatted,
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    final repo = FriendRepository()
                      ..currentUserHandle = profile.handle;
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => FriendRequestsScreen(
                          repository: repo,
                          currentUserHandle: profile.handle,
                        ),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Friend Requests',
                          style: TextStyle(fontSize: 14.5, color: AppColors.textMuted),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View requests',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textMuted),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _DoneButton(onTap: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  String _formatPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) return 'Not added';
    final clean = phone.trim();
    if (clean.startsWith('+91') && clean.length == 13) {
      return '+91 ${clean.substring(3, 8)} ${clean.substring(8)}';
    } else if (clean.length == 10 && RegExp(r'^\d+$').hasMatch(clean)) {
      return '+91 ${clean.substring(0, 5)} ${clean.substring(5)}';
    }
    return clean;
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14.5, color: AppColors.textMuted),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneButton extends StatefulWidget {
  const _DoneButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_DoneButton> createState() => _DoneButtonState();
}

class _DoneButtonState extends State<_DoneButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Semantics(
      button: true,
      label: 'Done',
      child: AnimatedScale(
        scale: (_pressed && !disableAnimations) ? 0.985 : 1.0,
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
          child: Container(
            height: 54,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Done',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showAccountInfoSheet(BuildContext context, {required UserProfile profile}) {
  final disableAnimations = MediaQuery.of(context).disableAnimations;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: disableAnimations
        ? AnimationStyle.noAnimation
        : AnimationStyle(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
    builder: (_) => AccountInfoSheet(profile: profile),
  );
}
