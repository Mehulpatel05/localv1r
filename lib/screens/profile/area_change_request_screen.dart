import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/post_repository.dart';
import '../../services/auth_service.dart';

class ParsedAreaResult {
  final String area;
  final String subtitle;
  final String city;
  final String? placeId;

  const ParsedAreaResult({
    required this.area,
    required this.subtitle,
    required this.city,
    this.placeId,
  });

  static ParsedAreaResult parse(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? item['placeId']?.toString() ?? item['place_id']?.toString();
    final rawMain = (item['mainText'] ?? item['main_text'] ?? item['name'] ?? item['description'] ?? '').toString().trim();
    final rawSec = (item['secondaryText'] ?? item['secondary_text'] ?? '').toString().trim();
    final rawDesc = (item['description'] ?? '').toString().trim();

    final cleanSubtitle = _cleanAddressString(rawSec.isNotEmpty ? rawSec : rawDesc);
    final detectedCity = _extractCity(rawSec.isNotEmpty ? rawSec : rawDesc, fallback: rawMain);

    return ParsedAreaResult(
      area: rawMain,
      subtitle: cleanSubtitle.isNotEmpty ? cleanSubtitle : rawSec,
      city: detectedCity,
      placeId: id,
    );
  }

  static String _cleanAddressString(String raw) {
    if (raw.isEmpty) return '';
    final parts = raw.split(',');
    final cleaned = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(r'^\d{4,8}$').hasMatch(trimmed)) continue;
      cleaned.add(trimmed);
    }
    return cleaned.join(', ');
  }

  static String _extractCity(String rawSecondary, {required String fallback}) {
    if (rawSecondary.isEmpty) return fallback;

    const ignoredTokens = {
      'india',
      'bharat',
      'gujarat',
      'rajasthan',
      'maharashtra',
      'madhya pradesh',
      'delhi',
      'karnataka',
      'tamil nadu',
      'uttar pradesh',
      'haryana',
      'punjab',
      'kerala',
      'telangana',
      'andhra pradesh',
      'bihar',
      'west bengal',
      'odisha',
      'assam',
      'jharkhand',
      'chhattisgarh',
      'uttarakhand',
      'himachal pradesh',
      'goa',
    };

    final parts = rawSecondary.split(',');
    final candidateCities = <String>[];

    for (final p in parts) {
      final clean = p.trim();
      if (clean.isEmpty) continue;
      final lower = clean.toLowerCase();
      if (RegExp(r'^\d{4,8}$').hasMatch(lower)) continue;
      if (ignoredTokens.contains(lower)) continue;
      candidateCities.add(clean);
    }

    if (candidateCities.isNotEmpty) {
      return candidateCities.last;
    }

    return fallback;
  }
}

class AreaChangeRequestScreen extends StatefulWidget {
  final PostRepository repository;

  const AreaChangeRequestScreen({
    super.key,
    required this.repository,
  });

  @override
  State<AreaChangeRequestScreen> createState() => _AreaChangeRequestScreenState();
}

class _AreaChangeRequestScreenState extends State<AreaChangeRequestScreen> {
  static const Color _primaryGreen = Color(0xFF1F6B4A);
  static const Color _lightGreenTint = Color(0xFFE8F5E9);

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _hasPendingRequest = false;
  Map<String, dynamic>? _pendingRequest;

  String _currentAreaName = '';
  String _currentCityName = '';
  String _currentAreaId = '';
  String _currentCityId = 'GJ-VAD';

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _areaNameController = TextEditingController();
  final TextEditingController _cityNameController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _debounceTimer;
  List<Map<String, dynamic>> _predictions = [];
  bool _isSearching = false;

  Map<String, dynamic>? _selectedArea;

  static const List<Map<String, String>> _popularVadodaraAreas = [
    {'id': 'GJ-VAD-ALKAPURI', 'name': 'Alkapuri', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-SAYAJIGUNJ', 'name': 'Sayajigunj', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-GOTRI', 'name': 'Gotri', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-MANJALPUR', 'name': 'Manjalpur', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-KARELIBAUG', 'name': 'Karelibaug', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-FATEHGUNJ', 'name': 'Fatehgunj', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-AKOTA', 'name': 'Akota', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-VASNA', 'name': 'Vasna Road', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-MAKARPURA', 'name': 'Makarpura', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-SUBHANPURA', 'name': 'Subhanpura', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-WAGHODIA', 'name': 'Waghodia Road', 'city_id': 'Vadodara'},
    {'id': 'GJ-VAD-NIZAMPURA', 'name': 'Nizampura', 'city_id': 'Vadodara'},
  ];

  @override
  void initState() {
    super.initState();
    _currentAreaName = widget.repository.locationService.area?.name ?? '';
    _currentCityName = widget.repository.locationService.city.name;
    _currentAreaId = widget.repository.locationService.area?.id ?? '';
    _currentCityId = widget.repository.locationService.city.id;

    _fetchStatus();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _areaNameController.dispose();
    _cityNameController.dispose();
    _reasonController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    setState(() => _isLoading = true);
    try {
      final res = await AuthService.instance.getAreaChangeRequestStatus();
      if (mounted) {
        setState(() {
          _hasPendingRequest = res['hasPending'] == true;
          _pendingRequest = res['request'] as Map<String, dynamic>?;
          if (res['currentArea'] is Map<String, dynamic>) {
            final ca = res['currentArea'] as Map<String, dynamic>;
            if ((ca['areaName'] as String?)?.isNotEmpty == true) {
              _currentAreaName = ca['areaName'];
            }
            if ((ca['areaId'] as String?)?.isNotEmpty == true) {
              _currentAreaId = ca['areaId'];
            }
            if ((ca['cityId'] as String?)?.isNotEmpty == true) {
              _currentCityId = ca['cityId'];
            }
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _predictions.clear();
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await AuthService.instance.searchPlacesAutocomplete(trimmed);
        if (mounted && _searchController.text.trim() == trimmed) {
          setState(() {
            _predictions = results;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  void _selectParsedArea(ParsedAreaResult parsed) {
    setState(() {
      _selectedArea = {
        'id': parsed.placeId ?? parsed.area,
        'area': parsed.area,
        'city': parsed.city,
        'name': parsed.area,
        'description': parsed.subtitle.isNotEmpty ? '${parsed.area}, ${parsed.subtitle}' : parsed.area,
      };
      _areaNameController.text = parsed.area;
      _cityNameController.text = parsed.city;
      _searchController.text = parsed.subtitle.isNotEmpty ? '${parsed.area}, ${parsed.subtitle}' : parsed.area;
      _predictions.clear();
      _searchFocusNode.unfocus();
    });
  }

  void _selectPopularArea(Map<String, String> area) {
    final areaName = area['name'] ?? '';
    final cityName = area['city_id'] == 'GJ-VAD' ? 'Vadodara' : (area['city_id'] ?? 'Vadodara');
    setState(() {
      _selectedArea = {
        'id': area['id'] ?? areaName,
        'area': areaName,
        'city': cityName,
        'name': areaName,
        'description': '$areaName, $cityName',
      };
      _areaNameController.text = areaName;
      _cityNameController.text = cityName;
      _searchController.text = '$areaName, $cityName';
      _predictions.clear();
      _searchFocusNode.unfocus();
    });
  }

  Future<void> _handleSendRequest() async {
    final areaName = _areaNameController.text.trim().isNotEmpty
        ? _areaNameController.text.trim()
        : (_selectedArea?['area'] ?? _selectedArea?['name'] ?? '').toString().trim();
    final cityName = _cityNameController.text.trim().isNotEmpty
        ? _cityNameController.text.trim()
        : (_selectedArea?['city'] ?? _currentCityName).toString().trim();

    if (areaName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or enter an area name.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final targetAreaId = (_selectedArea?['id'] ?? areaName).toString();
    if ((_currentAreaId.isNotEmpty && targetAreaId.toLowerCase() == _currentAreaId.toLowerCase()) ||
        (areaName.toLowerCase() == _currentAreaName.toLowerCase() &&
            cityName.toLowerCase() == _currentCityName.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already registered in this area.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final res = await AuthService.instance.submitAreaChangeRequest(
        requestedAreaId: areaName,
        requestedAreaName: areaName,
        requestedCityId: cityName.isNotEmpty ? cityName : _currentCityId,
        reason: _reasonController.text.trim(),
      );

      if (!mounted) return;

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request sent to admin for approval!'),
            backgroundColor: _primaryGreen,
          ),
        );
        setState(() {
          _hasPendingRequest = true;
          _pendingRequest = res['request'] as Map<String, dynamic>? ?? {
            'requested_area_name': areaName,
            'requested_city_id': cityName,
            'current_area_name': _currentAreaName,
            'created_at': DateTime.now().toIso8601String(),
            'reason': _reasonController.text.trim(),
            'status': 'pending',
          };
          _selectedArea = null;
          _areaNameController.clear();
          _cityNameController.clear();
          _reasonController.clear();
          _searchController.clear();
          _isSubmitting = false;
        });
      } else {
        setState(() => _isSubmitting = false);
        final err = res['error'] as String? ?? 'Failed to submit request.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleCancelRequest() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel Area Change Request?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: const Text(
          'Are you sure you want to cancel your pending area change request?',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Request', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSubmitting = true);
    try {
      final reqId = _pendingRequest?['id'] as String?;
      final res = await AuthService.instance.cancelAreaChangeRequest(requestId: reqId);
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request cancelled successfully.'),
            backgroundColor: AppColors.textPrimary,
          ),
        );
        setState(() {
          _hasPendingRequest = false;
          _pendingRequest = null;
          _isSubmitting = false;
        });
      } else {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['error'] as String? ?? 'Could not cancel request.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Change Area',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _primaryGreen),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCurrentAreaCard(),
                  const SizedBox(height: 20),
                  if (_hasPendingRequest)
                    _buildPendingRequestCard()
                  else
                    _buildRequestAreaSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentAreaCard() {
    final areaDisplay = _currentAreaName.isNotEmpty ? _currentAreaName : 'Vadodara';
    final cityDisplay = _currentCityName.isNotEmpty ? _currentCityName : 'Vadodara';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: _lightGreenTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: _primaryGreen,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'CURRENT AREA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: _lightGreenTint,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Verified',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  areaDisplay,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  cityDisplay,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRequestCard() {
    final requestedArea = _pendingRequest?['requested_area_name'] ?? 'Selected Area';
    final requestedCity = (_pendingRequest?['requested_city_id'] ?? '').toString();
    final rawDate = _pendingRequest?['created_at']?.toString();
    final dateDisplay = rawDate != null
        ? DateTime.tryParse(rawDate)?.toLocal().toString().split('.').first ?? ''
        : '';
    final reason = _pendingRequest?['reason']?.toString();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request Pending Admin Approval',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    Text(
                      'Your request is under review',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFEEBC8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Requested Area',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          requestedArea,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (requestedCity.isNotEmpty)
                          Text(
                            requestedCity,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (dateDisplay.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Submitted',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      Text(
                        dateDisplay,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
                if (reason != null && reason.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Reason',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          reason,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Once the admin approves your request, your neighborhood feed and chats will automatically shift to your new area.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Color(0xFF78350F),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _isSubmitting ? null : _handleCancelRequest,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFFCA5A5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.close_rounded, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Cancel Request',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestAreaSection() {
    final hasValidArea = _areaNameController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Select New Area',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose the neighborhood you have moved to. An admin will review and verify the request.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textMuted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search area name (e.g. Vavol, Alkapuri)',
            hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 22),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF64748B)),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _predictions.clear();
                      });
                    },
                  )
                : (_isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _primaryGreen),
                        ),
                      )
                    : null),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryGreen, width: 1.5),
            ),
          ),
        ),
        if (_predictions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0C000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _predictions.length > 5 ? 5 : _predictions.length,
              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final item = _predictions[index];
                final parsed = ParsedAreaResult.parse(item);
                return InkWell(
                  onTap: () => _selectParsedArea(parsed),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          height: 38,
                          width: 38,
                          decoration: BoxDecoration(
                            color: _lightGreenTint,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: _primaryGreen,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                parsed.area,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (parsed.subtitle.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  parsed.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 13,
                          color: Color(0xFF94A3B8),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (_selectedArea != null || _areaNameController.text.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF86EFAC), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: _primaryGreen, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Selected Area Details',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _primaryGreen,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        setState(() {
                          _selectedArea = null;
                          _areaNameController.clear();
                          _cityNameController.clear();
                          _searchController.clear();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _areaNameController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Area Name',
                    labelStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.place_rounded, color: _primaryGreen, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _primaryGreen, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _cityNameController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'City Name',
                    labelStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.location_city_rounded, color: _primaryGreen, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _primaryGreen, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          const Text(
            'Popular Areas in Vadodara',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popularVadodaraAreas.map((area) {
              final isCurrent = (_currentAreaId.isNotEmpty && area['id'] == _currentAreaId) ||
                  area['name']!.toLowerCase() == _currentAreaName.toLowerCase();
              final isSelected = _areaNameController.text.trim().toLowerCase() == area['name']!.toLowerCase();
              return InkWell(
                onTap: isCurrent ? null : () => _selectPopularArea(area),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _lightGreenTint
                        : (isCurrent ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? _primaryGreen
                          : (isCurrent ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1)),
                    ),
                  ),
                  child: Text(
                    area['name']! + (isCurrent ? ' (Current)' : ''),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? _primaryGreen
                          : (isCurrent ? const Color(0xFF94A3B8) : AppColors.textPrimary),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedArea = {
                    'area': '',
                    'city': _currentCityName.isNotEmpty ? _currentCityName : 'Vadodara',
                  };
                  _areaNameController.clear();
                  _cityNameController.text = _currentCityName.isNotEmpty ? _currentCityName : 'Vadodara';
                });
              },
              icon: const Icon(Icons.edit_note_rounded, size: 18, color: _primaryGreen),
              label: const Text(
                'Enter area name manually',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _primaryGreen,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Reason for Change (Optional)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _reasonController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'e.g., Shifted residence, relocated to this area',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryGreen, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: (!hasValidArea || _isSubmitting) ? null : _handleSendRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryGreen,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFCBD5E1),
            disabledForegroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Send Request to Admin',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
