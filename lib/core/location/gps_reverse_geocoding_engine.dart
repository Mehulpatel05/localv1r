import 'dart:math' as math;
import 'location_models.dart';
import 'all_india_data.dart';
import 'location_service.dart';

class GPSLocationEngine {
  /// Detects closest Indian State, City and Sub-locality Area from GPS Coordinates (lat, lng)
  static ReverseGeocodeResult detectLocationFromCoordinates(double lat, double lng) {
    GeoState? bestState;
    GeoCity? bestCity;
    GeoArea? bestArea;
    double minDistanceKm = double.infinity;

    for (final state in kAllIndiaStates) {
      for (final city in state.cities) {
        if (!city.enabled) continue;

        // Check distance to City centroid
        if (city.lat != null && city.lng != null) {
          final distCity = LocationService.calculateDistanceKm(lat, lng, city.lat!, city.lng!);
          if (distCity < minDistanceKm) {
            minDistanceKm = distCity;
            bestState = state;
            bestCity = city;
            bestArea = null;
          }
        }

        // Check distance to specific Sub-locality Areas
        for (final area in city.areas) {
          if (area.lat != null && area.lng != null) {
            final distArea = LocationService.calculateDistanceKm(lat, lng, area.lat!, area.lng!);
            if (distArea < minDistanceKm) {
              minDistanceKm = distArea;
              bestState = state;
              bestCity = city;
              bestArea = area;
            }
          }
        }
      }
    }

    // Fallback if no exact match found
    bestState ??= kAllIndiaStates.first;
    bestCity ??= bestState.cities.first;

    // Calculate accuracy score (1.0 = within 5km, decreases gracefully)
    final accuracy = math.max(0.2, 1.0 - (minDistanceKm / 100.0));

    return ReverseGeocodeResult(
      state: bestState,
      city: bestCity,
      area: bestArea,
      distanceKm: minDistanceKm,
      accuracyScore: accuracy,
    );
  }

  /// Parses address string / query to match State, City, Sub-locality, or 6-Digit PIN Code
  static List<ReverseGeocodeResult> searchPanIndiaLocation(String query) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final List<ReverseGeocodeResult> results = [];

    for (final state in kAllIndiaStates) {
      for (final city in state.cities) {
        if (!city.enabled) continue;

        final cityMatches = city.name.toLowerCase().contains(cleanQuery) ||
            city.id.toLowerCase().contains(cleanQuery) ||
            (city.pincode != null && city.pincode!.contains(cleanQuery));

        if (cityMatches) {
          results.add(ReverseGeocodeResult(
            state: state,
            city: city,
            area: null,
            distanceKm: 0.0,
            accuracyScore: 1.0,
          ));
        }

        for (final area in city.areas) {
          final areaMatches = area.name.toLowerCase().contains(cleanQuery) ||
              (area.pincode != null && area.pincode!.contains(cleanQuery));

          if (areaMatches) {
            results.add(ReverseGeocodeResult(
              state: state,
              city: city,
              area: area,
              distanceKm: 0.0,
              accuracyScore: 1.0,
            ));
          }
        }
      }
    }

    return results;
  }
}
