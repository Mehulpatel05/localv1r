import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'location_service.dart';
import 'city_picker_screen.dart';

class LocationChip extends StatelessWidget {
  const LocationChip({super.key});

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final cityName = locationService.city.name;
    
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CityPickerScreen()),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.5), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 14, color: Colors.black87),
            const SizedBox(width: 4),
            Text(
              cityName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 16, color: Colors.black87),
          ],
        ),
      ),
    );
  }
}

