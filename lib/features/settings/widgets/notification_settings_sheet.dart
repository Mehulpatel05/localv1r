import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../theme/app_colors.dart';

class NotificationSettingsSheet extends StatefulWidget {
  const NotificationSettingsSheet({super.key});

  @override
  State<NotificationSettingsSheet> createState() => _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState extends State<NotificationSettingsSheet> {
  bool _chatEnabled = true;
  bool _friendsEnabled = true;
  bool _postsEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _chatEnabled = prefs.getBool('notif_chat_enabled') ?? true;
      _friendsEnabled = prefs.getBool('notif_friends_enabled') ?? true;
      _postsEnabled = prefs.getBool('notif_posts_enabled') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _updatePref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

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
            'Notification Alerts',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.02 * 20,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Manage what alerts you want to receive on this device.',
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
              ),
            )
          else
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
                  _ToggleRow(
                    icon: Icons.chat_bubble_outline,
                    title: 'Direct Messages',
                    subtitle: 'Alerts for private 1-on-1 chats',
                    value: _chatEnabled,
                    onChanged: (val) {
                      setState(() => _chatEnabled = val);
                      _updatePref('notif_chat_enabled', val);
                    },
                  ),
                  const Divider(height: 1, thickness: 1, color: AppColors.divider),
                  _ToggleRow(
                    icon: Icons.people_outline,
                    title: 'Friend Requests',
                    subtitle: 'Alerts when someone connects with you',
                    value: _friendsEnabled,
                    onChanged: (val) {
                      setState(() => _friendsEnabled = val);
                      _updatePref('notif_friends_enabled', val);
                    },
                  ),
                  const Divider(height: 1, thickness: 1, color: AppColors.divider),
                  _ToggleRow(
                    icon: Icons.article_outlined,
                    title: 'Comments & Activity',
                    subtitle: 'Alerts when someone comments on your post',
                    value: _postsEnabled,
                    onChanged: (val) {
                      setState(() => _postsEnabled = val);
                      _updatePref('notif_posts_enabled', val);
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Save & Done',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppColors.chipBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primarySoft,
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.chipBg,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

void showNotificationSettingsSheet(BuildContext context) {
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
    builder: (_) => const NotificationSettingsSheet(),
  );
}
