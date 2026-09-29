import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'location_engine.dart';
import 'location_service.dart';

class CityPickerScreen extends StatefulWidget {
  const CityPickerScreen({super.key});

  @override
  State<CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends State<CityPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locService = context.watch<LocationService>();
    final currentCityId = locService.cityId;
    final currentAreaId = locService.areaId;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Select Location & Neighborhood'),
        backgroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Column(
        children: [
          // Auto-detect location button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: InkWell(
              onTap: () async {
                final success = await locService.checkLocationAndAutoDetect();
                if (success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🎯 Location auto-detected: ${locService.displayLabel}'),
                      backgroundColor: const Color(0xFF072E33),
                    ),
                  );
                  Navigator.pop(context);
                } else if (context.mounted) {
                  if (locService.isLocationOff) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Location Services (GPS) is OFF on device.'),
                        action: SnackBarAction(
                          label: 'Enable',
                          textColor: Colors.white,
                          onPressed: () => Geolocator.openLocationSettings(),
                        ),
                      ),
                    );
                  } else if (locService.isPermissionDenied) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Location permission denied.'),
                        action: SnackBarAction(
                          label: 'Settings',
                          textColor: Colors.white,
                          onPressed: () => Geolocator.openAppSettings(),
                        ),
                      ),
                    );
                  } else if (locService.isUnknownArea) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Outside 50 km supported radius. Please select your nearest city below.'),
                      ),
                    );
                  }
                }
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF072E33),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF0E4B52)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0E4B52),
                        shape: BoxShape.circle,
                      ),
                      child: locService.isDetectingLocation
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.my_location_rounded, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            locService.isDetectingLocation
                                ? 'Detecting Location via GPS...'
                                : 'Use Current Location (Auto-Detect)',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            locService.isDetectingLocation
                                ? 'Reverse geocoding & permission check...'
                                : 'Pan-India Reverse Geocoding GPS Engine',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF90B4B6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
          ),

          // Search box for neighborhoods / pincodes
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search city, area, pincode or address...',
                hintStyle: const TextStyle(color: Color(0xFF90B4B6)),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF90B4B6)),
                filled: true,
                fillColor: const Color(0xFF072E33),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF0E4B52)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF0E4B52)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),

          Expanded(
            child: ListView.builder(
              itemCount: kPanIndiaStates.length,
              itemBuilder: (context, stateIndex) {
                final state = kPanIndiaStates[stateIndex];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text(
                        state.name.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF90B4B6),
                          fontSize: 12,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    ...state.cities.map((city) {
                      final isEnabled = city.enabled;
                      final isCitySelected = currentCityId == city.id;

                      // Filter areas if searching
                      final areas = city.areas.where((a) {
                        if (_searchQuery.isEmpty) return true;
                        final nameMatches = a.name.toLowerCase().contains(_searchQuery);
                        final pinMatches = a.pincode?.contains(_searchQuery) ?? false;
                        final cityMatches = city.name.toLowerCase().contains(_searchQuery);
                        return nameMatches || pinMatches || cityMatches;
                      }).toList();

                      if (!isEnabled) {
                        if (_searchQuery.isNotEmpty && !city.name.toLowerCase().contains(_searchQuery)) {
                          return const SizedBox.shrink();
                        }
                        return ListTile(
                          title: Text(
                            city.name,
                            style: const TextStyle(color: Color(0xFF90B4B6)),
                          ),
                          trailing: const Text('Coming soon', style: TextStyle(color: Color(0xFF90B4B6), fontSize: 12)),
                          onTap: () => _joinWaitlist(context, city.id, city.name),
                        );
                      }

                      return Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded: isCitySelected,
                          leading: Icon(
                            Icons.location_city_rounded,
                            color: isCitySelected
                                ? Colors.white
                                : const Color(0xFF90B4B6),
                          ),
                          title: Text(
                            city.name,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: isCitySelected ? FontWeight.bold : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${city.areas.length} Neighborhoods',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF90B4B6),
                            ),
                          ),
                          children: [
                            // Option 1: Citywide
                            ListTile(
                              contentPadding: const EdgeInsets.only(left: 48, right: 16),
                              title: Text(
                                'All ${city.name} (Citywide)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: (isCitySelected && currentAreaId == null)
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: (isCitySelected && currentAreaId == null)
                                      ? Colors.white
                                      : const Color(0xFF90B4B6),
                                ),
                              ),
                              trailing: (isCitySelected && currentAreaId == null)
                                  ? const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18)
                                  : null,
                              onTap: () {
                                locService.setCity(city);
                                locService.setArea(null);
                                Navigator.pop(context);
                              },
                            ),
                            // Neighborhood areas list
                            ...areas.map((area) {
                              final isAreaSelected = isCitySelected && currentAreaId == area.id;

                              return ListTile(
                                contentPadding: const EdgeInsets.only(left: 48, right: 16),
                                title: Text(
                                  area.name,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isAreaSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isAreaSelected
                                        ? Colors.white
                                        : const Color(0xFF90B4B6),
                                  ),
                                ),
                                subtitle: area.pincode != null
                                    ? Text(
                                        'PIN: ${area.pincode}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF90B4B6),
                                        ),
                                      )
                                    : null,
                                trailing: isAreaSelected
                                    ? const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18)
                                    : null,
                                onTap: () {
                                  locService.setCity(city);
                                  locService.setArea(area);
                                  Navigator.pop(context);
                                },
                              );
                            }),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _joinWaitlist(BuildContext context, String cityId, String cityName) async {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined waitlist for $cityName! We will notify you when we launch.')),
      );
    }
  }
}
