import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'location_engine.dart';
import 'location_enabler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// v2: Expanded LocationState — 12 states vs old 7
// ─────────────────────────────────────────────────────────────────────────────
enum LocationState {
  // ── Existing (v1) ──────────────────────────────────────────────
  detecting,               // Actively fetching GPS
  gpsActive,               // Fresh GPS fix — best confidence
  locationOff,             // Device GPS toggle is OFF
  permissionDenied,        // User denied once — can re-ask
  permissionDeniedForever, // User denied permanently → Settings
  manualLocation,          // User manually selected city/area
  unknownArea,             // GPS ok but >50 km from any known city

  // ── New in v2 ──────────────────────────────────────────────────
  usingLastKnown,          // GPS timed out; using cached last position
  usingIpFallback,         // GPS off/denied; location via IP geolocation
  lowAccuracy,             // GPS on but accuracy >500 m
  backgroundRefreshing,    // Silently updating in background
  stale,                   // Location context >1 hr old
}

// ─────────────────────────────────────────────────────────────────────────────
// SharedPreferences keys
// ─────────────────────────────────────────────────────────────────────────────
const _kCityKey         = 'selected_city_id';
const _kCityNameKey     = 'selected_city_name';
const _kAreaKey         = 'selected_area_id';
const _kAreaNameKey     = 'selected_area_name';
const _kIsManualKey     = 'is_manual_location';
const _kLastLatKey      = 'last_known_lat';
const _kLastLngKey      = 'last_known_lng';
const _kLastFetchedKey  = 'last_location_fetched_at';
const _kDefaultCityId   = 'GJ-VAD';

// ─────────────────────────────────────────────────────────────────────────────
// LocationService v2  —  Rapido / Uber style location requirement
// ─────────────────────────────────────────────────────────────────────────────
class LocationService extends ChangeNotifier {
  // ── Internal state ──────────────────────────────────────────────────────────
  GeoCity _city     = LocationEngine.lookupCity(_kDefaultCityId)!;
  GeoArea? _area    = LocationEngine.lookupArea('GJ-VAD-WAGHODIA') ?? LocationEngine.lookupCity(_kDefaultCityId)!.areas.firstOrNull;
  LocationState _state        = LocationState.detecting;
  LocationSource _source      = LocationSource.defaultCity;
  double _confidenceScore     = 0.1;
  DateTime? _fetchedAt;
  double? _rawLat;
  double? _rawLng;
  bool _isManualLocation      = false;
  bool _isInitialized         = false;
  double _selectedRadiusKm    = 50.0;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;

  // ── Public getters (v1 compatible) ─────────────────────────────────────────
  GeoCity           get city                  => _city;
  GeoArea?          get area                  => _area;
  String            get cityId                => _city.id;
  String?           get areaId               => _area?.id;
  LocationState     get state                 => _state;
  bool              get isManualLocation      => _isManualLocation;
  bool              get isDetectingLocation   => _state == LocationState.detecting;
  bool              get isLocationOff         => _state == LocationState.locationOff;
  bool              get isPermissionDenied    =>
      _state == LocationState.permissionDenied ||
      _state == LocationState.permissionDeniedForever;
  bool              get isPermissionDeniedForever =>
      _state == LocationState.permissionDeniedForever;
  bool              get isUnknownArea         => _state == LocationState.unknownArea;
  double            get selectedRadiusKm      => _selectedRadiusKm;
  bool              get isVadodara            => _city.id == 'GJ-VAD' && _state != LocationState.unknownArea;
  bool              get isLocationBlocked     => isLocationOff || isPermissionDenied;

  // ── v2 getters ──────────────────────────────────────────────────────────────
  LocationSource    get source                => _source;
  double            get confidenceScore       => _confidenceScore;
  DateTime?         get fetchedAt             => _fetchedAt;
  double?           get rawLat                => _rawLat;
  double?           get rawLng                => _rawLng;
  bool              get isStale               =>
      _fetchedAt != null &&
      DateTime.now().difference(_fetchedAt!) > const Duration(hours: 1);
  bool              get isUsingFallback       =>
      _source == LocationSource.lastKnown ||
      _source == LocationSource.ipFallback;

  /// Convenience: build a LocationContext snapshot
  LocationContext get locationContext => LocationContext(
    city: _city,
    area: _area,
    rawLat: _rawLat,
    rawLng: _rawLng,
    source: _source,
    confidenceScore: _confidenceScore,
    fetchedAt: _fetchedAt ?? DateTime.now(),
    distanceKm: 0,
  );

  // ── Display helpers (v1 compatible + v2 additions) ──────────────────────────
  String get displayLabel {
    if (_state == LocationState.unknownArea) return 'Unknown Area (>50 km)';
    return _area == null ? _city.name : '${_area!.name}, ${_city.name}';
  }

  String get statusBadgeLabel {
    switch (_state) {
      case LocationState.detecting:
        return 'Detecting...';
      case LocationState.locationOff:
        return 'Location OFF';
      case LocationState.permissionDenied:
      case LocationState.permissionDeniedForever:
        return 'Permission needed';
      case LocationState.usingLastKnown:
        return '~Last Known';
      case LocationState.usingIpFallback:
        return '~Approx (IP)';
      case LocationState.lowAccuracy:
        return 'Low accuracy';
      case LocationState.backgroundRefreshing:
        return 'Updating...';
      case LocationState.stale:
        return 'Location outdated';
      case LocationState.unknownArea:
        return 'Outside 50 km';
      case LocationState.manualLocation:
        return 'Manual location';
      case LocationState.gpsActive:
        return '';
    }
  }

  /// Banner message shown in the smart location banner widget.
  /// Returns null when no banner should appear.
  String? get bannerMessage {
    switch (_state) {
      case LocationState.locationOff:
        return 'GPS is off. Enable for accurate local posts.';
      case LocationState.permissionDenied:
        return 'Allow location permission to see local posts.';
      case LocationState.permissionDeniedForever:
        return 'Enable location in App Settings to auto-detect.';
      case LocationState.usingIpFallback:
        return 'Using approximate location (GPS unavailable).';
      case LocationState.stale:
        return 'Location not updated in 1+ hour. Tap to refresh.';
      case LocationState.unknownArea:
        return 'You appear to be outside our service area.';
      default:
        return null;
    }
  }

  Color get chipIconColor {
    if (_state == LocationState.locationOff ||
        _state == LocationState.permissionDenied ||
        _state == LocationState.permissionDeniedForever) {
      return Colors.amber.shade700;
    }
    if (isUsingFallback || _state == LocationState.stale) {
      return Colors.orange.shade700;
    }
    return const Color(0xFF0B8A3E);
  }

  void setSelectedRadius(double radiusKm) {
    _selectedRadiusKm = radiusKm;
    notifyListeners();
  }

  // ── Lifecycle & Hardware Toggle Listener ────────────────────────────────────
  LocationService() {
    _initServiceStatusListener();
  }

  void _initServiceStatusListener() {
    try {
      _serviceStatusSub =
          Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
        if (status == ServiceStatus.disabled) {
          if (kDebugMode) {
            debugPrint('[LocationService] GPS toggle turned OFF by user');
          }
        } else if (status == ServiceStatus.enabled) {
          if (kDebugMode) {
            debugPrint('[LocationService] GPS toggle turned ON by user');
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocationService] Service status stream error: $e');
      }
    }
  }

  @override
  void dispose() {
    _serviceStatusSub?.cancel();
    super.dispose();
  }

  // ── Initial Load ────────────────────────────────────────────────────────────
  /// Called once at app startup from SplashController
  Future<void> load() async {
    if (_isInitialized) return;
    _isInitialized = true;

    final prefs = await SharedPreferences.getInstance();

    final savedCityId   = prefs.getString(_kCityKey) ?? _kDefaultCityId;
    final savedCityName = prefs.getString(_kCityNameKey);
    final savedCity     = LocationEngine.lookupCity(savedCityId);

    _rawLat     = prefs.getDouble(_kLastLatKey);
    _rawLng     = prefs.getDouble(_kLastLngKey);
    final fetchedMs = prefs.getInt(_kLastFetchedKey);
    _fetchedAt  = fetchedMs != null
        ? DateTime.fromMillisecondsSinceEpoch(fetchedMs)
        : null;

    if (savedCity != null) {
      _city = savedCity;
    } else if (savedCityName != null && savedCityName.isNotEmpty) {
      _city = GeoCity(
        id: savedCityId,
        stateId: 'IN',
        name: savedCityName,
        enabled: true,
        areas: const [],
      );
    } else {
      _city = LocationEngine.lookupCity(_kDefaultCityId)!;
    }

    final savedAreaId   = prefs.getString(_kAreaKey);
    final savedAreaName = prefs.getString(_kAreaNameKey) ?? prefs.getString('home_area_name');
    final matchedArea   = _city.areas.where((a) => a.id == savedAreaId).firstOrNull ??
        (savedAreaId != null ? LocationEngine.lookupArea(savedAreaId) : null);

    if (matchedArea != null) {
      _area = (savedAreaName != null && savedAreaName.isNotEmpty && matchedArea.name != savedAreaName)
          ? GeoArea(
              id: matchedArea.id,
              cityId: _city.id,
              name: savedAreaName,
              lat: matchedArea.lat,
              lng: matchedArea.lng,
              pincode: matchedArea.pincode,
            )
          : matchedArea;
    } else if (savedAreaName != null && savedAreaName.isNotEmpty) {
      _area = GeoArea(
        id: (savedAreaId != null && savedAreaId.isNotEmpty) ? savedAreaId : _city.id,
        cityId: _city.id,
        name: savedAreaName,
        lat: _rawLat,
        lng: _rawLng,
      );
    } else {
      _area = _city.areas.firstOrNull;
    }

    _isManualLocation = prefs.getBool(_kIsManualKey) ?? true;
    _state = LocationState.manualLocation;
    _source = _isManualLocation ? LocationSource.manual : LocationSource.defaultCity;
    _confidenceScore = 0.9;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 🛰️ CORE: 5-step smart fallback chain
  // ─────────────────────────────────────────────────────────────────────────────
  Future<bool> checkLocationAndAutoDetect({
    double? forceLat,
    double? forceLng,
  }) async {
    _state = LocationState.detecting;
    notifyListeners();

    // ── Step 1: Fresh GPS ─────────────────────────────────────────────────────
    if (forceLat != null && forceLng != null) {
      return _resolveFromCoords(
        forceLat, forceLng, LocationSource.gps, 1.0,
      );
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) debugPrint('[LocationService] Device GPS is OFF');
        _state = LocationState.locationOff;
        notifyListeners();
        return false; // STRICT: Do not bypass when GPS is OFF
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        _state = LocationState.permissionDeniedForever;
        notifyListeners();
        return false; // STRICT: Must grant permission
      }

      if (permission == LocationPermission.denied) {
        _state = LocationState.permissionDenied;
        notifyListeners();
        return false; // STRICT: Must grant permission
      }

      // Permission granted AND GPS is ON — try fresh GPS
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        ).timeout(const Duration(seconds: 12));

        // Save as last known
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_kLastLatKey, position.latitude);
        await prefs.setDouble(_kLastLngKey, position.longitude);
        await prefs.setInt(
          _kLastFetchedKey,
          DateTime.now().millisecondsSinceEpoch,
        );

        return await _resolveFromCoords(
          position.latitude,
          position.longitude,
          LocationSource.gps,
          1.0,
        );
      } on TimeoutException {
        if (kDebugMode) debugPrint('[LocationService] GPS timed out — checking fallback');
      } catch (e) {
        if (kDebugMode) debugPrint('[LocationService] GPS error: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationService] GPS service check error: $e');
      _state = LocationState.locationOff;
      notifyListeners();
      return false;
    }

    // ── Step 2: Last Known GPS Position (Only when GPS is ON but indoor fix slow) ──
    if (_rawLat != null && _rawLng != null) {
      final age = _fetchedAt != null
          ? DateTime.now().difference(_fetchedAt!)
          : const Duration(days: 999);

      if (age < const Duration(minutes: 30)) {
        if (kDebugMode) {
          debugPrint('[LocationService] Using last-known GPS (${age.inMinutes} min old)');
        }
        final ok = await _resolveFromCoords(
          _rawLat!, _rawLng!, LocationSource.lastKnown, 0.75,
        );
        if (ok) {
          _state = LocationState.usingLastKnown;
          notifyListeners();
          return true;
        }
      }
    }

    // ── Step 3: IP Geolocation Fallback (Only when GPS is ON but satellites weak) ──
    if (kDebugMode) debugPrint('[LocationService] Trying IP geolocation fallback...');
    final ipResult = await _tryIpGeolocation();
    if (ipResult) return true;

    // Could not determine location despite GPS being active
    _state = LocationState.unknownArea;
    notifyListeners();
    return false;
  }

  /// Rapido-style Google Play Services Location Resolution Prompt.
  /// Prompts in-app system dialog: "To continue, your device will need to use Location Accuracy"
  /// Returns true and auto-detects if user taps [Turn on].
  Future<bool> promptAndEnableGps() async {
    final turnedOn = await LocationEnabler.requestEnableLocation();
    if (turnedOn) {
      return await checkLocationAndAutoDetect();
    } else {
      _state = LocationState.locationOff;
      notifyListeners();
      return false;
    }
  }

  // ── Backwards compatibility alias ───────────────────────────────────────────
  Future<bool> ensureLocationPermissionAndAutoDetect({
    double? lat,
    double? lng,
  }) => checkLocationAndAutoDetect(forceLat: lat, forceLng: lng);

  // ─────────────────────────────────────────────────────────────────────────────
  // Resolve city/area from lat/lng coords using Haversine engine
  // ─────────────────────────────────────────────────────────────────────────────
  Future<bool> _resolveFromCoords(
    double lat, double lng,
    LocationSource src, double confidence,
  ) async {
    final match = LocationEngine.detectLocation(lat, lng);
    if (match.isUnknownArea) {
      _rawLat = lat;
      _rawLng = lng;
      _state  = LocationState.unknownArea;
      notifyListeners();
      return false;
    }

    _city            = match.city;
    _area            = match.area;
    _rawLat          = lat;
    _rawLng          = lng;
    _isManualLocation = false;
    _source          = src;
    _confidenceScore = confidence;
    _fetchedAt       = DateTime.now();
    _state           = LocationState.gpsActive;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCityKey, _city.id);
    if (_area != null) {
      await prefs.setString(_kAreaKey, _area!.id);
    } else {
      await prefs.remove(_kAreaKey);
    }
    await prefs.setBool(_kIsManualKey, false);
    await prefs.setInt(_kLastFetchedKey, _fetchedAt!.millisecondsSinceEpoch);

    notifyListeners();
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Step 3: IP Geolocation via ip-api.com (free, no key required)
  // ─────────────────────────────────────────────────────────────────────────────
  Future<bool> _tryIpGeolocation() async {
    try {
      final response = await http
          .get(Uri.parse('http://ip-api.com/json?fields=lat,lon,status,city'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final lat = (data['lat'] as num).toDouble();
          final lon = (data['lon'] as num).toDouble();

          if (kDebugMode) {
            debugPrint('[LocationService v2] IP geolocation: lat=$lat, lon=$lon city=${data['city']}');
          }

          final match = LocationEngine.detectLocation(lat, lon);
          if (!match.isUnknownArea) {
            _city            = match.city;
            _area            = match.area;
            _rawLat          = lat;
            _rawLng          = lon;
            _source          = LocationSource.ipFallback;
            _confidenceScore = 0.5;
            _fetchedAt       = DateTime.now();
            _isManualLocation = false;
            _state           = LocationState.usingIpFallback;

            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kCityKey, _city.id);
            if (_area != null) {
              await prefs.setString(_kAreaKey, _area!.id);
            } else {
              await prefs.remove(_kAreaKey);
            }
            await prefs.setBool(_kIsManualKey, false);

            notifyListeners();
            return true;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationService v2] IP geolocation failed: $e');
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Manual Selection
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> setCity(GeoCity c) async {
    _city            = c;
    _area            = null;
    _isManualLocation = true;
    _source          = LocationSource.manual;
    _confidenceScore = 0.9;
    _fetchedAt       = DateTime.now();
    _state           = LocationState.manualLocation;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCityKey, c.id);
    await prefs.setString(_kCityNameKey, c.name);
    await prefs.remove(_kAreaKey);
    await prefs.remove(_kAreaNameKey);
    await prefs.setBool(_kIsManualKey, true);
    notifyListeners();
  }

  Future<void> setArea(GeoArea? a) async {
    _area            = a;
    _isManualLocation = true;
    _source          = LocationSource.manual;
    _confidenceScore = 0.9;
    _fetchedAt       = DateTime.now();
    _state           = LocationState.manualLocation;

    final prefs = await SharedPreferences.getInstance();
    if (a == null) {
      await prefs.remove(_kAreaKey);
      await prefs.remove(_kAreaNameKey);
    } else {
      await prefs.setString(_kAreaKey, a.id);
      await prefs.setString(_kAreaNameKey, a.name);
      await prefs.setString('home_area_name', a.name);
      if (a.lat != null) await prefs.setDouble(_kLastLatKey, a.lat!);
      if (a.lng != null) await prefs.setDouble(_kLastLngKey, a.lng!);
    }
    await prefs.setBool(_kIsManualKey, true);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Static Haversine utility (unchanged)
  // ─────────────────────────────────────────────────────────────────────────────
  static double calculateDistanceKm(
    double lat1, double lon1, double lat2, double lon2,
  ) {
    const p = 0.017453292519943295;
    final c = math.cos;
    final a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a));
  }
}
