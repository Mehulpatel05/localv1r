import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme.dart';

/// Modal bottom sheet allowing users to toggle specific notification categories.
/// Strictly adheres to Nearhood B&W design system.
class NotificationSettingsSheet extends StatefulWidget {
  const NotificationSettingsSheet({super.key});

  @override
  State<NotificationSettingsSheet> createState() => _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState extends State<NotificationSettingsSheet> {
  bool _chatEnabled = true;
  bool _friendsEnabled = true;
  bool _communitiesEnabled = true;
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
      _communitiesEnabled = prefs.getBool('notif_communities_enabled') ?? true;
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
    final c = context.nearhoodColors;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(22, 10, 22, 22 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grab handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title & Subtitle
          Text(
            'Notification Alerts',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.02 * 20,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage what alerts you want to receive on this device.',
            style: TextStyle(fontSize: 13.5, color: c.muted),
          ),

          const SizedBox(height: 16),

          // Toggles Card
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: c.ink, strokeWidth: 2),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: c.line, width: 1),
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
                  Divider(height: 1, thickness: 1, color: c.line),
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
                  Divider(height: 1, thickness: 1, color: c.line),
                  _ToggleRow(
                    icon: Icons.groups_outlined,
                    title: 'Community Messages',
                    subtitle: 'Alerts from joined communities',
                    value: _communitiesEnabled,
                    onChanged: (val) {
                      setState(() => _communitiesEnabled = val);
                      _updatePref('notif_communities_enabled', val);
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: c.line),
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

          // Done Button
          SizedBox(
            height: 54,
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.btn,
                foregroundColor: c.btnink,
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
    final c = context.nearhoodColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.field,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: c.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: c.btn,
            activeTrackColor: c.ink.withValues(alpha: 0.35),
            inactiveThumbColor: c.muted,
            inactiveTrackColor: c.field,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Shows [NotificationSettingsSheet] with bottom sheet animation.
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
