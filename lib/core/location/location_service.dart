import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_models.dart';
import 'gujarat_data.dart';

class LocationService extends ChangeNotifier {
  static const _kCityKey = 'selected_city_id';
  static const _kAreaKey = 'selected_area_id';
  static const _kDefaultCityId = 'GJ-VAD';

  GeoCity _city = lookupCity(_kDefaultCityId)!;
  GeoArea? _area;

  GeoCity get city => _city;
  GeoArea? get area => _area;
  String get cityId => _city.id;
  String? get areaId => _area?.id;

  String get displayLabel => _area == null ? _city.name : '${_area!.name}, ${_city.name}';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCity = lookupCity(prefs.getString(_kCityKey) ?? _kDefaultCityId);
    
    _city = (savedCity != null && savedCity.enabled) ? savedCity : lookupCity(_kDefaultCityId)!;
    final savedAreaId = prefs.getString(_kAreaKey);
    
    _area = _city.areas.where((a) => a.id == savedAreaId).firstOrNull;
    notifyListeners();
  }

  Future<void> setCity(GeoCity c) async {
    if (!c.enabled) return;
    _city = c;
    _area = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCityKey, c.id);
    await prefs.remove(_kAreaKey);
    notifyListeners();
  }

  Future<void> setArea(GeoArea? a) async {
    if (a != null && a.cityId != _city.id) return;
    _area = a;
    final prefs = await SharedPreferences.getInstance();
    a == null ? await prefs.remove(_kAreaKey) : await prefs.setString(_kAreaKey, a.id);
    notifyListeners();
  }
}
