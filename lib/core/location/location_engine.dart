import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'location_models.dart';
export 'location_models.dart';

// ── 2. HIGH-SPEED CONSOLIDATED ENGINE WITH O(1) HASH INDEXES ────────────────
class LocationEngine {
  static final Map<String, GeoCity> _cityIndex = {};
  static final Map<String, GeoArea> _pincodeIndex = {};
  static bool _isIndexed = false;

  /// O(1) Pre-indexing for 0ms Instant Lookups
  static void _ensureIndexed() {
    if (_isIndexed) return;
    for (final state in kPanIndiaStates) {
      for (final city in state.cities) {
        _cityIndex[city.id] = city;
        if (city.pincode != null) _pincodeIndex[city.pincode!] = city.areas.firstOrNull ?? GeoArea(id: city.id, cityId: city.id, name: city.name);
        for (final area in city.areas) {
          if (area.pincode != null) _pincodeIndex[area.pincode!] = area;
        }
      }
    }
    _isIndexed = true;
  }

  /// O(1) Lookup by City ID
  static GeoCity? lookupCity(String cityId) {
    _ensureIndexed();
    return _cityIndex[cityId];
  }

  /// O(1) Lookup by 6-Digit PIN Code
  static GeoArea? lookupPincode(String pin) {
    _ensureIndexed();
    return _pincodeIndex[pin];
  }

  /// Haversine Formula for 0ms Distance Calculation
  static double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final c = math.cos;
    final a = 0.5 - c((lat2 - lat1) * p) / 2 + c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a));
  }

  /// Fast Reverse Geocoding Matcher
  static ReverseGeocodeResult detectLocation(double lat, double lng) {
    _ensureIndexed();
    GeoState? bestState;
    GeoCity? bestCity;
    GeoArea? bestArea;
    double minDistance = double.infinity;

    for (final state in kPanIndiaStates) {
      for (final city in state.cities) {
        if (!city.enabled) continue;
        if (city.lat != null && city.lng != null) {
          final dist = calculateDistanceKm(lat, lng, city.lat!, city.lng!);
          if (dist < minDistance) {
            minDistance = dist;
            bestState = state;
            bestCity = city;
            bestArea = null;
          }
        }
        for (final area in city.areas) {
          if (area.lat != null && area.lng != null) {
            final dist = calculateDistanceKm(lat, lng, area.lat!, area.lng!);
            if (dist < minDistance) {
              minDistance = dist;
              bestState = state;
              bestCity = city;
              bestArea = area;
            }
          }
        }
      }
    }

    bestState ??= kPanIndiaStates.first;
    bestCity ??= bestState.cities.first;

    final isUnknown = minDistance > 50.0;
    if (kDebugMode) {
      debugPrint('[LocationEngine] detectLocation: lat=$lat, lng=$lng, detected city=${bestCity.name}, area=${bestArea?.name ?? "None"}, distance=${minDistance.toStringAsFixed(2)}km, isUnknown=$isUnknown');
    }

    return ReverseGeocodeResult(
      state: bestState,
      city: bestCity,
      area: bestArea,
      distanceKm: minDistance,
      isUnknownArea: isUnknown,
    );
  }
}

// ── 3. PAN-INDIA MASTER DATASET ──────────────────────────────────────────────
const kPanIndiaStates = [
  GeoState(
    id: 'GJ',
    name: 'Gujarat',
    cities: [
      GeoCity(
        id: 'GJ-VAD',
        stateId: 'GJ',
        name: 'Vadodara',
        enabled: true,
        lat: 22.3072,
        lng: 73.1812,
        pincode: '390001',
        areas: [
          GeoArea(id: 'GJ-VAD-GENERAL', cityId: 'GJ-VAD', name: 'General / All Vadodara', lat: 22.3072, lng: 73.1812),
          GeoArea(id: 'GJ-VAD-ALKAPURI', cityId: 'GJ-VAD', name: 'Alkapuri', pincode: '390007', lat: 22.3120, lng: 73.1740),
          GeoArea(id: 'GJ-VAD-SAYAJIGUNJ', cityId: 'GJ-VAD', name: 'Sayajigunj', pincode: '390005', lat: 22.3100, lng: 73.1880),
          GeoArea(id: 'GJ-VAD-GOTRI', cityId: 'GJ-VAD', name: 'Gotri', pincode: '390021', lat: 22.3180, lng: 73.1430),
          GeoArea(id: 'GJ-VAD-MANJALPUR', cityId: 'GJ-VAD', name: 'Manjalpur', pincode: '390011', lat: 22.2680, lng: 73.1960),
          GeoArea(id: 'GJ-VAD-KARELIBAUG', cityId: 'GJ-VAD', name: 'Karelibaug', pincode: '390018', lat: 22.3270, lng: 73.1970),
          GeoArea(id: 'GJ-VAD-FATEHGUNJ', cityId: 'GJ-VAD', name: 'Fatehgunj', pincode: '390002', lat: 22.3250, lng: 73.1860),
          GeoArea(id: 'GJ-VAD-SUBHANPURA', cityId: 'GJ-VAD', name: 'Subhanpura', pincode: '390023', lat: 22.3210, lng: 73.1550),
          GeoArea(id: 'GJ-VAD-AKOTA', cityId: 'GJ-VAD', name: 'Akota', pincode: '390020', lat: 22.2960, lng: 73.1700),
          GeoArea(id: 'GJ-VAD-VASNA', cityId: 'GJ-VAD', name: 'Vasna', pincode: '390007', lat: 22.2880, lng: 73.1520),
          GeoArea(id: 'GJ-VAD-BHAYLI', cityId: 'GJ-VAD', name: 'Bhayli', pincode: '391410', lat: 22.2790, lng: 73.1250),
        ],
      ),
      GeoCity(
        id: 'GJ-SRT',
        stateId: 'GJ',
        name: 'Surat',
        enabled: true,
        lat: 21.1702,
        lng: 72.8311,
        pincode: '395003',
        areas: [
          GeoArea(id: 'GJ-SRT-VESU', cityId: 'GJ-SRT', name: 'Vesu', pincode: '395007', lat: 21.1418, lng: 72.7709),
          GeoArea(id: 'GJ-SRT-ADAJAN', cityId: 'GJ-SRT', name: 'Adajan', pincode: '395009', lat: 21.1959, lng: 72.7933),
        ],
      ),
    ],
  ),
  GeoState(
    id: 'MH',
    name: 'Maharashtra',
    cities: [
      GeoCity(
        id: 'MH-MUM',
        stateId: 'MH',
        name: 'Mumbai',
        enabled: true,
        lat: 19.0760,
        lng: 72.8777,
        pincode: '400001',
        areas: [
          GeoArea(id: 'MH-MUM-BANDRA', cityId: 'MH-MUM', name: 'Bandra West', pincode: '400050', lat: 19.0596, lng: 72.8295),
          GeoArea(id: 'MH-MUM-ANDHERI', cityId: 'MH-MUM', name: 'Andheri West', pincode: '400058', lat: 19.1136, lng: 72.8397),
          GeoArea(id: 'MH-MUM-POWAI', cityId: 'MH-MUM', name: 'Powai', pincode: '400076', lat: 19.1176, lng: 72.9060),
        ],
      ),
      GeoCity(
        id: 'MH-PUN',
        stateId: 'MH',
        name: 'Pune',
        enabled: true,
        lat: 18.5204,
        lng: 73.8567,
        pincode: '411001',
        areas: [
          GeoArea(id: 'MH-PUN-BANER', cityId: 'MH-PUN', name: 'Baner', pincode: '411045', lat: 18.5590, lng: 73.7868),
          GeoArea(id: 'MH-PUN-HINJEWADI', cityId: 'MH-PUN', name: 'Hinjewadi', pincode: '411057', lat: 18.5912, lng: 73.7389),
        ],
      ),
    ],
  ),
  GeoState(
    id: 'DL',
    name: 'Delhi NCR',
    cities: [
      GeoCity(
        id: 'DL-DEL',
        stateId: 'DL',
        name: 'New Delhi',
        enabled: true,
        lat: 28.6139,
        lng: 77.2090,
        pincode: '110001',
        areas: [
          GeoArea(id: 'DL-DEL-CP', cityId: 'DL-DEL', name: 'Connaught Place', pincode: '110001', lat: 28.6315, lng: 77.2167),
          GeoArea(id: 'DL-DEL-DWARKA', cityId: 'DL-DEL', name: 'Dwarka', pincode: '110075', lat: 28.5921, lng: 77.0460),
        ],
      ),
    ],
  ),
  GeoState(
    id: 'KA',
    name: 'Karnataka',
    cities: [
      GeoCity(
        id: 'KA-BLR',
        stateId: 'KA',
        name: 'Bengaluru (Bangalore)',
        enabled: true,
        lat: 12.9716,
        lng: 77.5946,
        pincode: '560001',
        areas: [
          GeoArea(id: 'KA-BLR-INDIRA', cityId: 'KA-BLR', name: 'Indiranagar', pincode: '560038', lat: 12.9784, lng: 77.6408),
          GeoArea(id: 'KA-BLR-KORA', cityId: 'KA-BLR', name: 'Koramangala', pincode: '560034', lat: 12.9352, lng: 77.6245),
        ],
      ),
    ],
  ),
];
