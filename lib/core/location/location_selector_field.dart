import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'location_service.dart';
import 'location_models.dart';

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
  GeoArea? _selectedArea;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final city = locationService.city;

    if (!_initialized || (_selectedArea != null && _selectedArea!.cityId != city.id)) {
      final generalArea = city.areas.where((a) => a.id.contains('GENERAL') || a.name.toLowerCase().contains('general')).firstOrNull;
      _selectedArea = locationService.area ?? generalArea ?? (city.areas.isNotEmpty ? city.areas.first : null);
      _initialized = true;
      if (_selectedArea != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedArea != null) {
            widget.onLocationSelected(city, _selectedArea!);
          }
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Read-only City Field
        TextFormField(
          key: ValueKey(city.id),
          initialValue: city.name,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'City',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Color(0xFFF3F4F6), // light gray to indicate read-only
          ),
        ),
        const SizedBox(height: 16),
        // Dropdown Area Field
        DropdownButtonFormField<GeoArea>(
          decoration: const InputDecoration(
            labelText: 'Area *',
            border: OutlineInputBorder(),
          ),
          value: _selectedArea,
          items: city.areas.map((area) {
            final isGeneral = area.id.contains('GENERAL') || area.name.toLowerCase().contains('general');
            return DropdownMenuItem<GeoArea>(
              value: area,
              child: Text(
                isGeneral ? 'General / All ${city.name} (Whole City)' : area.name,
                style: TextStyle(
                  fontWeight: isGeneral ? FontWeight.bold : FontWeight.normal,
                  color: isGeneral ? const Color(0xFF3B82F6) : Colors.black87,
                ),
              ),
            );
          }).toList(),
          onChanged: (area) {
            setState(() {
              _selectedArea = area;
            });
            if (area != null) {
              widget.onLocationSelected(city, area);
            }
          },
          validator: (value) => value == null ? 'Please select an area' : null,
        ),
      ],
    );
  }
}
