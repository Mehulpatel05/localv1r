import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'location_service.dart';
import 'location_models.dart';
import 'city_picker_screen.dart';

class LocationSelectorField extends StatefulWidget {
  final void Function(GeoCity city, GeoArea area) onLocationSelected;

  const LocationSelectorField({
    super.key,
    required this.onLocationSelected,
  });

  @override
  State<LocationSelectorField> createState() => _LocationSelectorFieldState();
}

class _LocationSelectorFieldState extends State<LocationSelectorField> {
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final city = locationService.city;

    if (!_initialized) {
      _initialized = true;
      final defaultArea = GeoArea(
        id: '${city.id}_GENERAL',
        cityId: city.id,
        name: 'All ${city.name}',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onLocationSelected(city, defaultArea);
        }
      });
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CityPickerScreen()),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFF3B82F6),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'City',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    city.name,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_right_rounded,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

