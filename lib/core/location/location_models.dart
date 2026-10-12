class GeoState {
  final String id;
  final String name;
  final List<GeoCity> cities;

  const GeoState({
    required this.id,
    required this.name,
    required this.cities,
  });
}

class GeoCity {
  final String id;
  final String stateId;
  final String name;
  final bool enabled;
  final List<GeoArea> areas;
  final double? lat;
  final double? lng;
  final String? pincode;

  const GeoCity({
    required this.id,
    required this.stateId,
    required this.name,
    this.enabled = true,
    required this.areas,
    this.lat,
    this.lng,
    this.pincode,
  });
}

class GeoArea {
  final String id;
  final String cityId;
  final String name;
  final String? pincode;
  final double? lat;
  final double? lng;

  const GeoArea({
    required this.id,
    required this.cityId,
    required this.name,
    this.pincode,
    this.lat,
    this.lng,
  });
}

/// High-accuracy GPS Reverse Geocoding result
class ReverseGeocodeResult {
  final GeoState state;
  final GeoCity city;
  final GeoArea? area;
  final double distanceKm;
  final double accuracyScore; // 0.0 to 1.0 (1.0 = exact match)
  final bool isUnknownArea;

  const ReverseGeocodeResult({
    required this.state,
    required this.city,
    this.area,
    required this.distanceKm,
    this.accuracyScore = 1.0,
    this.isUnknownArea = false,
  });

  String get formattedLocation {
    if (isUnknownArea) {
      return 'Unknown Area (>50 km)';
    }
    if (area != null) {
      return '${area!.name}, ${city.name}';
    }
    return '${city.name}, ${state.name}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// v2: Location Source — where did we get this location from?
// ─────────────────────────────────────────────────────────────────────────────
enum LocationSource {
  gps,          // Fresh GPS fix
  lastKnown,    // Cached last-known GPS position
  ipFallback,   // Detected via IP geolocation (no GPS permission needed)
  manual,       // User manually picked city/area
  defaultCity,  // Hard-coded default (Vadodara) — last resort
}

// ─────────────────────────────────────────────────────────────────────────────
// v2: Richer snapshot of the resolved location
// ─────────────────────────────────────────────────────────────────────────────
class LocationContext {
  final GeoCity city;
  final GeoArea? area;
  final double? rawLat;
  final double? rawLng;
  final LocationSource source;

  /// 0.0 – 1.0  (GPS fresh ≈ 1.0 · IP fallback ≈ 0.5 · default ≈ 0.1)
  final double confidenceScore;

  /// When this snapshot was resolved
  final DateTime fetchedAt;

  /// Distance to nearest known city/area centre (km)
  final double distanceKm;

  const LocationContext({
    required this.city,
    this.area,
    this.rawLat,
    this.rawLng,
    required this.source,
    required this.confidenceScore,
    required this.fetchedAt,
    this.distanceKm = 0,
  });

  /// Human-readable label (e.g. "Alkapuri, Vadodara")
  String get displayLabel =>
      area == null ? city.name : '${area!.name}, ${city.name}';

  /// Short badge that appears below the location chip
  String get sourceBadge {
    switch (source) {
      case LocationSource.gps:
        return 'GPS';
      case LocationSource.lastKnown:
        return '~Last Known';
      case LocationSource.ipFallback:
        return '~Approx';
      case LocationSource.manual:
        return 'Manual';
      case LocationSource.defaultCity:
        return 'Default';
    }
  }

  /// Whether this snapshot is older than [maxAge]
  bool isStale({Duration maxAge = const Duration(hours: 1)}) =>
      DateTime.now().difference(fetchedAt) > maxAge;

  LocationContext copyWith({
    GeoCity? city,
    GeoArea? area,
    double? rawLat,
    double? rawLng,
    LocationSource? source,
    double? confidenceScore,
    DateTime? fetchedAt,
    double? distanceKm,
  }) {
    return LocationContext(
      city: city ?? this.city,
      area: area ?? this.area,
      rawLat: rawLat ?? this.rawLat,
      rawLng: rawLng ?? this.rawLng,
      source: source ?? this.source,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }
}
