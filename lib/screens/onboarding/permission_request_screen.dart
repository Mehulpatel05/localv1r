import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/app_permission_service.dart';

/// Full-page permission onboarding screen shown once on first launch.
class PermissionRequestScreen extends StatefulWidget {
  final void Function(BuildContext context) onComplete;

  const PermissionRequestScreen({super.key, required this.onComplete});

  @override
  State<PermissionRequestScreen> createState() => _PermissionRequestScreenState();
}

class _PermissionRequestScreenState extends State<PermissionRequestScreen> {
  bool _isRequesting = false;
  bool _hasRequested = false; // tracks if we ran through the flow at least once

  final List<_PermItem> _permissions = [
    _PermItem(
      permission: Permission.notification,
      icon: Icons.notifications_rounded,
      color: Color(0xFF3B82F6),
      title: 'Notifications',
      reason: 'Stay updated with new messages, local alerts and replies.',
    ),
    _PermItem(
      permission: Permission.locationWhenInUse,
      icon: Icons.location_on_rounded,
      color: Color(0xFF10B981),
      title: 'Location',
      reason: 'Automatically show posts from your local area in Vadodara.',
    ),
    _PermItem(
      permission: Permission.photos,
      icon: Icons.photo_library_rounded,
      color: Color(0xFFF59E0B),
      title: 'Photo Library',
      reason: 'Attach photos from your gallery when creating a post.',
    ),
    _PermItem(
      permission: Permission.camera,
      icon: Icons.camera_alt_rounded,
      color: Color(0xFF8B5CF6),
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
          // Mark as denied if NOT granted (denied, permanently denied, or restricted)
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
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3B82F6).withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.location_city, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Vadodara Local\nNeeds Access',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Allow the following permissions so the app\nworks fully for you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Permission Cards ───────────────────────────────────
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _permissions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _buildPermissionCard(_permissions[index]),
              ),
            ),

            const SizedBox(height: 16),

            // ── Buttons ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  // "Open Settings" — show only if something is permanently denied
                  if (_hasRequested && _hasPermanentlyDenied) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black54,
                        side: const BorderSide(color: Color(0xFF374151)),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.settings_rounded, size: 18),
                      label: const Text('Open Settings to Allow'),
                      onPressed: AppPermissionService.openSettings,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Main action button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                      onPressed: _isRequesting
                          ? null
                          : _hasRequested
                              ? () => widget.onComplete(context)   // ← Pass valid context
                              : _requestAll,
                      child: _isRequesting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : Text(
                              _hasRequested ? 'Get Started →' : 'Allow Permissions',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),

                  // Skip link — always visible before requesting
                  if (!_hasRequested) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => widget.onComplete(context),
                      child: const Text(
                        'Skip for now',
                        style: TextStyle(color: Colors.black38, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard(_PermItem item) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: item.granted
            ? item.color.withOpacity(0.08)
            : const Color(0xFF151D30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.granted
              ? item.color.withOpacity(0.5)
              : item.denied
                  ? Colors.redAccent.withOpacity(0.4)
                  : const Color(0xFF243049),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, color: item.color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: const TextStyle(color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 3),
                Text(item.reason,
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (item.granted)
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 24)
          else if (item.denied)
            const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 24)
          else
            const Icon(Icons.radio_button_unchecked,
                color: Colors.white24, size: 24),
        ],
      ),
    );
  }
}

class _PermItem {
  final Permission permission;
  final IconData icon;
  final Color color;
  final String title;
  final String reason;
  bool granted = false;
  bool denied = false;

  // Separately track permanent denial for settings button
  bool get permanentlyDenied => denied; // refined if needed

  _PermItem({
    required this.permission,
    required this.icon,
    required this.color,
    required this.title,
    required this.reason,
  });
}
