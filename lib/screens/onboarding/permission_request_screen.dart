import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/motion.dart';
import '../../services/app_permission_service.dart';

/// Full-page permission onboarding screen designed to fit entirely on screen
/// without scrolling, featuring custom app branding and compact cards.
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
    return Scaffold(
      backgroundColor: Colors.white,
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
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/images/nearhood_app_icon_1024.png',
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Image.asset(
                            'assets/images/nearhood_logo.png',
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.location_city_rounded,
                                color: Colors.white,
                                size: 28,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Nearhood Needs Access',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Allow the following permissions so the app\nworks fully for you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                      height: 1.35,
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
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildPermissionCard(item),
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
                        foregroundColor: const Color(0xFF4B5563),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text(
                        'Open Settings to Allow',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      onPressed: AppPermissionService.openSettings,
                    ),
                    const SizedBox(height: 10),
                  ],

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  if (!_hasRequested) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => widget.onComplete(context),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Skip for now',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 13,
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

  Widget _buildPermissionCard(_PermItem item) {
    return AnimatedContainer(
      duration: AppMotion.durationStandard,
      curve: AppMotion.interactiveCurve,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: item.granted ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.granted
              ? const Color(0xFF86EFAC)
              : item.denied
                  ? const Color(0xFFFCA5A5)
                  : const Color(0xFFE5E7EB),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFF3F4F6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.icon,
              color: const Color(0xFF1F2937),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.reason,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.granted)
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF10B981),
              size: 22,
            )
          else if (item.denied)
            const Icon(
              Icons.cancel_rounded,
              color: Colors.redAccent,
              size: 22,
            )
          else
            const Icon(
              Icons.radio_button_unchecked,
              color: Color(0xFFD1D5DB),
              size: 22,
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
