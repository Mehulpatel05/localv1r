import 'location_models.dart';

const kGujarat = GeoState(
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
      areas: [
        GeoArea(id: 'GJ-VAD-GENERAL', cityId: 'GJ-VAD', name: 'General / All Vadodara'),
        GeoArea(id: 'GJ-VAD-ALKAPURI', cityId: 'GJ-VAD', name: 'Alkapuri', pincode: '390007'),
        GeoArea(id: 'GJ-VAD-SAYAJIGUNJ', cityId: 'GJ-VAD', name: 'Sayajigunj', pincode: '390005'),
        GeoArea(id: 'GJ-VAD-GOTRI', cityId: 'GJ-VAD', name: 'Gotri', pincode: '390021'),
        GeoArea(id: 'GJ-VAD-MANJALPUR', cityId: 'GJ-VAD', name: 'Manjalpur', pincode: '390011'),
        GeoArea(id: 'GJ-VAD-KARELIBAUG', cityId: 'GJ-VAD', name: 'Karelibaug', pincode: '390018'),
        GeoArea(id: 'GJ-VAD-FATEHGUNJ', cityId: 'GJ-VAD', name: 'Fatehgunj', pincode: '390002'),
        GeoArea(id: 'GJ-VAD-SUBHANPURA', cityId: 'GJ-VAD', name: 'Subhanpura', pincode: '390023'),
        GeoArea(id: 'GJ-VAD-WAGHODIA', cityId: 'GJ-VAD', name: 'Waghodia Road', pincode: '390019'),
        GeoArea(id: 'GJ-VAD-AKOTA', cityId: 'GJ-VAD', name: 'Akota', pincode: '390020'),
        GeoArea(id: 'GJ-VAD-VASNA', cityId: 'GJ-VAD', name: 'Vasna', pincode: '390007'),
        GeoArea(id: 'GJ-VAD-BHAYLI', cityId: 'GJ-VAD', name: 'Bhayli', pincode: '391410'),
        GeoArea(id: 'GJ-VAD-SAMA', cityId: 'GJ-VAD', name: 'Sama', pincode: '390008'),
        GeoArea(id: 'GJ-VAD-HARNI', cityId: 'GJ-VAD', name: 'Harni', pincode: '390022'),
        GeoArea(id: 'GJ-VAD-MAKARPURA', cityId: 'GJ-VAD', name: 'Makarpura', pincode: '390014'),
        GeoArea(id: 'GJ-VAD-TANDALJA', cityId: 'GJ-VAD', name: 'Tandalja', pincode: '390012'),
        GeoArea(id: 'GJ-VAD-NIZAMPURA', cityId: 'GJ-VAD', name: 'Nizampura', pincode: '390002'),
        GeoArea(id: 'GJ-VAD-CHHANI', cityId: 'GJ-VAD', name: 'Chhani', pincode: '391740'),
        GeoArea(id: 'GJ-VAD-DANDIA', cityId: 'GJ-VAD', name: 'Dandia Bazaar', pincode: '390001'),
        GeoArea(id: 'GJ-VAD-RAOPURA', cityId: 'GJ-VAD', name: 'Raopura', pincode: '390001'),
        GeoArea(id: 'GJ-VAD-OPR', cityId: 'GJ-VAD', name: 'Old Padra Road', pincode: '390015'),
        GeoArea(id: 'GJ-VAD-OTHER', cityId: 'GJ-VAD', name: 'Other / Not listed'),
      ],
    ),
    GeoCity(id: 'GJ-SRT', stateId: 'GJ', name: 'Surat', enabled: false, areas: []),
    GeoCity(id: 'GJ-AMD', stateId: 'GJ', name: 'Ahmedabad', enabled: false, areas: []),
    GeoCity(id: 'GJ-RJT', stateId: 'GJ', name: 'Rajkot', enabled: false, areas: []),
  ],
);

const kStates = [kGujarat];

GeoCity? lookupCity(String cityId) {
  for (final state in kStates) {
    for (final city in state.cities) {
      if (city.id == cityId) return city;
    }
  }
  return null;
}
