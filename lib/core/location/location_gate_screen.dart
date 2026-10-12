import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/app_colors.dart';
import 'location_service.dart';
import 'location_enabler.dart';

class LocationGateScreen extends StatefulWidget {
  final LocationService locationService;
  final VoidCallback? onManualSelect;

  const LocationGateScreen({
    super.key,
    required this.locationService,
    this.onManualSelect,
  });

  @override
  State<LocationGateScreen> createState() => _LocationGateScreenState();
}

class _LocationGateScreenState extends State<LocationGateScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleEnableLocationPressed();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleEnableLocationPressed() async {
    if (_isChecking || !mounted) return;
    setState(() => _isChecking = true);

    try {
      final turnedOn = await LocationEnabler.requestEnableLocation();
      if (!turnedOn) {
        if (mounted) setState(() => _isChecking = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        if (mounted) setState(() => _isChecking = false);
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        await widget.locationService.checkLocationAndAutoDetect();
      }
    } catch (e) {
      debugPrint('[LocationGateScreen] Prompt error: $e');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.locationService;
    final isPermDenied = loc.isPermissionDeniedForever;
    final isDetecting = _isChecking || loc.isDetectingLocation;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              const Spacer(flex: 2),

              Center(
                child: ScaleTransition(
                  scale: _pulseAnimation,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primarySoft,
                        ),
                      ),
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primarySoft,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                      ),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          loc.isLocationOff
                              ? Icons.location_off_rounded
                              : Icons.my_location_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 36),

              Text(
                loc.isLocationOff
                    ? 'Device Location is Off'
                    : isPermDenied
                        ? 'Location Permission Needed'
                        : 'Enable Your Location',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Nearhood is a hyper-local community app live exclusively in Vadodara. Turn on your device location to verify your area and access local posts, shops, and community alerts.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),

              const Spacer(flex: 3),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: isDetecting ? null : _handleEnableLocationPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: isDetecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isPermDenied
                              ? Icons.settings_rounded
                              : Icons.my_location_rounded,
                          size: 20,
                        ),
                  label: Text(
                    isDetecting
                        ? 'Detecting Location...'
                        : isPermDenied
                            ? 'Open App Settings'
                            : 'Turn On Device Location',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.place_rounded,
                          color: AppColors.primary,
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Currently serving Vadodara (GJ) only',
                          style: TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
