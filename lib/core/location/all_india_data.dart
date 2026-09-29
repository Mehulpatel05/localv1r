import 'location_models.dart';
import 'gujarat_data.dart';

// ── 1. MAHARASHTRA ──────────────────────────────────────────────────────────
const kMaharashtra = GeoState(
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
        GeoArea(id: 'MH-MUM-GENERAL', cityId: 'MH-MUM', name: 'General / All Mumbai', lat: 19.0760, lng: 72.8777),
        GeoArea(id: 'MH-MUM-BANDRA', cityId: 'MH-MUM', name: 'Bandra West', pincode: '400050', lat: 19.0596, lng: 72.8295),
        GeoArea(id: 'MH-MUM-ANDHERI-W', cityId: 'MH-MUM', name: 'Andheri West', pincode: '400058', lat: 19.1136, lng: 72.8397),
        GeoArea(id: 'MH-MUM-ANDHERI-E', cityId: 'MH-MUM', name: 'Andheri East', pincode: '400069', lat: 19.1197, lng: 72.8464),
        GeoArea(id: 'MH-MUM-POWAI', cityId: 'MH-MUM', name: 'Powai', pincode: '400076', lat: 19.1176, lng: 72.9060),
        GeoArea(id: 'MH-MUM-JUHU', cityId: 'MH-MUM', name: 'Juhu', pincode: '400049', lat: 19.1075, lng: 72.8263),
        GeoArea(id: 'MH-MUM-COLABA', cityId: 'MH-MUM', name: 'Colaba', pincode: '400005', lat: 18.9067, lng: 72.8147),
        GeoArea(id: 'MH-MUM-FORT', cityId: 'MH-MUM', name: 'Fort', pincode: '400001', lat: 18.9322, lng: 72.8335),
        GeoArea(id: 'MH-MUM-WORLI', cityId: 'MH-MUM', name: 'Worli', pincode: '400018', lat: 19.0176, lng: 72.8170),
        GeoArea(id: 'MH-MUM-THANE', cityId: 'MH-MUM', name: 'Thane West', pincode: '400601', lat: 19.2183, lng: 72.9781),
        GeoArea(id: 'MH-MUM-NAVI', cityId: 'MH-MUM', name: 'Navi Mumbai (Vashi)', pincode: '400703', lat: 19.0770, lng: 72.9986),
        GeoArea(id: 'MH-MUM-MALAD', cityId: 'MH-MUM', name: 'Malad West', pincode: '400064', lat: 19.1874, lng: 72.8484),
        GeoArea(id: 'MH-MUM-BORIVALI', cityId: 'MH-MUM', name: 'Borivali West', pincode: '400092', lat: 19.2307, lng: 72.8567),
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
        GeoArea(id: 'MH-PUN-GENERAL', cityId: 'MH-PUN', name: 'General / All Pune', lat: 18.5204, lng: 73.8567),
        GeoArea(id: 'MH-PUN-BANER', cityId: 'MH-PUN', name: 'Baner', pincode: '411045', lat: 18.5590, lng: 73.7868),
        GeoArea(id: 'MH-PUN-KOTHRUD', cityId: 'MH-PUN', name: 'Kothrud', pincode: '411038', lat: 18.5074, lng: 73.8077),
        GeoArea(id: 'MH-PUN-HINJEWADI', cityId: 'MH-PUN', name: 'Hinjewadi IT Park', pincode: '411057', lat: 18.5912, lng: 73.7389),
        GeoArea(id: 'MH-PUN-VIMAN', cityId: 'MH-PUN', name: 'Viman Nagar', pincode: '411014', lat: 18.5679, lng: 73.9143),
        GeoArea(id: 'MH-PUN-WAKAD', cityId: 'MH-PUN', name: 'Wakad', pincode: '411057', lat: 18.5987, lng: 73.7663),
        GeoArea(id: 'MH-PUN-KOREGAON', cityId: 'MH-PUN', name: 'Koregaon Park', pincode: '411001', lat: 18.5362, lng: 73.8940),
        GeoArea(id: 'MH-PUN-AUNDH', cityId: 'MH-PUN', name: 'Aundh', pincode: '411007', lat: 18.5580, lng: 73.8075),
      ],
    ),
    GeoCity(
      id: 'MH-NAG',
      stateId: 'MH',
      name: 'Nagpur',
      enabled: true,
      lat: 21.1458,
      lng: 79.0882,
      pincode: '440001',
      areas: [
        GeoArea(id: 'MH-NAG-GENERAL', cityId: 'MH-NAG', name: 'General / All Nagpur', lat: 21.1458, lng: 79.0882),
        GeoArea(id: 'MH-NAG-DHARAMPETH', cityId: 'MH-NAG', name: 'Dharampeth', pincode: '440010', lat: 21.1408, lng: 79.0645),
        GeoArea(id: 'MH-NAG-SADAR', cityId: 'MH-NAG', name: 'Sadar', pincode: '440001', lat: 21.1610, lng: 79.0805),
      ],
    ),
  ],
);

// ── 2. DELHI NCR ────────────────────────────────────────────────────────────
const kDelhiNCR = GeoState(
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
        GeoArea(id: 'DL-DEL-GENERAL', cityId: 'DL-DEL', name: 'General / All Delhi', lat: 28.6139, lng: 77.2090),
        GeoArea(id: 'DL-DEL-CP', cityId: 'DL-DEL', name: 'Connaught Place', pincode: '110001', lat: 28.6315, lng: 77.2167),
        GeoArea(id: 'DL-DEL-SOUTH', cityId: 'DL-DEL', name: 'South Extension / Hauz Khas', pincode: '110049', lat: 28.5494, lng: 77.2001),
        GeoArea(id: 'DL-DEL-DWARKA', cityId: 'DL-DEL', name: 'Dwarka', pincode: '110075', lat: 28.5921, lng: 77.0460),
        GeoArea(id: 'DL-DEL-ROHINI', cityId: 'DL-DEL', name: 'Rohini', pincode: '110085', lat: 28.7041, lng: 77.1025),
        GeoArea(id: 'DL-DEL-LAJPAT', cityId: 'DL-DEL', name: 'Lajpat Nagar', pincode: '110024', lat: 28.5677, lng: 77.2433),
        GeoArea(id: 'DL-DEL-KAROL', cityId: 'DL-DEL', name: 'Karol Bagh', pincode: '110005', lat: 28.6517, lng: 77.1906),
      ],
    ),
    GeoCity(
      id: 'DL-GUR',
      stateId: 'DL',
      name: 'Gurgaon (Gurugram)',
      enabled: true,
      lat: 28.4595,
      lng: 77.0266,
      pincode: '122001',
      areas: [
        GeoArea(id: 'DL-GUR-GENERAL', cityId: 'DL-GUR', name: 'General / All Gurgaon', lat: 28.4595, lng: 77.0266),
        GeoArea(id: 'DL-GUR-CYBER', cityId: 'DL-GUR', name: 'Cyber City (DLF Phase 2/3)', pincode: '122002', lat: 28.4950, lng: 77.0895),
        GeoArea(id: 'DL-GUR-GOLF', cityId: 'DL-GUR', name: 'Golf Course Road (Sector 54/56)', pincode: '122011', lat: 28.4390, lng: 77.0980),
        GeoArea(id: 'DL-GUR-SOBNA', cityId: 'DL-GUR', name: 'Sohna Road (Sector 48/49)', pincode: '122018', lat: 28.4162, lng: 77.0428),
      ],
    ),
    GeoCity(
      id: 'DL-NOI',
      stateId: 'DL',
      name: 'Noida',
      enabled: true,
      lat: 28.5355,
      lng: 77.3910,
      pincode: '201301',
      areas: [
        GeoArea(id: 'DL-NOI-GENERAL', cityId: 'DL-NOI', name: 'General / All Noida', lat: 28.5355, lng: 77.3910),
        GeoArea(id: 'DL-NOI-18', cityId: 'DL-NOI', name: 'Sector 18 (Atta Market)', pincode: '201301', lat: 28.5708, lng: 77.3261),
        GeoArea(id: 'DL-NOI-62', cityId: 'DL-NOI', name: 'Sector 62 (IT Hub)', pincode: '201309', lat: 28.6270, lng: 77.3726),
        GeoArea(id: 'DL-NOI-EXT', cityId: 'DL-NOI', name: 'Greater Noida West', pincode: '201306', lat: 28.5800, lng: 77.4500),
      ],
    ),
  ],
);

// ── 3. KARNATAKA ────────────────────────────────────────────────────────────
const kKarnataka = GeoState(
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
        GeoArea(id: 'KA-BLR-GENERAL', cityId: 'KA-BLR', name: 'General / All Bangalore', lat: 12.9716, lng: 77.5946),
        GeoArea(id: 'KA-BLR-INDIRA', cityId: 'KA-BLR', name: 'Indiranagar', pincode: '560038', lat: 12.9784, lng: 77.6408),
        GeoArea(id: 'KA-BLR-KORA', cityId: 'KA-BLR', name: 'Koramangala', pincode: '560034', lat: 12.9352, lng: 77.6245),
        GeoArea(id: 'KA-BLR-HSR', cityId: 'KA-BLR', name: 'HSR Layout', pincode: '560102', lat: 12.9121, lng: 77.6446),
        GeoArea(id: 'KA-BLR-WHITE', cityId: 'KA-BLR', name: 'Whitefield', pincode: '560066', lat: 12.9698, lng: 77.7500),
        GeoArea(id: 'KA-BLR-JAYA', cityId: 'KA-BLR', name: 'Jayanagar', pincode: '560041', lat: 12.9308, lng: 77.5838),
        GeoArea(id: 'KA-BLR-ELECTRONIC', cityId: 'KA-BLR', name: 'Electronic City', pincode: '560100', lat: 12.8399, lng: 77.6770),
        GeoArea(id: 'KA-BLR-MG', cityId: 'KA-BLR', name: 'MG Road / Brigade Road', pincode: '560001', lat: 12.9756, lng: 77.6066),
      ],
    ),
  ],
);

// ── 4. TELANGANA ────────────────────────────────────────────────────────────
const kTelangana = GeoState(
  id: 'TS',
  name: 'Telangana',
  cities: [
    GeoCity(
      id: 'TS-HYD',
      stateId: 'TS',
      name: 'Hyderabad',
      enabled: true,
      lat: 17.3850,
      lng: 78.4867,
      pincode: '500001',
      areas: [
        GeoArea(id: 'TS-HYD-GENERAL', cityId: 'TS-HYD', name: 'General / All Hyderabad', lat: 17.3850, lng: 78.4867),
        GeoArea(id: 'TS-HYD-GACHI', cityId: 'TS-HYD', name: 'Gachibowli', pincode: '500032', lat: 17.4401, lng: 78.3489),
        GeoArea(id: 'TS-HYD-HITECH', cityId: 'TS-HYD', name: 'HITECH City / Madhapur', pincode: '500081', lat: 17.4435, lng: 78.3772),
        GeoArea(id: 'TS-HYD-BANJARA', cityId: 'TS-HYD', name: 'Banjara Hills', pincode: '500034', lat: 17.4156, lng: 78.4347),
        GeoArea(id: 'TS-HYD-JUBILEE', cityId: 'TS-HYD', name: 'Jubilee Hills', pincode: '500033', lat: 17.4319, lng: 78.4072),
        GeoArea(id: 'TS-HYD-KUKAT', cityId: 'TS-HYD', name: 'Kukatpally', pincode: '500072', lat: 17.4849, lng: 78.4138),
      ],
    ),
  ],
);

// ── 5. TAMIL NADU ───────────────────────────────────────────────────────────
const kTamilNadu = GeoState(
  id: 'TN',
  name: 'Tamil Nadu',
  cities: [
    GeoCity(
      id: 'TN-CHE',
      stateId: 'TN',
      name: 'Chennai',
      enabled: true,
      lat: 13.0827,
      lng: 80.2707,
      pincode: '600001',
      areas: [
        GeoArea(id: 'TN-CHE-GENERAL', cityId: 'TN-CHE', name: 'General / All Chennai', lat: 13.0827, lng: 80.2707),
        GeoArea(id: 'TN-CHE-TNAGAR', cityId: 'TN-CHE', name: 'T. Nagar', pincode: '600017', lat: 13.0418, lng: 80.2341),
        GeoArea(id: 'TN-CHE-ADYAR', cityId: 'TN-CHE', name: 'Adyar', pincode: '600020', lat: 13.0012, lng: 80.2565),
        GeoArea(id: 'TN-CHE-VELACHERY', cityId: 'TN-CHE', name: 'Velachery', pincode: '600042', lat: 12.9815, lng: 80.2180),
        GeoArea(id: 'TN-CHE-ANNA', cityId: 'TN-CHE', name: 'Anna Nagar', pincode: '600040', lat: 13.0850, lng: 80.2101),
      ],
    ),
  ],
);

// ── 6. WEST BENGAL ──────────────────────────────────────────────────────────
const kWestBengal = GeoState(
  id: 'WB',
  name: 'West Bengal',
  cities: [
    GeoCity(
      id: 'WB-KOL',
      stateId: 'WB',
      name: 'Kolkata',
      enabled: true,
      lat: 22.5726,
      lng: 88.3639,
      pincode: '700001',
      areas: [
        GeoArea(id: 'WB-KOL-GENERAL', cityId: 'WB-KOL', name: 'General / All Kolkata', lat: 22.5726, lng: 88.3639),
        GeoArea(id: 'WB-KOL-SALT', cityId: 'WB-KOL', name: 'Salt Lake (Sector V)', pincode: '700091', lat: 22.5800, lng: 88.4300),
        GeoArea(id: 'WB-KOL-PARK', cityId: 'WB-KOL', name: 'Park Street', pincode: '700016', lat: 22.5539, lng: 88.3533),
        GeoArea(id: 'WB-KOL-NEWTOWN', cityId: 'WB-KOL', name: 'New Town', pincode: '700156', lat: 22.5958, lng: 88.4726),
      ],
    ),
  ],
);

// ── 7. RAJASTHAN ────────────────────────────────────────────────────────────
const kRajasthan = GeoState(
  id: 'RJ',
  name: 'Rajasthan',
  cities: [
    GeoCity(
      id: 'RJ-JAI',
      stateId: 'RJ',
      name: 'Jaipur',
      enabled: true,
      lat: 26.9124,
      lng: 75.7873,
      pincode: '302001',
      areas: [
        GeoArea(id: 'RJ-JAI-GENERAL', cityId: 'RJ-JAI', name: 'General / All Jaipur', lat: 26.9124, lng: 75.7873),
        GeoArea(id: 'RJ-JAI-MALVIYA', cityId: 'RJ-JAI', name: 'Malviya Nagar', pincode: '302017', lat: 26.8520, lng: 75.8130),
        GeoArea(id: 'RJ-JAI-VAISHALI', cityId: 'RJ-JAI', name: 'Vaishali Nagar', pincode: '302021', lat: 26.9030, lng: 75.7480),
        GeoArea(id: 'RJ-JAI-CSCHEME', cityId: 'RJ-JAI', name: 'C-Scheme', pincode: '302001', lat: 26.9100, lng: 75.8000),
      ],
    ),
  ],
);

// ── 8. UTTAR PRADESH ────────────────────────────────────────────────────────
const kUttarPradesh = GeoState(
  id: 'UP',
  name: 'Uttar Pradesh',
  cities: [
    GeoCity(
      id: 'UP-LKO',
      stateId: 'UP',
      name: 'Lucknow',
      enabled: true,
      lat: 26.8467,
      lng: 80.9462,
      pincode: '226001',
      areas: [
        GeoArea(id: 'UP-LKO-GENERAL', cityId: 'UP-LKO', name: 'General / All Lucknow', lat: 26.8467, lng: 80.9462),
        GeoArea(id: 'UP-LKO-GOMTI', cityId: 'UP-LKO', name: 'Gomti Nagar', pincode: '226010', lat: 26.8500, lng: 81.0000),
        GeoArea(id: 'UP-LKO-HAZRAT', cityId: 'UP-LKO', name: 'Hazratganj', pincode: '226001', lat: 26.8480, lng: 80.9450),
      ],
    ),
  ],
);

// ── ALL INDIA MASTER STATES LIST ────────────────────────────────────────────
const kAllIndiaStates = [
  kGujarat,
  kMaharashtra,
  kDelhiNCR,
  kKarnataka,
  kTelangana,
  kTamilNadu,
  kWestBengal,
  kRajasthan,
  kUttarPradesh,
];

GeoCity? lookupPanIndiaCity(String cityId) {
  for (final state in kAllIndiaStates) {
    for (final city in state.cities) {
      if (city.id == cityId) return city;
    }
  }
  return null;
}
