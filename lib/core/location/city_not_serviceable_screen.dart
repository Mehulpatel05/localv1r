import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import 'location_service.dart';
import 'city_picker_screen.dart';

class CityNotServiceableScreen extends StatefulWidget {
  final LocationService locationService;
  final VoidCallback? onPreviewVadodara;
  final VoidCallback? onManualSelect;

  const CityNotServiceableScreen({
    super.key,
    required this.locationService,
    this.onPreviewVadodara,
    this.onManualSelect,
  });

  @override
  State<CityNotServiceableScreen> createState() => _CityNotServiceableScreenState();
}

class _CityNotServiceableScreenState extends State<CityNotServiceableScreen> {
  bool _isRechecking = false;
  bool _joinedWaitlist = false;

  @override
  void initState() {
    super.initState();
    _checkSavedWaitlist();
  }

  Future<void> _checkSavedWaitlist() async {
    final prefs = await SharedPreferences.getInstance();
    final cityText = widget.locationService.city.name;
    final saved = prefs.getBool('waitlist_joined_$cityText') ?? false;
    if (mounted && saved) {
      setState(() => _joinedWaitlist = true);
    }
  }

  Future<void> _handleRecheckLocation() async {
    setState(() => _isRechecking = true);
    final success = await widget.locationService.checkLocationAndAutoDetect();
    if (mounted) {
      setState(() => _isRechecking = false);
      if (!success && widget.locationService.isUnknownArea) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still detected outside Vadodara. Ensure GPS signal is clear.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleJoinWaitlist() async {
    setState(() => _joinedWaitlist = true);
    final cityText = widget.locationService.city.name.isNotEmpty && widget.locationService.city.id != 'GJ-VAD'
        ? widget.locationService.city.name
        : 'Unknown';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('waitlist_joined_$cityText', true);

      final phone = await AuthService.instance.getPhoneNumber() ?? '';
      final handle = await AuthService.instance.getUserHandle() ?? '';
      final contact = phone.isNotEmpty ? phone : (handle.isNotEmpty ? handle : 'device_${DateTime.now().millisecondsSinceEpoch}');

      final lat = widget.locationService.rawLat;
      final lng = widget.locationService.rawLng;

      final token = await AuthService.instance.getAccessToken();
      await http.post(
        Uri.parse('${AuthService.baseUrl}/places/waitlist'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'city_text': cityText,
          'contact_or_device_id': contact,
          'lat': lat,
          'lng': lng,
        }),
      ).timeout(const Duration(seconds: 6));
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "You're on the waitlist! We will notify you when Nearhood launches in your city.",
                style: TextStyle(fontSize: 13.5, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.locationService;
    final detectedName = loc.city.name.isNotEmpty && loc.city.id != 'GJ-VAD'
        ? loc.city.name
        : 'Outside Vadodara';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              const Spacer(flex: 2),

              Center(
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primarySoft,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.location_city_rounded,
                    color: AppColors.primary,
                    size: 52,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.explore_off_rounded, color: AppColors.error, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Detected: $detectedName',
                      style: const TextStyle(
                        color: AppColors.errorSoftText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                "Nearhood is Live Only in Vadodara!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                "We are currently dedicated exclusively to Vadodara neighborhoods to ensure a trusted, hyper-local community experience. We are expanding to other cities soon!",
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
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _joinedWaitlist ? null : _handleJoinWaitlist,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    _joinedWaitlist ? Icons.check_circle_rounded : Icons.notifications_active_rounded,
                    size: 20,
                  ),
                  label: Text(
                    _joinedWaitlist ? 'Waitlist Joined' : 'Notify Me When You Launch',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _isRechecking ? null : _handleRecheckLocation,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(
                      color: AppColors.divider,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isRechecking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18, color: AppColors.primary),
                  label: Text(
                    _isRechecking ? 'Re-checking GPS...' : 'Re-check My Location',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              TextButton(
                onPressed: () {
                  if (widget.onPreviewVadodara != null) {
                    widget.onPreviewVadodara!();
                  } else if (widget.onManualSelect != null) {
                    widget.onManualSelect!();
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CityPickerScreen()),
                    );
                  }
                },
                child: const Text(
                  'Explore Vadodara as Guest',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
