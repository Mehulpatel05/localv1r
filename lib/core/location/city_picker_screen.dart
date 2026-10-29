import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../services/founding_service.dart';
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
    FoundingService.instance.fetchCounts();
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Select Location & Neighborhood'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: InkWell(
              onTap: () async {
                final success = await locService.checkLocationAndAutoDetect(force: true);
                if (success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Location auto-detected: ${locService.displayLabel}'),
                      backgroundColor: AppColors.primary,
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
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: locService.isDetectingLocation
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 16),
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
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            locService.isDetectingLocation
                                ? 'Reverse geocoding & permission check...'
                                : 'Pan-India Reverse Geocoding GPS Engine',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search city, area, pincode or address...',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
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
                          color: AppColors.textMuted,
                          fontSize: 12,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    ...state.cities.map((city) {
                      final isEnabled = city.enabled;
                      final isCitySelected = currentCityId == city.id;

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
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: AppColors.chipBg,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_city_rounded,
                                color: AppColors.textMuted,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              city.name,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.chipBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Coming soon',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            onTap: () => _joinWaitlist(context, city.id, city.name),
                          ),
                        );
                      }

                      final areaWidgets = <Widget>[];

                      for (int i = 0; i < areas.length; i++) {
                        final area = areas[i];
                        final isAreaSelected = isCitySelected && currentAreaId == area.id;

                        if (i > 0) {
                          areaWidgets.add(const Divider(height: 1, color: AppColors.divider, indent: 16, endIndent: 16));
                        }
                        areaWidgets.add(
                          InkWell(
                            onTap: () {
                              locService.setCity(city);
                              locService.setArea(area);
                              Navigator.pop(context);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  const SizedBox(width: 32),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                area.name,
                                                style: TextStyle(
                                                  fontSize: 15.5,
                                                  fontWeight: isAreaSelected ? FontWeight.w700 : FontWeight.w600,
                                                  color: isAreaSelected
                                                      ? AppColors.primary
                                                      : AppColors.textPrimary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (area.pincode != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'PIN: ${area.pincode}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (isAreaSelected) ...[
                                    const SizedBox(width: 10),
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      return Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            initiallyExpanded: isCitySelected,
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isCitySelected ? AppColors.primarySoft : AppColors.chipBg,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.location_city_rounded,
                                color: isCitySelected
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              city.name,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: isCitySelected ? FontWeight.bold : FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: ListenableBuilder(
                              listenable: FoundingService.instance,
                              builder: (context, _) {
                                final hasLoaded = FoundingService.instance.hasLoadedCounts;
                                final citySpotsLeft = FoundingService.instance.getSpotsLeft(city.id);
                                return Text(
                                  hasLoaded && citySpotsLeft > 0
                                      ? '${city.areas.length} Neighborhoods · $citySpotsLeft founding spots left'
                                      : '${city.areas.length} Neighborhoods',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                );
                              },
                            ),
                            children: [
                              const Divider(height: 1, color: AppColors.divider),
                              ...areaWidgets,
                            ],
                          ),
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('waitlist_joined_$cityId', true);

      final phone = await AuthService.instance.getPhoneNumber() ?? '';
      final handle = await AuthService.instance.getUserHandle() ?? '';
      final contact = phone.isNotEmpty ? phone : (handle.isNotEmpty ? handle : 'device_${DateTime.now().millisecondsSinceEpoch}');

      final token = await AuthService.instance.getAccessToken();
      await http.post(
        Uri.parse('${AuthService.baseUrl}/places/waitlist'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'city_text': cityName,
          'contact_or_device_id': contact,
        }),
      ).timeout(const Duration(seconds: 6));
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined waitlist for $cityName! We will notify you when we launch.')),
      );
    }
  }
}
