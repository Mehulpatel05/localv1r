import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme.dart';
import '../../../services/auth_service.dart';

/// Modal bottom sheet allowing users to configure who can call them (Voice & Video).
/// Options: 'everyone' (default), 'friends', 'nobody'.
class CallPrivacySettingsSheet extends StatefulWidget {
  const CallPrivacySettingsSheet({
    super.key,
    required this.userHandle,
  });

  final String userHandle;

  @override
  State<CallPrivacySettingsSheet> createState() => _CallPrivacySettingsSheetState();
}

class _CallPrivacySettingsSheetState extends State<CallPrivacySettingsSheet> {
  String _selectedOption = 'everyone';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final clean = widget.userHandle.replaceAll('@', '').trim();
    final prefs = await SharedPreferences.getInstance();
    String? localVal = prefs.getString('call_privacy');

    if (localVal == null && clean.isNotEmpty) {
      try {
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/preferences/$clean'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          localVal = data['preferences']?['callPrivacy'] as String?;
          if (localVal != null) {
            await prefs.setString('call_privacy', localVal);
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _selectedOption = localVal ?? 'everyone';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectOption(String option) async {
    if (_selectedOption == option) return;

    HapticFeedback.selectionClick();
    setState(() => _selectedOption = option);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('call_privacy', option);

    final clean = widget.userHandle.replaceAll('@', '').trim();
    if (clean.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('${AuthService.baseUrl}/preferences'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'handle': clean,
            'callPrivacy': option,
          }),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Error updating call privacy in D1: $e');
      }
    }
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
            'Call Privacy',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.02 * 20,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose who is allowed to start voice and video calls with you.',
            style: TextStyle(fontSize: 13.5, color: c.muted),
          ),

          const SizedBox(height: 18),

          // Options Card
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
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
                  _OptionRow(
                    icon: Icons.public,
                    title: 'Everyone',
                    subtitle: 'Anyone you chat with can call you',
                    isSelected: _selectedOption == 'everyone',
                    onTap: () => _selectOption('everyone'),
                  ),
                  Divider(height: 1, thickness: 1, color: c.line),
                  _OptionRow(
                    icon: Icons.people_outline,
                    title: 'Friends Only',
                    subtitle: 'Only accepted friends can call you',
                    isSelected: _selectedOption == 'friends',
                    onTap: () => _selectOption('friends'),
                  ),
                  Divider(height: 1, thickness: 1, color: c.line),
                  _OptionRow(
                    icon: Icons.block_outlined,
                    title: 'Nobody',
                    subtitle: 'Disable all incoming voice & video calls',
                    isSelected: _selectedOption == 'nobody',
                    onTap: () => _selectOption('nobody'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nearhoodColors;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected ? c.btn : c.field,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 19,
                color: isSelected ? c.btnink : c.ink,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? c.ink : c.line,
                  width: 2,
                ),
                color: isSelected ? c.ink : Colors.transparent,
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: c.bg,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [CallPrivacySettingsSheet] with bottom sheet animation.
void showCallPrivacySettingsSheet(BuildContext context, {required String userHandle}) {
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
    builder: (_) => CallPrivacySettingsSheet(userHandle: userHandle),
  );
}
