import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../services/app_permission_service.dart';

/// Full-page permission onboarding screen designed to fit entirely on screen
/// without scrolling, featuring custom app branding and Nearhood theme styling.
class PermissionRequestScreen extends StatefulWidget {
  final void Function(BuildContext context) onComplete;

  const PermissionRequestScreen({super.key, required this.onComplete});

  @override
  State<PermissionRequestScreen> createState() => _PermissionRequestScreenState();
}

class _PermissionRequestScreenState extends State<PermissionRequestScreen> {
  bool _isRequesting = false;
  bool _hasRequested = false;

  final List<_PermItem> _permissions = [
    _PermItem(
      permission: Permission.notification,
      icon: Icons.notifications_none_rounded,
      title: 'Notifications',
      reason: 'Stay updated with new messages, local alerts and replies.',
    ),
    _PermItem(
      permission: Permission.locationWhenInUse,
      icon: Icons.location_on_outlined,
      title: 'Location',
      reason: 'Automatically show posts from your local area in your city.',
    ),
    _PermItem(
      permission: Permission.photos,
      icon: Icons.photo_outlined,
      title: 'Photo Library',
      reason: 'Attach photos from your gallery when creating a post.',
    ),
    _PermItem(
      permission: Permission.camera,
      icon: Icons.camera_alt_outlined,
      title: 'Camera',
      reason: 'Take a photo directly from camera and post it.',
    ),
  ];

  Future<void> _requestAll() async {
    setState(() {
      _isRequesting = true;
      _hasRequested = false;
    });

    for (final item in _permissions) {
      final status = await item.permission.request();
      if (mounted) {
        setState(() {
          item.granted = status.isGranted;
          item.denied = !status.isGranted;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isRequesting = false;
        _hasRequested = true;
      });
    }
  }

  bool get _hasPermanentlyDenied => _permissions.any((p) => p.permanentlyDenied);

  @override
  Widget build(BuildContext context) {
    final colors = context.nearhoodColors;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              const Spacer(flex: 1),

              // ── Header & App Logo ──────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.field,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.line, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        'assets/images/nearhood_app_icon_1024.png',
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Image.asset(
                            'assets/images/nearhood_logo.png',
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.location_city_rounded,
                                color: colors.ink,
                                size: 30,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Nearhood Needs Access',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: colors.ink,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Allow the following permissions so the app\nworks fully for you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 1),

              // ── Permission Cards (Compact & Non-scrollable) ──────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: _permissions
                    .map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildPermissionCard(item, colors),
                        ))
                    .toList(),
              ),

              const Spacer(flex: 1),

              // ── Action Buttons ─────────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hasRequested && _hasPermanentlyDenied) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.muted,
                        side: BorderSide(color: colors.line),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text(
                        'Open Settings to Allow',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      onPressed: AppPermissionService.openSettings,
                    ),
                    const SizedBox(height: 10),
                  ],

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.field2,
                        foregroundColor: Colors.white,
                        side: const BorderSide(
                          color: Color(0xFF2DD4BF),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isRequesting
                          ? null
                          : _hasRequested
                              ? () => widget.onComplete(context)
                              : _requestAll,
                      child: _isRequesting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _hasRequested ? 'Get Started' : 'Allow Permissions',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),

                  if (!_hasRequested) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => widget.onComplete(context),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Skip for now',
                        style: TextStyle(
                          color: colors.muted.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard(_PermItem item, NearhoodColors colors) {
    final cardColor = item.granted
        ? const Color(0xFF064E3B).withValues(alpha: 0.35)
        : colors.field;
    final borderColor = item.granted
        ? const Color(0xFF4ADE80)
        : item.denied
            ? const Color(0xFFEF4444)
            : colors.line;

    return AnimatedContainer(
      duration: AppMotion.durationStandard,
      curve: AppMotion.interactiveCurve,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.field2,
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.icon,
              color: colors.ink,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.reason,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (item.granted)
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF4ADE80),
              size: 24,
            )
          else if (item.denied)
            const Icon(
              Icons.cancel_rounded,
              color: Color(0xFFEF4444),
              size: 24,
            )
          else
            Icon(
              Icons.radio_button_unchecked,
              color: colors.muted.withValues(alpha: 0.4),
              size: 24,
            ),
        ],
      ),
    );
  }
}

class _PermItem {
  final Permission permission;
  final IconData icon;
  final String title;
  final String reason;
  bool granted = false;
  bool denied = false;

  bool get permanentlyDenied => denied;

  _PermItem({
    required this.permission,
    required this.icon,
    required this.title,
    required this.reason,
  });
}
