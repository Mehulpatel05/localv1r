class GeoState {
  final String id;
  final String name;
  final List<GeoCity> cities;
  const GeoState({required this.id, required this.name, required this.cities});
}

class GeoCity {
  final String id;
  final String stateId;
  final String name;
  final bool enabled;
  final List<GeoArea> areas;
  final double? lat;
  final double? lng;
  const GeoCity({
    required this.id,
    required this.stateId,
    required this.name,
    this.enabled = false,
    required this.areas,
    this.lat,
    this.lng,
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
