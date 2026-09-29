import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'location_service.dart';

class ProximityRadiusFilterBar extends StatelessWidget {
  const ProximityRadiusFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentRadius = locationService.selectedRadiusKm;
    final currentArea = locationService.area;

    final options = [
      {'label': 'Citywide', 'value': 0.0},
      {'label': '10 km', 'value': 10.0},
      {'label': '20 km', 'value': 20.0},
      {'label': '30 km', 'value': 30.0},
      {'label': '40 km', 'value': 40.0},
      {'label': '50 km', 'value': 50.0},
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: options.length + (currentArea != null ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          // If area is selected, show Area badge as first item
          if (currentArea != null && index == 0) {
            return InputChip(
              avatar: Icon(
                Icons.near_me_rounded,
                size: 14,
                color: isDark ? Colors.white : Colors.black,
              ),
              label: Text(
                currentArea.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: isDark ? const Color(0xFF27272A) : const Color(0xFFE2E8F0),
              shape: StadiumBorder(
                side: BorderSide(
                  color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFCBD5E1),
                ),
              ),
              onDeleted: () {
                context.read<LocationService>().setArea(null);
              },
              deleteIconColor: isDark ? Colors.white70 : Colors.black54,
            );
          }

          final optIndex = currentArea != null ? index - 1 : index;
          final option = options[optIndex];
          final val = option['value'] as double;
          final label = option['label'] as String;
          final isSelected = currentRadius == val;

          return ChoiceChip(
            showCheckmark: false,
            label: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF475569)),
              ),
            ),
            selected: isSelected,
            selectedColor: isDark ? Colors.white : Colors.black,
            backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF1F5F9),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            shape: StadiumBorder(
              side: BorderSide(
                color: isSelected
                    ? (isDark ? Colors.white : Colors.black)
                    : (isDark ? const Color(0xFF27272A) : const Color(0xFFE2E8F0)),
              ),
            ),
            onSelected: (selected) {
              if (selected) {
                context.read<LocationService>().setSelectedRadius(val);
              }
            },
          );
        },
      ),
    );
  }
}
