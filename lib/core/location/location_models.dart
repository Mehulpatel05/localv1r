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
