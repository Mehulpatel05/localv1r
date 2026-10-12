import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../theme/app_colors.dart';
import 'location_service.dart';
import 'city_picker_screen.dart';

class LocationBanner extends StatefulWidget {
  final VoidCallback? onChooseCity;

  const LocationBanner({super.key, this.onChooseCity});

  @override
  State<LocationBanner> createState() => _LocationBannerState();
}

class _LocationBannerState extends State<LocationBanner>
    with SingleTickerProviderStateMixin {
  bool _dismissed = false;
  LocationState? _lastState;

  void _checkStateChange(LocationState newState) {
    if (newState != _lastState) {
      if (_dismissed) {
        if (newState == LocationState.locationOff ||
            newState == LocationState.permissionDenied ||
            newState == LocationState.permissionDeniedForever) {
          _dismissed = false;
        }
      }
      _lastState = newState;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationService>();
    _checkStateChange(loc.state);

    if (_dismissed) return const SizedBox.shrink();

    final message = loc.bannerMessage;
    if (message == null) return const SizedBox.shrink();

    return _BannerBody(
      state: loc.state,
      message: message,
      onDismiss: () => setState(() => _dismissed = true),
      onAction: () => _handleAction(context, loc),
    );
  }

  void _handleAction(BuildContext context, LocationService loc) {
    switch (loc.state) {
      case LocationState.locationOff:
        Geolocator.openLocationSettings();
        break;
      case LocationState.permissionDenied:
        loc.checkLocationAndAutoDetect();
        break;
      case LocationState.permissionDeniedForever:
        Geolocator.openAppSettings();
        break;
      case LocationState.stale:
      case LocationState.usingIpFallback:
      case LocationState.usingLastKnown:
        loc.checkLocationAndAutoDetect();
        break;
      case LocationState.unknownArea:
        if (widget.onChooseCity != null) {
          widget.onChooseCity!();
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CityPickerScreen()),
          );
        }
        break;
      default:
        break;
    }
  }
}

class _BannerBody extends StatelessWidget {
  final LocationState state;
  final String message;
  final VoidCallback onDismiss;
  final VoidCallback onAction;

  const _BannerBody({
    required this.state,
    required this.message,
    required this.onDismiss,
    required this.onAction,
  });

  Color get _bgColor {
    switch (state) {
      case LocationState.locationOff:
      case LocationState.permissionDenied:
      case LocationState.permissionDeniedForever:
        return AppColors.errorSoft;
      case LocationState.stale:
        return const Color(0xFFFEF3C7);
      case LocationState.usingIpFallback:
      case LocationState.usingLastKnown:
        return AppColors.primarySoft;
      case LocationState.unknownArea:
        return AppColors.chipBg;
      default:
        return AppColors.primarySoft;
    }
  }

  Color get _borderColor {
    switch (state) {
      case LocationState.locationOff:
      case LocationState.permissionDenied:
      case LocationState.permissionDeniedForever:
        return AppColors.error;
      case LocationState.stale:
        return const Color(0xFFD97706);
      case LocationState.usingIpFallback:
      case LocationState.usingLastKnown:
        return AppColors.primary;
      case LocationState.unknownArea:
        return AppColors.divider;
      default:
        return AppColors.primary;
    }
  }

  Color get _textColor {
    switch (state) {
      case LocationState.locationOff:
      case LocationState.permissionDenied:
      case LocationState.permissionDeniedForever:
        return AppColors.errorSoftText;
      case LocationState.stale:
        return const Color(0xFF92400E);
      case LocationState.usingIpFallback:
      case LocationState.usingLastKnown:
        return AppColors.primaryText;
      case LocationState.unknownArea:
        return AppColors.textPrimary;
      default:
        return AppColors.primaryText;
    }
  }

  IconData get _icon {
    switch (state) {
      case LocationState.locationOff:
        return Icons.location_off_rounded;
      case LocationState.permissionDenied:
      case LocationState.permissionDeniedForever:
        return Icons.lock_outline_rounded;
      case LocationState.stale:
        return Icons.history_rounded;
      case LocationState.usingIpFallback:
        return Icons.wifi_tethering_rounded;
      case LocationState.usingLastKnown:
        return Icons.access_time_rounded;
      case LocationState.unknownArea:
        return Icons.explore_off_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  String get _actionLabel {
    switch (state) {
      case LocationState.locationOff:
        return 'Enable';
      case LocationState.permissionDenied:
        return 'Allow';
      case LocationState.permissionDeniedForever:
        return 'Settings';
      case LocationState.stale:
        return 'Refresh';
      case LocationState.usingIpFallback:
      case LocationState.usingLastKnown:
        return 'Retry GPS';
      case LocationState.unknownArea:
        return 'Choose City';
      default:
        return 'Fix';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor, width: 1.0),
        ),
        child: Row(
          children: [
            Icon(_icon, size: 16, color: _borderColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: _textColor,
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor, width: 1),
                ),
                child: Text(
                  _actionLabel,
                  style: TextStyle(
                    color: _borderColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close_rounded, size: 14, color: _textColor),
            ),
          ],
        ),
      ),
    );
  }
}
