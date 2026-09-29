import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_engine.dart';

enum LocationState {
  detecting,
  gpsActive,
  locationOff,
  permissionDenied,
  permissionDeniedForever,
  manualLocation,
  unknownArea,
}

class LocationService extends ChangeNotifier with WidgetsBindingObserver {
  static const _kCityKey = 'selected_city_id';
  static const _kAreaKey = 'selected_area_id';
  static const _kIsManualKey = 'is_manual_location';
  static const _kDefaultCityId = 'GJ-VAD';

  GeoCity _city = LocationEngine.lookupCity(_kDefaultCityId)!;
  GeoArea? _area;
  LocationState _state = LocationState.detecting;
  bool _isManualLocation = false;
  bool _isInitialized = false;

  GeoCity get city => _city;
  GeoArea? get area => _area;
  String get cityId => _city.id;
  String? get areaId => _area?.id;
  LocationState get state => _state;
  bool get isManualLocation => _isManualLocation;
  bool get isDetectingLocation => _state == LocationState.detecting;
  bool get isLocationOff => _state == LocationState.locationOff;
  bool get isPermissionDenied =>
      _state == LocationState.permissionDenied || _state == LocationState.permissionDeniedForever;
  bool get isPermissionDeniedForever => _state == LocationState.permissionDeniedForever;
  bool get isUnknownArea => _state == LocationState.unknownArea;
  double get selectedRadiusKm => 50.0;
  void setSelectedRadius(double radiusKm) {
    notifyListeners();
  }

  String get displayLabel {
    if (_state == LocationState.unknownArea) {
      return 'Unknown Area (>50 km)';
    }
    return _area == null ? _city.name : '${_area!.name}, ${_city.name}';
  }

  String get statusBadgeLabel {
    if (_state == LocationState.detecting) return 'Detecting...';
    if (_state == LocationState.locationOff) return 'Location OFF';
    if (_state == LocationState.permissionDenied || _state == LocationState.permissionDeniedForever) {
      return 'Permission needed';
    }
    if (_isManualLocation) return 'Manual location';
    if (_state == LocationState.unknownArea) return 'Outside 50 km';
    return '';
  }

  LocationService() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When returning from Settings to app, re-check GPS & Auto-detect
    if (state == AppLifecycleState.resumed) {
      if (kDebugMode) {
        debugPrint('[LocationService] App resumed. Re-checking GPS location & permissions...');
      }
      checkLocationAndAutoDetect();
    }
  }

  /// Initial load from disk cache, then immediate FRESH GPS auto-detect
  Future<void> load() async {
    if (_isInitialized) return;
    _isInitialized = true;

    final prefs = await SharedPreferences.getInstance();
    final savedCityId = prefs.getString(_kCityKey) ?? _kDefaultCityId;
    final savedCity = LocationEngine.lookupCity(savedCityId);
    _city = (savedCity != null && savedCity.enabled) ? savedCity : LocationEngine.lookupCity(_kDefaultCityId)!;

    final savedAreaId = prefs.getString(_kAreaKey);
    _area = _city.areas.where((a) => a.id == savedAreaId).firstOrNull;
    _isManualLocation = prefs.getBool(_kIsManualKey) ?? false;

    if (_isManualLocation) {
      _state = LocationState.manualLocation;
      notifyListeners();
    } else {
      await checkLocationAndAutoDetect();
    }
  }

  /// 🛰️ Main GPS & Permission Auto-Detect Logic
  Future<bool> checkLocationAndAutoDetect({double? forceLat, double? forceLng}) async {
    _state = LocationState.detecting;
    notifyListeners();

    try {
      // 1. Check if Device Location Services (GPS) is ON
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) debugPrint('[LocationService] Location services are OFF on device.');
        _state = LocationState.locationOff;
        notifyListeners();
        return false;
      }

      // 2. Check Permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (kDebugMode) debugPrint('[LocationService] Location permission denied.');
        _state = LocationState.permissionDenied;
        notifyListeners();
        return false;
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) debugPrint('[LocationService] Location permission denied forever.');
        _state = LocationState.permissionDeniedForever;
        notifyListeners();
        return false;
      }

      // 3. Fetch FRESH Position (No getLastKnownPosition, NO IP-geolocation)
      Position? position;
      if (forceLat != null && forceLng != null) {
        position = Position(
          latitude: forceLat,
          longitude: forceLng,
          timestamp: DateTime.now(),
          accuracy: 1.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      } else {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException('GPS signal timed out'),
        );
      }

      // 4. Perform Haversine Reverse Geocoding in LocationEngine
      final matchResult = LocationEngine.detectLocation(position.latitude, position.longitude);

      if (matchResult.isUnknownArea) {
        _state = LocationState.unknownArea;
        notifyListeners();
        return false;
      }

      // Fresh GPS ALWAYS overrides saved location!
      _city = matchResult.city;
      if (matchResult.area != null) {
        _area = matchResult.area;
      } else {
        _area = null;
      }
      _isManualLocation = false;
      _state = LocationState.gpsActive;

      // Save to SharedPreferences
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
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationService] GPS auto-detect exception: $e');
      if (_state == LocationState.detecting) {
        _state = _isManualLocation ? LocationState.manualLocation : LocationState.locationOff;
      }
      notifyListeners();
      return false;
    }
  }

  /// Backwards compatibility method name mapping
  Future<bool> ensureLocationPermissionAndAutoDetect({double? lat, double? lng}) async {
    return checkLocationAndAutoDetect(forceLat: lat, forceLng: lng);
  }

  /// Manual City Selection
  Future<void> setCity(GeoCity c) async {
    if (!c.enabled) return;
    _city = c;
    _area = null;
    _isManualLocation = true;
    _state = LocationState.manualLocation;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCityKey, c.id);
    await prefs.remove(_kAreaKey);
    await prefs.setBool(_kIsManualKey, true);
    notifyListeners();
  }

  /// Manual Area Selection
  Future<void> setArea(GeoArea? a) async {
    if (a != null && a.cityId != _city.id) return;
    _area = a;
    _isManualLocation = true;
    _state = LocationState.manualLocation;

    final prefs = await SharedPreferences.getInstance();
    if (a == null) {
      await prefs.remove(_kAreaKey);
    } else {
      await prefs.setString(_kAreaKey, a.id);
    }
    await prefs.setBool(_kIsManualKey, true);
    notifyListeners();
  }

  /// Calculates distance in kilometers between two GPS coordinates using Haversine formula
  static double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // math.PI / 180
    final c = math.cos;
    final a = 0.5 - c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) *
        (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
  }
}
