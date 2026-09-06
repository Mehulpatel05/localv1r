import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'location_service.dart';
import 'location_models.dart';

class LocationSelectorField extends StatefulWidget {
  final void Function(GeoCity city, GeoArea area) onLocationSelected;

  const LocationSelectorField({
    Key? key,
    required this.onLocationSelected,
  }) : super(key: key);

  @override
  State<LocationSelectorField> createState() => _LocationSelectorFieldState();
}

class _LocationSelectorFieldState extends State<LocationSelectorField> {
  GeoArea? _selectedArea;

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final city = locationService.city;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Read-only City Field
        TextFormField(
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
            return DropdownMenuItem<GeoArea>(
              value: area,
              child: Text(area.name),
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
