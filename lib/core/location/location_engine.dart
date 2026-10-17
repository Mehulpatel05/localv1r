import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'location_models.dart';
import 'all_india_data.dart';
export 'location_models.dart';
export 'all_india_data.dart' show kAllIndiaStates;

// ── 2. HIGH-SPEED CONSOLIDATED ENGINE WITH O(1) HASH INDEXES ────────────────
class LocationEngine {
  static final Map<String, GeoCity> _cityIndex = {};
  static final Map<String, GeoArea> _areaIndex = {};
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
          _areaIndex[area.id] = area;
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

  /// O(1) Lookup by Area ID (e.g. 'GJ-VAD-ALKAPURI')
  static GeoArea? lookupArea(String areaId) {
    _ensureIndexed();
    final direct = _areaIndex[areaId];
    if (direct != null) return direct;
    if (areaId.endsWith('-ROAD')) {
      return _areaIndex[areaId.substring(0, areaId.length - 5)];
    }
    return null;
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
// Only Vadodara is enabled (true); all other cities across all states are "Coming soon" (enabled: false)
const kPanIndiaStates = kAllIndiaStates;

