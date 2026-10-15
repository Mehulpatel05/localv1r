import 'package:flutter/material.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../../../theme/app_colors.dart';

class ShorebirdUpdateTile extends StatefulWidget {
  const ShorebirdUpdateTile({super.key});

  @override
  State<ShorebirdUpdateTile> createState() => _ShorebirdUpdateTileState();
}

class _ShorebirdUpdateTileState extends State<ShorebirdUpdateTile> {
  final _updater = ShorebirdUpdater();
  bool _isChecking = false;
  int? _currentPatchNumber;
  int? _nextPatchNumber;

  @override
  void initState() {
    super.initState();
    _loadPatchInfo();
  }

  Future<void> _loadPatchInfo() async {
    if (!_updater.isAvailable) return;

    try {
      final current = await _updater.readCurrentPatch();
      final next = await _updater.readNextPatch();
      if (mounted) {
        setState(() {
          _currentPatchNumber = current?.number;
          _nextPatchNumber = next?.number;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleCheckForUpdates() async {
    if (_isChecking) return;

    setState(() => _isChecking = true);

    try {
      if (!_updater.isAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Shorebird code push is only active on release builds.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final status = await _updater.checkForUpdate();

      if (status == UpdateStatus.outdated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Downloading new update in background...'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
        }

        await _updater.update();
        await _loadPatchInfo();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.primary,
              content: Text('Update downloaded! Restart app to apply changes.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 5),
            ),
          );
        }
      } else if (status == UpdateStatus.restartRequired) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFF59E0B),
              content: Text('Update already downloaded! Restart app to apply.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('App is already up to date!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update check failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String statusText;
    Color statusColor;

    if (!_updater.isAvailable) {
      statusText = 'Development build';
      statusColor = AppColors.textMuted;
    } else if (_nextPatchNumber != null) {
      statusText = 'Update ready (Restart to apply)';
      statusColor = const Color(0xFFF59E0B);
    } else if (_currentPatchNumber != null) {
      statusText = 'App is up to date (Version 1.0.1)';
      statusColor = AppColors.primary;
    } else {
      statusText = 'App is up to date (Version 1.0.1)';
      statusColor = AppColors.primary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.divider,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bolt_rounded,
              color: statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'App Updates (Over The Air)',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _isChecking
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                )
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: statusColor.withValues(alpha: 0.5)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: _handleCheckForUpdates,
                  child: Text(
                    'Check',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
