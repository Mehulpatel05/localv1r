import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_colors.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/presence_service.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/r2_storage_service.dart';
import '../../core/splash_controller.dart';
import '../../core/widgets/instagram_avatar_cropper.dart';
import '../../core/services/name_cache_service.dart';
import '../../core/location/location_engine.dart';
import '../../core/location/location_enabler.dart';
import '../../features/auth/widgets/logo_pin.dart';
import '../../features/auth/widgets/street_painter.dart';
import '../main/main_screen.dart';
import '../onboarding/permission_request_screen.dart';
import '../../main.dart';

enum UsernameState {
  empty,
  focused,
  checking,
  available,
  taken,
  invalid,
  reserved,
}

class CreateHandleScreen extends StatefulWidget {
  final PostRepository repository;
  final String userId;
  final String? phoneNumber;
  final dynamic user;
  final bool isChangeArea;

  const CreateHandleScreen({
    super.key,
    required this.repository,
    required this.userId,
    this.phoneNumber,
    this.user,
    this.isChangeArea = false,
  });

  @override
  State<CreateHandleScreen> createState() => _CreateHandleScreenState();
}

class _CreateHandleScreenState extends State<CreateHandleScreen> {
  static const Color _primaryGreen = Color(0xFF0E8A3E);
  static const Color _lightGreenTint = Color(0xFFE3F4EA);
  static const Color _screenBg = Color(0xFFF8FAFC);
  static const Color _textPrimary = Color(0xFF0F172A);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _borderColor = Color(0xFFE2E8F0);

  static const Set<String> _reservedUsernames = {
    'admin',
    'administrator',
    'root',
    'system',
    'sysadmin',
    'support',
    'nearhood',
    'official',
    'help',
    'info',
    'moderator',
    'mod',
    'security',
    'staff',
    'team',
    'null',
    'undefined',
    'api',
    'auth',
    'developer',
    'bot',
    'service',
    'vadodara',
    'government',
    'police',
  };

  static const List<Map<String, Color>> _avatarPresets = [
    {
      'bg': Color(0xFFE3F4EA),
      'accent': Color(0xFF0E8A3E),
    },
    {
      'bg': Color(0xFFE0F2FE),
      'accent': Color(0xFF0284C7),
    },
    {
      'bg': Color(0xFFFEF3C7),
      'accent': Color(0xFFD97706),
    },
    {
      'bg': Color(0xFFF3E8FF),
      'accent': Color(0xFF9333EA),
    },
    {
      'bg': Color(0xFFFFE4E6),
      'accent': Color(0xFFE11D48),
    },
  ];

  int _selectedAvatarPresetIndex = 0;

  Color get _currentAvatarBgColor =>
      _avatarPresets[_selectedAvatarPresetIndex]['bg']!;

  Color get _currentAvatarAccentColor =>
      _avatarPresets[_selectedAvatarPresetIndex]['accent']!;

  int _currentStep = 1;

  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();

  final TextEditingController _handleController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  final TextEditingController _areaSearchController = TextEditingController();
  final FocusNode _areaFocusNode = FocusNode();

  final TextEditingController _addressNoteController = TextEditingController();
  final FocusNode _addressNoteFocusNode = FocusNode();

  UsernameState _state = UsernameState.empty;
  Timer? _debounceTimer;
  Timer? _areaDebounceTimer;
  bool _isSubmitting = false;
  bool _isLocating = false;
  bool _isSearchingPlaces = false;
  bool _isResolvingArea = false;
  String? _customErrorMessage;
  File? _pickedProfileImage;
  final Map<String, bool> _availabilityCache = {};

  GeoArea? _selectedArea;
  String? _selectedCityName;
  String? _selectedCityId;
  List<Map<String, dynamic>> _livePredictions = [];
  bool _isAreaSearching = false;
  String _autocompleteSessionToken = '';

  @override
  void initState() {
    super.initState();

    if (widget.isChangeArea) {
      _currentStep = 2;
    }

    _nameFocusNode.addListener(() {
      setState(() {});
    });
    _nameController.addListener(() {
      setState(() {});
    });

    if (widget.user?.displayName != null &&
        (widget.user!.displayName as String).trim().isNotEmpty) {
      _nameController.text = (widget.user!.displayName as String).trim();
    }

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        if (_handleController.text.trim().isEmpty) {
          setState(() => _state = UsernameState.empty);
        }
      }
      setState(() {});
    });

    _areaFocusNode.addListener(() {
      setState(() {
        _isAreaSearching = _areaFocusNode.hasFocus &&
            _areaSearchController.text.trim().isNotEmpty;
      });
    });

    _addressNoteFocusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _areaDebounceTimer?.cancel();
    _nameController.dispose();
    _nameFocusNode.dispose();
    _handleController.dispose();
    _focusNode.dispose();
    _areaSearchController.dispose();
    _areaFocusNode.dispose();
    _addressNoteController.dispose();
    _addressNoteFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    _debounceTimer?.cancel();
    final trimmed = value.trim().toLowerCase();

    if (trimmed.isEmpty) {
      setState(() {
        _state = UsernameState.empty;
        _customErrorMessage = null;
      });
      return;
    }

    final RegExp validRegex = RegExp(r'^[a-z0-9]{3,20}$');
    if (!validRegex.hasMatch(trimmed)) {
      setState(() {
        _state = UsernameState.invalid;
        _customErrorMessage =
            'Username must be 3–20 characters using lowercase letters and numbers.';
      });
      return;
    }

    if (_reservedUsernames.contains(trimmed)) {
      setState(() {
        _state = UsernameState.reserved;
        _customErrorMessage = 'This username is reserved and cannot be used.';
      });
      return;
    }

    final filterViolation = ContentFilter.validateContent(trimmed);
    if (filterViolation != null) {
      setState(() {
        _state = UsernameState.invalid;
        _customErrorMessage = 'Username contains prohibited words or patterns.';
      });
      return;
    }

    if (_availabilityCache.containsKey(trimmed)) {
      setState(() {
        _state = _availabilityCache[trimmed]!
            ? UsernameState.available
            : UsernameState.taken;
        _customErrorMessage = null;
      });
      return;
    }

    setState(() {
      _state = UsernameState.checking;
      _customErrorMessage = null;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _checkAvailability(trimmed);
    });
  }


  Future<void> _checkAvailability(String handle) async {
    if (widget.userId.isEmpty) {
      final loggedIn = await AuthService.instance.isLoggedIn();
      if (!loggedIn) {
        setState(() {
          _state = UsernameState.invalid;
          _customErrorMessage = 'Session expired. Please sign in again.';
        });
        return;
      }
    }

    try {
      final isAvailable = await AuthService.instance.checkHandleAvailable(handle);

      if (!mounted || _handleController.text.trim().toLowerCase() != handle) {
        return;
      }

      _availabilityCache[handle] = isAvailable;

      setState(() {
        if (isAvailable) {
          _state = UsernameState.available;
          _customErrorMessage = null;
        } else {
          _state = UsernameState.taken;
          _customErrorMessage = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = UsernameState.available;
      });
    }
  }

  void _onAreaSearchChanged(String query) {
    _areaDebounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _livePredictions.clear();
        _isAreaSearching = false;
        _isSearchingPlaces = false;
        _autocompleteSessionToken = '';
      });
      return;
    }

    if (_autocompleteSessionToken.isEmpty) {
      _autocompleteSessionToken =
          DateTime.now().millisecondsSinceEpoch.toString();
    }

    setState(() {
      _isAreaSearching = true;
      _isSearchingPlaces = true;
    });

    _areaDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final predictions = await AuthService.instance.searchPlacesAutocomplete(
          trimmed,
          sessionToken: _autocompleteSessionToken,
        );
        if (!mounted || _areaSearchController.text.trim() != trimmed) return;
        setState(() {
          _livePredictions = predictions;
          _isSearchingPlaces = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _isSearchingPlaces = false;
        });
      }
    });
  }

  Future<void> _onSelectPrediction(Map<String, dynamic> prediction) async {
    final placeId = (prediction['placeId'] ?? prediction['place_id'] ?? '').toString().trim();
    final mainText = (prediction['mainText'] ??
            prediction['main_text'] ??
            prediction['description'] ??
            prediction['name'] ??
            '')
        .toString()
        .trim();

    if (placeId.isEmpty && mainText.isEmpty) return;

    final lat = (prediction['lat'] as num?)?.toDouble() ??
        (prediction['latitude'] as num?)?.toDouble();
    final lng = (prediction['lng'] as num?)?.toDouble() ??
        (prediction['longitude'] as num?)?.toDouble();

    _areaFocusNode.unfocus();
    setState(() {
      _isResolvingArea = true;
      _isAreaSearching = false;
      _livePredictions.clear();
      _areaSearchController.text = mainText;
      _selectedArea = GeoArea(
        id: placeId.isNotEmpty ? placeId : 'GJ-VAD-AREA',
        cityId: _selectedCityId ?? 'GJ-VAD',
        name: mainText,
        lat: lat,
        lng: lng,
      );
    });

    try {
      final res = await AuthService.instance.resolveArea(
        placeId.isNotEmpty ? placeId : null,
        name: mainText,
        cityId: _selectedCityId,
        sessionToken: _autocompleteSessionToken,
      );
      _autocompleteSessionToken = '';

      if (!mounted) return;

      if (res != null && res['live'] == true && res['area'] != null) {
        final areaData = res['area'] as Map<String, dynamic>;
        final cityData = res['city'] as Map<String, dynamic>?;
        final cityName = cityData?['name'] as String? ?? _selectedCityName ?? 'Vadodara';
        final cityId =
            areaData['city_id'] as String? ?? cityData?['id'] as String? ?? _selectedCityId ?? 'GJ-VAD';

        setState(() {
          _selectedCityName = cityName;
          _selectedCityId = cityId;
          _selectedArea = GeoArea(
            id: areaData['id'] as String? ?? (placeId.isNotEmpty ? placeId : 'GJ-VAD-AREA'),
            cityId: cityId,
            name: areaData['name'] as String? ?? mainText,
            lat: areaData['lat'] != null
                ? (areaData['lat'] as num).toDouble()
                : lat,
            lng: areaData['lng'] != null
                ? (areaData['lng'] as num).toDouble()
                : lng,
          );
          _areaSearchController.text = _selectedArea!.name;
        });
      } else if (res != null && res['live'] == false) {
        final detectedCity = res['detected_city'] as String? ?? mainText;
        final resLat = res['lat'] != null ? (res['lat'] as num).toDouble() : lat;
        final resLng = res['lng'] != null ? (res['lng'] as num).toDouble() : lng;
        setState(() {
          _selectedArea = null;
        });
        _showWaitlistSheet(detectedCity: detectedCity, lat: resLat, lng: resLng);
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isResolvingArea = false);
      }
    }
  }

  Future<void> _detectCurrentLocation() async {
    setState(() => _isLocating = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final turnedOn = await LocationEnabler.requestEnableLocation();
        if (!turnedOn) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please turn on device location (GPS).'),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          setState(() => _isLocating = false);
          return;
        }
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission required to detect your area.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _isLocating = false);
        return;
      }

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          position = last;
        } else {
          rethrow;
        }
      }

      final res = await AuthService.instance.reverseGeocodeCoordinates(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      if (res != null && res['live'] == true && res['area'] != null) {
        final areaData = res['area'] as Map<String, dynamic>;
        final cityData = res['city'] as Map<String, dynamic>?;
        final cityName = cityData?['name'] as String? ?? _selectedCityName ?? 'Vadodara';
        final cityId =
            areaData['city_id'] as String? ?? cityData?['id'] as String? ?? _selectedCityId ?? 'GJ-VAD';

        setState(() {
          _selectedCityName = cityName;
          _selectedCityId = cityId;
          _selectedArea = GeoArea(
            id: areaData['id'] as String,
            cityId: cityId,
            name: areaData['name'] as String? ?? 'Detected Area',
            lat: position.latitude,
            lng: position.longitude,
          );
          _areaSearchController.text = _selectedArea!.name;
          _isAreaSearching = false;
          _livePredictions.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Detected: ${_selectedArea!.name}, $cityName'),
            backgroundColor: _primaryGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (res != null && res['live'] == false) {
        final detectedCity = res['detected_city'] as String? ?? _selectedCityName ?? 'Aapka shehar';
        setState(() {
          _selectedArea = null;
        });
        _showWaitlistSheet(
          detectedCity: detectedCity,
          lat: position.latitude,
          lng: position.longitude,
        );
      } else {
        final match = LocationEngine.detectLocation(
          position.latitude,
          position.longitude,
        );
        if (match.area != null) {
          setState(() {
            _selectedCityName = match.city.name;
            _selectedCityId = match.city.id;
            _selectedArea = match.area;
            _areaSearchController.text = match.area!.name;
            _isAreaSearching = false;
            _livePredictions.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Detected: ${match.area!.name}, ${match.city.name}'),
              backgroundColor: _primaryGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not detect your area. Please search above.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location detection failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  Future<void> _showWaitlistSheet({
    required String detectedCity,
    double? lat,
    double? lng,
  }) async {
    bool isSubmittingWaitlist = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Material(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _borderColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: _lightGreenTint,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_city_rounded,
                          color: _primaryGreen,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Nearhood abhi $detectedCity mein nahi hai',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Hum jald hi aapke shehar aa rahe hain! Waitlist join kijiye taaki launch hote hi aapko sabse pehle access mile.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _textSecondary.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: isSubmittingWaitlist
                              ? null
                              : () async {
                                  setSheetState(
                                      () => isSubmittingWaitlist = true);
                                  final uid = widget.userId.isNotEmpty
                                      ? widget.userId
                                      : (await AuthService.instance.getUserId() ??
                                          '');
                                  final phone = widget.phoneNumber ??
                                      (await AuthService.instance
                                              .getPhoneNumber() ??
                                          '');
                                  final contact = phone.isNotEmpty
                                      ? phone
                                      : (uid.isNotEmpty ? uid : 'app_user');

                                  final success =
                                      await AuthService.instance.joinWaitlist(
                                    cityText: detectedCity,
                                    lat: lat,
                                    lng: lng,
                                    contactOrDeviceId: contact,
                                  );

                                  if (sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? 'Aap waitlist mein add ho gaye hain! Shukriya.'
                                              : 'Waitlist join karne mein samasya aayi. Dobara koshish karein.',
                                        ),
                                        backgroundColor: success
                                            ? _primaryGreen
                                            : AppColors.error,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                          child: isSubmittingWaitlist
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.notifications_active_rounded,
                                        size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Join waitlist',
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: _textSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _areaSearchController.clear();
                            _areaFocusNode.requestFocus();
                          },
                          child: const Text(
                            'Choose another area',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPhotoPickerSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Material(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: AppColors.divider, width: 1.5),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Add Profile Picture',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Choose Default Avatar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(_avatarPresets.length, (idx) {
                    final preset = _avatarPresets[idx];
                    final isSelected = _pickedProfileImage == null &&
                        _selectedAvatarPresetIndex == idx;
                    return GestureDetector(
                      onTap: () {
                        setModalState(() {
                          _selectedAvatarPresetIndex = idx;
                          _pickedProfileImage = null;
                        });
                        setState(() {
                          _selectedAvatarPresetIndex = idx;
                          _pickedProfileImage = null;
                        });
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: preset['bg'],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? _primaryGreen
                                : Colors.transparent,
                            width: isSelected ? 2.5 : 1.0,
                          ),
                        ),
                        child: Center(
                          child: CustomPaint(
                            size: const Size(36, 36),
                            painter: _DefaultAvatarPainter(
                              color: preset['accent']!,
                              strokeWidth: 2.0,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              const SizedBox(height: 14),
              const Divider(color: _borderColor, height: 1),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 22),
                ),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.primary, size: 22),
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_pickedProfileImage != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.errorSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 22),
                  ),
                  title: const Text(
                    'Remove Photo',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _pickedProfileImage = null);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (picked != null) {
        final rawFile = File(picked.path);

        if (!mounted) return;

        final croppedFile = await InstagramAvatarCropper.cropImage(
          context,
          imageFile: rawFile,
        );

        if (croppedFile != null && mounted) {
          setState(() => _pickedProfileImage = croppedFile);
        }
      }
    } catch (e) {
      debugPrint('Error picking profile image: $e');
    }
  }

  Future<void> _createHandle() async {
    if (widget.isChangeArea) {
      if (_selectedArea == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select your area to finish.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() {
        _isSubmitting = true;
        _customErrorMessage = null;
      });

      try {
        final result = await AuthService.instance.confirmAreaDetails(
          areaId: _selectedArea!.id,
          addressNote: _addressNoteController.text.trim(),
        );

        if (!mounted) return;

        if (result['success'] != true) {
          final errorMsg = result['error'] as String? ?? 'Failed to update area. Please try again.';
          setState(() {
            _isSubmitting = false;
            _customErrorMessage = errorMsg;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        final selectedCityId =
            _selectedArea!.cityId.isNotEmpty ? _selectedArea!.cityId : 'GJ-VAD';
        final city = LocationEngine.lookupCity(selectedCityId) ??
            GeoCity(
              id: selectedCityId,
              stateId: 'GJ',
              name: _selectedCityName ?? 'Vadodara',
              enabled: true,
              areas: [_selectedArea!],
            );
        await widget.repository.locationService.setCity(city);
        await widget.repository.locationService.setArea(_selectedArea);

        if (!mounted) return;
        Navigator.of(context).pop(true);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _customErrorMessage = 'An error occurred. Please try again.';
        });
      }
      return;
    }

    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() {
        _currentStep = 1;
        _customErrorMessage = 'Please enter your full name (at least 2 letters).';
      });
      return;
    }

    final handle = _handleController.text.trim().toLowerCase();
    final RegExp validRegex = RegExp(r'^[a-z0-9]{3,20}$');

    if (!validRegex.hasMatch(handle) || _reservedUsernames.contains(handle)) {
      setState(() {
        _currentStep = 1;
        _state = UsernameState.invalid;
        _customErrorMessage = 'Invalid or reserved username.';
      });
      return;
    }

    if (_selectedArea == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your area to finish.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final effectiveUid = widget.userId.isNotEmpty
        ? widget.userId
        : (await AuthService.instance.getUserId() ?? '');

    setState(() {
      _isSubmitting = true;
      _customErrorMessage = null;
    });

    try {
      final selectedCityId =
          _selectedArea!.cityId.isNotEmpty ? _selectedArea!.cityId : 'GJ-VAD';
      final result = await AuthService.instance.saveUserHandle(
        handle,
        userId: effectiveUid,
        phone: widget.phoneNumber,
        name: name,
        cityId: selectedCityId,
        areaId: _selectedArea!.id,
        areaName: _selectedArea!.name,
        addressNote: _addressNoteController.text.trim(),
      );

      if (result['success'] != true) {
        final isTaken = result['isTaken'] == true;
        final errorMsg = result['error'] as String? ?? 'Failed to update username.';

        if (isTaken) {
          _availabilityCache[handle] = false;
        }

        setState(() {
          _currentStep = 1;
          _state = isTaken ? UsernameState.taken : UsernameState.available;
          _isSubmitting = false;
          _customErrorMessage = errorMsg;
        });
        return;
      }

      NameCacheService.instance.setCachedName(handle, name);
      await NameCacheService.instance.saveMyNameLocally(name);

      if (_pickedProfileImage != null) {
        try {
          final uploadedUrl = await R2StorageService.uploadImage(_pickedProfileImage!);
          if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
            await AuthService.instance.updateUserProfileImage(uploadedUrl);
          }
        } catch (e) {
          debugPrint('Profile photo upload warning during onboarding: $e');
        }
      }

      final city = LocationEngine.lookupCity(selectedCityId) ??
          GeoCity(
            id: selectedCityId,
            stateId: 'GJ',
            name: _selectedCityName ?? 'Vadodara',
            enabled: true,
            areas: [_selectedArea!],
          );
      await widget.repository.locationService.setCity(city);
      await widget.repository.locationService.setArea(_selectedArea);

      widget.repository.currentUserHandle = handle;
      NotificationService().initialize();
      NotificationService().startListening(handle);
      PresenceService.instance.init(handle);

      SplashController.instance.warmFetchOnLogin(
        uid: effectiveUid,
        handle: handle,
        cityId: selectedCityId,
        postRepo: widget.repository,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PermissionRequestScreen(
            onComplete: (permContext) async {
              final p = await SharedPreferences.getInstance();
              await p.setString('perms_done', 'true');
              if (permContext.mounted) {
                Navigator.of(permContext).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => MainScreen(
                      repository: widget.repository,
                      currentUserHandle: handle,
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _customErrorMessage =
              'Failed to complete setup: ${e.toString().replaceAll('Exception:', '').trim()}';
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _handleTopLeftAction() async {
    if (widget.isChangeArea) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(false);
        return;
      }
    }

    if (_currentStep == 2) {
      setState(() => _currentStep = 1);
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.divider, width: 1.5),
        ),
        title: const Text(
          'Cancel Setup?',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'If you leave now, your account setup won\'t be completed and you will be signed out.',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.instance.signOut();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const VadodaraLocalApp(),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNameValid = _nameController.text.trim().length >= 2;
    final isStep1Valid =
        isNameValid && _state == UsernameState.available && !_isSubmitting;
    final isStep2Valid =
        _selectedArea != null && !_isSubmitting && !_isResolvingArea;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleTopLeftAction();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(
              _currentStep == 1 ? Icons.close_rounded : Icons.arrow_back_rounded,
              color: _textPrimary,
              size: 22,
            ),
            onPressed: _handleTopLeftAction,
          ),
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LogoPin(width: 22, height: 28),
              SizedBox(width: 8),
              Text(
                'nearhood',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          actions: [
            if (widget.isChangeArea)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Text(
                    'Change Area',
                    style: TextStyle(
                      color: _primaryGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              Center(
                child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_currentStep/2',
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: StreetPainter(
                    strokeColor: const Color(0x180B8A3E),
                    isOtp: true,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeaderTitles(),
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _currentStep == 1
                          ? _buildStep1Card()
                          : _buildStep2Card(),
                    ),
                    const SizedBox(height: 18),
                    _currentStep == 1
                        ? _buildStep1ContinueButton(isStep1Valid)
                        : _buildStep2FinishButton(isStep2Valid),
                    const SizedBox(height: 12),
                    _buildFooterText(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderTitles() {
    final title = _currentStep == 1
        ? 'Namaste! Aap kaun?'
        : 'Aapka ghar kahan hai?';
    final subtitle = _currentStep == 1
        ? 'Apna naam aur username chuniye'
        : 'Apne area ke padosi aur posts dekhne ke liye';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (_currentStep == 2) ...[
            const SizedBox(width: 12),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _lightGreenTint,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _primaryGreen.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                color: _primaryGreen,
                size: 22,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep1Card() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _buildAvatar()),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Photo optional hai',
              style: TextStyle(
                fontSize: 12,
                color: _textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildFullNameField(),
          const SizedBox(height: 16),
          _buildUsernameField(),
          const SizedBox(height: 8),
          _buildUsernameStatusHelper(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return GestureDetector(
      onTap: _showPhotoPickerSheet,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _currentAvatarBgColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: _pickedProfileImage != null
                  ? Image.file(
                      _pickedProfileImage!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    )
                  : CustomPaint(
                      size: const Size(80, 80),
                      painter: _DefaultAvatarPainter(
                        color: _currentAvatarAccentColor,
                      ),
                    ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: _primaryGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullNameField() {
    final hasFocus = _nameFocusNode.hasFocus;
    final isValid = _nameController.text.trim().length >= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Full Name',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: _screenBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasFocus ? _primaryGreen : _borderColor,
              width: hasFocus ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: hasFocus ? _primaryGreen : _textSecondary,
                  size: 18,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Aapka poora naam (e.g. Rahul Sharma)',
                    hintStyle: TextStyle(
                      fontSize: 13.5,
                      color: _textSecondary.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (isValid)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: _primaryGreen,
                    size: 17,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameField() {
    final hasFocus = _focusNode.hasFocus;
    final isTaken = _state == UsernameState.taken;
    final isInvalid = _state == UsernameState.invalid || _state == UsernameState.reserved;
    final isAvailable = _state == UsernameState.available;

    Color currentBorderColor;
    if (isTaken || isInvalid) {
      currentBorderColor = AppColors.error;
    } else if (hasFocus || isAvailable) {
      currentBorderColor = _primaryGreen;
    } else {
      currentBorderColor = _borderColor;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Username',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: (isTaken || isInvalid) ? AppColors.errorSoft : _screenBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: currentBorderColor,
              width: (hasFocus || isAvailable || isTaken || isInvalid) ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 12, right: 6),
                child: Text(
                  '@',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _primaryGreen,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _handleController,
                  focusNode: _focusNode,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                    TextInputFormatter.withFunction((oldVal, newVal) {
                      return newVal.copyWith(text: newVal.text.toLowerCase());
                    }),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  onChanged: _onTextChanged,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'username',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: _textSecondary.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_state == UsernameState.checking)
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
                    ),
                  ),
                )
              else if (isAvailable)
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: _primaryGreen,
                    size: 18,
                  ),
                )
              else if (isTaken || isInvalid)
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Icon(
                    Icons.cancel_rounded,
                    color: AppColors.error,
                    size: 18,
                  ),
                )
              else
                const SizedBox(width: 14),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameStatusHelper() {
    final handleText = _handleController.text.trim();

    switch (_state) {
      case UsernameState.empty:
      case UsernameState.focused:
        return const Text(
          '3–20 characters · lowercase letters and numbers',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        );

      case UsernameState.checking:
        return const Text(
          'Checking availability...',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        );

      case UsernameState.available:
        return Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: _primaryGreen,
            ),
            const SizedBox(width: 4),
            Text(
              '@$handleText available hai',
              style: const TextStyle(
                color: _primaryGreen,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      case UsernameState.taken:
        return Row(
          children: [
            const Icon(
              Icons.cancel_rounded,
              size: 14,
              color: AppColors.error,
            ),
            const SizedBox(width: 4),
            Text(
              '@$handleText already taken hai',
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      case UsernameState.invalid:
      case UsernameState.reserved:
        return Text(
          _customErrorMessage ?? 'Invalid username.',
          style: const TextStyle(
            color: AppColors.error,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        );
    }
  }

  Widget _buildStep1ContinueButton(bool isStep1Valid) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isStep1Valid
              ? _primaryGreen
              : _primaryGreen.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: isStep1Valid
            ? () {
                _focusNode.unfocus();
                _nameFocusNode.unfocus();
                setState(() => _currentStep = 2);
              }
            : null,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Continue',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(width: 6),
            Icon(Icons.arrow_forward_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Card() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAreaSearchField(),
          if (_isAreaSearching &&
              (_livePredictions.isNotEmpty || _isSearchingPlaces))
            _buildAreaSuggestionsList(),
          const SizedBox(height: 14),
          _buildCurrentLocationButton(),
          if (_selectedArea != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _lightGreenTint.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primaryGreen.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: _primaryGreen, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_selectedArea!.name}, ${_selectedCityName ?? "Vadodara"}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          _buildAddressNoteField(),
        ],
      ),
    );
  }

  Widget _buildAreaSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your area',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: _screenBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _primaryGreen,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.location_on_outlined,
                  color: _primaryGreen,
                  size: 19,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _areaSearchController,
                  focusNode: _areaFocusNode,
                  onChanged: _onAreaSearchChanged,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search or choose your area (e.g. Alkapuri)',
                    hintStyle: TextStyle(
                      fontSize: 13.5,
                      color: _textSecondary.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_isResolvingArea || _isSearchingPlaces)
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
                    ),
                  ),
                )
              else if (_areaSearchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: _textSecondary),
                  onPressed: () {
                    _areaSearchController.clear();
                    _onAreaSearchChanged('');
                    setState(() {
                      _selectedArea = null;
                    });
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAreaSuggestionsList() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _isSearchingPlaces
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
                  ),
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: _livePredictions.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: _borderColor),
              itemBuilder: (ctx, index) {
                final prediction = _livePredictions[index];
                final mainText = (prediction['mainText'] ??
                        prediction['main_text'] ??
                        prediction['description'] ??
                        prediction['name'] ??
                        '')
                    .toString();
                final secondaryText = (prediction['secondaryText'] ??
                        prediction['secondary_text'] ??
                        '')
                    .toString();

                return ListTile(
                  dense: true,
                  minVerticalPadding: 10,
                  leading: const Icon(
                    Icons.location_on_rounded,
                    color: _primaryGreen,
                    size: 18,
                  ),
                  title: Text(
                    mainText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _textPrimary,
                    ),
                  ),
                  subtitle: secondaryText.isNotEmpty
                      ? Text(
                          secondaryText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textSecondary,
                          ),
                        )
                      : null,
                  onTap: () => _onSelectPrediction(prediction),
                );
              },
            ),
    );
  }

  Widget _buildCurrentLocationButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLocating ? null : _detectCurrentLocation,
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: const _DashedBorderPainter(
            color: _primaryGreen,
            radius: 12,
            strokeWidth: 1.2,
          ),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: _lightGreenTint.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: _isLocating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          color: _primaryGreen,
                          size: 17,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Use my current location',
                          style: TextStyle(
                            color: _primaryGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddressNoteField() {
    final hasFocus = _addressNoteFocusNode.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Society / flat / landmark (Optional)',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: _screenBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasFocus ? _primaryGreen : _borderColor,
              width: hasFocus ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(
                  Icons.home_outlined,
                  color: hasFocus ? _primaryGreen : _textSecondary,
                  size: 20,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _addressNoteController,
                  focusNode: _addressNoteFocusNode,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Tower B, Shivalik Residency, Near Circle',
                    hintStyle: TextStyle(
                      fontSize: 13.5,
                      color: _textSecondary.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: _textSecondary),
            SizedBox(width: 4),
            Expanded(
              child: Text(
                'Exact address kisi ko nahi dikhega, sirf aapka area.',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep2FinishButton(bool isStep2Valid) {
    final areaName = _selectedArea?.name ?? 'Area';

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isStep2Valid
              ? _primaryGreen
              : _primaryGreen.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: isStep2Valid ? _createHandle : null,
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.isChangeArea
                        ? 'Confirm & join $areaName'
                        : 'Finish & join $areaName',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle_rounded, size: 18),
                ],
              ),
      ),
    );
  }

  Widget _buildFooterText() {
    final footerMsg = _currentStep == 1
        ? 'You can change your profile details later.'
        : 'You can change your area later from Profile.';

    return Center(
      child: Text(
        footerMsg,
        style: TextStyle(
          fontSize: 12.5,
          color: _textSecondary.withValues(alpha: 0.8),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  static const double dashWidth = 5.0;
  static const double dashSpace = 3.0;

  final Color color;
  final double strokeWidth;
  final double radius;

  const _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.2,
    this.radius = 14,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final length = (distance + dashWidth < metric.length)
            ? dashWidth
            : metric.length - distance;
        final extract = metric.extractPath(distance, distance + length);
        canvas.drawPath(extract, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.radius != radius;
}

class _DefaultAvatarPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _DefaultAvatarPainter({
    required this.color,
    this.strokeWidth = 2.4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    final headCenter = Offset(cx, cy - size.height * 0.11);
    final headRadius = size.width * 0.16;
    canvas.drawCircle(headCenter, headRadius, paint);

    final shoulderPath = Path();
    final leftX = cx - size.width * 0.28;
    final rightX = cx + size.width * 0.28;
    final topY = cy + size.height * 0.10;
    final bottomY = cy + size.height * 0.26;

    shoulderPath.moveTo(leftX, bottomY);
    shoulderPath.cubicTo(
      leftX,
      topY,
      rightX,
      topY,
      rightX,
      bottomY,
    );

    canvas.drawPath(shoulderPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DefaultAvatarPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
