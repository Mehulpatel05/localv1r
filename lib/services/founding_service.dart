import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/api_constants.dart';
import '../models/founding_model.dart';
import '../core/services/badge_cache_service.dart';
import 'auth_service.dart';

class FoundingService extends ChangeNotifier {
  static final FoundingService _instance = FoundingService._internal();
  factory FoundingService() => _instance;
  static FoundingService get instance => _instance;

  static const String _kFoundingCountsCacheKey = 'founding_approved_counts_cache_v1';

  FoundingService._internal() {
    _loadCachedCounts();
  }

  Map<String, int> _approvedCounts = {};
  FoundingMyStatus? _myStatus;
  bool _isLoading = false;
  bool _hasLoadedCounts = false;

  Map<String, int> get approvedCounts => Map.unmodifiable(_approvedCounts);
  FoundingMyStatus? get myStatus => _myStatus;
  bool get isLoading => _isLoading;
  bool get hasLoadedCounts => _hasLoadedCounts;

  Future<void> _loadCachedCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kFoundingCountsCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final parsed = <String, int>{};
        decoded.forEach((k, v) {
          parsed[k] = (v as num?)?.toInt() ?? 0;
        });
        if (parsed.isNotEmpty) {
          _approvedCounts = parsed;
          _hasLoadedCounts = true;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  int getApprovedCount(String areaId) {
    return _approvedCounts[areaId] ?? 0;
  }

  int getSpotsLeft(String areaId) {
    final count = getApprovedCount(areaId);
    return (100 - count).clamp(0, 100);
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService.instance.getAccessToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, String>> _getAdminHeaders() async {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-admin-key': 'nearhood_admin_vadodara_2026',
      'Authorization': 'Bearer nearhood_admin_vadodara_2026',
    };
  }

  Future<Map<String, int>> fetchCounts() async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/founding/counts');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['counts'] is Map) {
          final Map<String, dynamic> raw = decoded['counts'];
          final parsed = <String, int>{};
          raw.forEach((k, v) {
            parsed[k] = (v as num?)?.toInt() ?? 0;
          });
          _approvedCounts = parsed;
          _hasLoadedCounts = true;
          notifyListeners();
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kFoundingCountsCacheKey, jsonEncode(parsed));
          } catch (_) {}
          return _approvedCounts;
        }
      }
    } catch (e) {
      debugPrint('[FoundingService] fetchCounts error: $e');
    }
    return _approvedCounts;
  }

  Future<FoundingMyStatus?> fetchMyStatus({String? cityId, String? areaId}) async {
    try {
      _isLoading = true;
      final params = <String>[];
      if (cityId != null && cityId.isNotEmpty) params.add('city_id=$cityId');
      if (areaId != null && areaId.isNotEmpty) params.add('area_id=$areaId');
      final q = params.isNotEmpty ? '?${params.join('&')}' : '';
      final uri = Uri.parse('${ApiConstants.baseUrl}/founding/me$q');
      final headers = await _getAuthHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          _myStatus = FoundingMyStatus.fromJson(decoded);
          final myHandle = await AuthService.instance.getUserHandle();
          if (myHandle != null && myHandle.isNotEmpty) {
            final clean = myHandle.replaceAll('@', '').trim();
            if (_myStatus?.state == FoundingUserState.approved) {
              BadgeCacheService.instance.setBadge(
                clean,
                isVerified: true,
                badgeText: 'FOUNDING #${_myStatus!.seq ?? 1}',
                founderSeq: _myStatus!.seq,
              );
            } else {
              BadgeCacheService.instance.removeBadge(clean);
            }
          }
          notifyListeners();
          return _myStatus;
        }
      }
    } catch (e) {
      debugPrint('[FoundingService] fetchMyStatus error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return _myStatus;
  }

  Future<Map<String, dynamic>> submitRequest({required String cityId, String? areaId}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/founding/request');
      final headers = await _getAuthHeaders();
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({'city_id': cityId, if (areaId != null && areaId.isNotEmpty) 'area_id': areaId}),
      ).timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200 && decoded['success'] == true) {
        await fetchMyStatus(cityId: cityId, areaId: areaId);
        return {'success': true, 'message': decoded['message'] ?? 'Request submitted successfully!'};
      }
      return {'success': false, 'message': decoded['error'] ?? 'Could not submit request.'};
    } catch (e) {
      return {'success': false, 'message': 'Network error submitting request: $e'};
    }
  }

  Future<List<AdminFoundingCity>> fetchAdminCities() async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/founding/cities');
      final headers = await _getAdminHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['cities'] is List) {
          return (decoded['cities'] as List)
              .whereType<Map<String, dynamic>>()
              .map((m) => AdminFoundingCity.fromJson(m))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[FoundingService] fetchAdminCities error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> addCity(String cityName, {String stateId = 'GJ'}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/founding/cities');
      final headers = await _getAdminHeaders();
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({'name': cityName, 'stateId': stateId}),
      ).timeout(const Duration(seconds: 12));

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200 && decoded['success'] == true) {
        return {
          'success': true,
          'message': decoded['message'] ?? 'City and localities added successfully',
          'city': decoded['city'],
          'areasCount': decoded['areasCount'],
        };
      }
      return {
        'success': false,
        'message': decoded['error'] ?? 'Could not add city.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error adding city: $e'};
    }
  }

  Future<List<AdminFoundingArea>> fetchAdminAreas(String cityId) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/founding/cities/$cityId/areas');
      final headers = await _getAdminHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['areas'] is List) {
          return (decoded['areas'] as List)
              .whereType<Map<String, dynamic>>()
              .map((m) => AdminFoundingArea.fromJson(m))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[FoundingService] fetchAdminAreas error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> fetchAdminRequests(String areaId, {String status = 'pending'}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/founding/areas/$areaId/requests?status=$status');
      final headers = await _getAdminHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          final list = (decoded['requests'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map((m) => AdminFoundingRequestItem.fromJson(m))
                  .toList() ??
              [];
          return {
            'success': true,
            'areaName': decoded['areaName'] ?? areaId,
            'approvedCount': (decoded['approvedCount'] as num?)?.toInt() ?? 0,
            'spotsLeft': (decoded['spotsLeft'] as num?)?.toInt() ?? 100,
            'requests': list,
          };
        }
      }
    } catch (e) {
      debugPrint('[FoundingService] fetchAdminRequests error: $e');
    }
    return {'success': false, 'requests': <AdminFoundingRequestItem>[], 'approvedCount': 0, 'spotsLeft': 100};
  }

  Future<List<AdminFounderItem>> fetchAdminFounders(String areaId) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/founding/areas/$areaId/founders');
      final headers = await _getAdminHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['founders'] is List) {
          return (decoded['founders'] as List)
              .whereType<Map<String, dynamic>>()
              .map((m) => AdminFounderItem.fromJson(m))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[FoundingService] fetchAdminFounders error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> approveRequest(String requestId) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/founding/requests/$requestId/approve');
      final headers = await _getAdminHeaders();
      final response = await http.post(uri, headers: headers).timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200 && decoded['success'] == true) {
        await fetchCounts();
        return {'success': true, 'message': decoded['message'] ?? 'Approved successfully'};
      }
      return {'success': false, 'message': decoded['error'] ?? 'Could not approve request.'};
    } catch (e) {
      return {'success': false, 'message': 'Network error approving request: $e'};
    }
  }

  Future<Map<String, dynamic>> rejectRequest(String requestId, String reason) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/founding/requests/$requestId/reject');
      final headers = await _getAdminHeaders();
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({'reason': reason}),
      ).timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200 && decoded['success'] == true) {
        return {'success': true, 'message': decoded['message'] ?? 'Rejected successfully'};
      }
      return {'success': false, 'message': decoded['error'] ?? 'Could not reject request.'};
    } catch (e) {
      return {'success': false, 'message': 'Network error rejecting request: $e'};
    }
  }

  Future<Map<String, dynamic>> removeFounder(String userId, String areaId) async {
    try {
      final clean = userId.replaceFirst(RegExp(r'^@+'), '').trim().toLowerCase();
      BadgeCacheService.instance.removeBadge(clean);
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/founding/founders/$clean/remove');
      final headers = await _getAdminHeaders();
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({'area_id': areaId, 'all_areas': true}),
      ).timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200 && decoded['success'] == true) {
        BadgeCacheService.instance.removeBadge(clean);
        await fetchCounts();
        return {'success': true, 'message': decoded['message'] ?? 'Badge removed successfully'};
      }
      return {'success': false, 'message': decoded['error'] ?? 'Could not remove badge.'};
    } catch (e) {
      return {'success': false, 'message': 'Network error removing founder: $e'};
    }
  }
}
