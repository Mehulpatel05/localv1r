import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'location_service.dart';
import 'city_picker_screen.dart';

class LocationChip extends StatelessWidget {
  const LocationChip({super.key});

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    
    return InkWell(
      onTap: () {
        // Show area picker bottom sheet
        _showAreaPicker(context, locationService);
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
              locationService.displayLabel,
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

  void _showAreaPicker(BuildContext context, LocationService locationService) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return _AreaPickerSheet(locationService: locationService);
      },
    );
  }
}

class _AreaPickerSheet extends StatelessWidget {
  final LocationService locationService;
  const _AreaPickerSheet({required this.locationService});

  @override
  Widget build(BuildContext context) {
    final city = locationService.city;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your location', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(city.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Text(city.stateId, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CityPickerScreen()));
                  },
                  child: const Text('Change ▸'),
                ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('AREA', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                // Filter out generic "General / All" duplicate item from specific areas list
                final specificAreas = city.areas
                    .where((a) => !a.id.contains('GENERAL') && !a.name.toLowerCase().contains('general / all'))
                    .toList();

                return ListView.builder(
                  itemCount: specificAreas.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final isSelected = locationService.area == null;
                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isSelected ? const Color(0xFF3B82F6) : Colors.grey,
                        ),
                        title: Text(
                          'All of ${city.name} (Default)',
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? const Color(0xFF3B82F6) : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          'Show posts from entire ${city.name}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        onTap: () {
                          locationService.setArea(null);
                          Navigator.pop(context);
                        },
                      );
                    }
                    final area = specificAreas[index - 1];
                    final isSelected = locationService.area?.id == area.id;
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: isSelected ? const Color(0xFF3B82F6) : Colors.grey,
                      ),
                      title: Text(
                        area.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFF3B82F6) : Colors.black87,
                        ),
                      ),
                      subtitle: area.pincode != null
                          ? Text('PIN: ${area.pincode}', style: const TextStyle(fontSize: 11, color: Colors.grey))
                          : null,
                      onTap: () {
                        locationService.setArea(area);
                        Navigator.pop(context);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
