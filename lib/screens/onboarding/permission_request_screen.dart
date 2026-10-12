import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/app_colors.dart';
import '../../core/motion.dart';
import '../../services/app_permission_service.dart';
import '../../core/constants/app_static_assets.dart';
import '../../core/widgets/safe_image.dart';

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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              const Spacer(flex: 1),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.divider, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SafeImage(
                        imageUrl: AppStaticAssets.appIcon1024,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Nearhood Needs Access',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Allow the following permissions so the app\nworks fully for you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 1),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: _permissions
                    .map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildPermissionCard(item),
                        ))
                    .toList(),
              ),

              const Spacer(flex: 1),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hasRequested && _hasPermanentlyDenied) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        side: const BorderSide(color: AppColors.divider),
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
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
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
                      child: const Text(
                        'Skip for now',
                        style: TextStyle(
                          color: AppColors.textMuted,
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

  Widget _buildPermissionCard(_PermItem item) {
    final cardColor = item.granted
        ? AppColors.primarySoft
        : (item.denied ? AppColors.errorSoft : AppColors.surface);
    final borderColor = item.granted
        ? AppColors.primary
        : (item.denied ? AppColors.error : AppColors.divider);

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
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.chipBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.icon,
              color: AppColors.textPrimary,
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
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.reason,
                  style: const TextStyle(
                    color: AppColors.textMuted,
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
              color: AppColors.primary,
              size: 24,
            )
          else if (item.denied)
            const Icon(
              Icons.cancel_rounded,
              color: AppColors.error,
              size: 24,
            )
          else
            const Icon(
              Icons.radio_button_unchecked,
              color: AppColors.textMuted,
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
