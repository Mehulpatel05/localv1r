import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../bazar/shop_detail_screen.dart';
import '../../services/bazar_repository.dart';
import '../../services/auth_service.dart';
import '../../services/r2_storage_service.dart';
import '../../core/location/location_engine.dart';
import '../../theme/app_colors.dart';

class RegisterShopScreen extends StatefulWidget {
  const RegisterShopScreen({super.key});

  @override
  State<RegisterShopScreen> createState() => _RegisterShopScreenState();
}

class _RegisterShopScreenState extends State<RegisterShopScreen> {
  int _currentStep = 0;

  String? _shopLogoPath;
  final TextEditingController _shopNameController = TextEditingController();
  String _selectedCategory = 'Pharmacy';
  final TextEditingController _shortDescController = TextEditingController();

  final List<Map<String, String>> _categories = [
    {'name': 'Pharmacy', 'icon': '💊'},
    {'name': 'Kirana', 'icon': '🛒'},
    {'name': 'Bakery', 'icon': '🥐'},
    {'name': 'Salon', 'icon': '💇'},
    {'name': 'Fashion', 'icon': '👗'},
    {'name': 'Tailor', 'icon': '👔'},
    {'name': 'Electronics', 'icon': '📱'},
    {'name': 'Cafe', 'icon': '☕'},
    {'name': 'Other', 'icon': '🏪'},
  ];

  final TextEditingController _addressController = TextEditingController();
  String _selectedVisibilityKm = '2 km';
  final List<String> _visibilityKmOptions = ['1 km', '2 km', '5 km', '10 km', '30 km'];
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _whatsAppController = TextEditingController();
  bool _sameNumberOnWhatsApp = true;

  final Set<String> _selectedOpenDays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'};
  final List<Map<String, String>> _daysOfWeek = [
    {'id': 'Mon', 'label': 'M'},
    {'id': 'Tue', 'label': 'T'},
    {'id': 'Wed', 'label': 'W'},
    {'id': 'Thu', 'label': 'T'},
    {'id': 'Fri', 'label': 'F'},
    {'id': 'Sat', 'label': 'S'},
    {'id': 'Sun', 'label': 'S'},
  ];
  String _openingTime = '9:00 AM';
  String _closingTime = '9:00 PM';
  bool _homeDeliveryEnabled = true;
  final Set<String> _selectedPaymentMethods = {'Cash', 'UPI'};

  String? _shopBoardPhotoPath;
  final TextEditingController _gstController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLocating = false;

  Future<void> _useCurrentLocation() async {
    if (_isLocating) return;

    setState(() => _isLocating = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('⚠️ Please enable GPS / Location services on your device.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('⚠️ Location permission was denied.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('⚠️ Location permission permanently denied. Please enable in Settings.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw TimeoutException('GPS signal timed out'),
      );

      final matchResult = LocationEngine.detectLocation(position.latitude, position.longitude);

      String detectedAddress = '';
      if (matchResult.area != null) {
        detectedAddress = '${matchResult.area!.name}, ${matchResult.city.name}';
      } else if (matchResult.city.name.isNotEmpty) {
        detectedAddress = matchResult.city.name;
      } else {
        detectedAddress = 'Vadodara';
      }

      if (mounted) {
        setState(() {
          _addressController.text = detectedAddress;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.textPrimary,
            content: Text('📍 Location updated to $detectedAddress'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not fetch GPS location: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _shortDescController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    _whatsAppController.dispose();
    _gstController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool _validateStep(int step) {
    if (step == 1) {
      if (_shopNameController.text.trim().length < 3) {
        _showErrorSnackBar('Shop name is required (min 3 characters).');
        return false;
      }
      if (_selectedCategory.isEmpty) {
        _showErrorSnackBar('Please select a shop category.');
        return false;
      }
      if (_shortDescController.text.trim().length < 5) {
        _showErrorSnackBar('Please enter a short description about your shop.');
        return false;
      }
      return true;
    } else if (step == 2) {
      if (_addressController.text.trim().length < 4) {
        _showErrorSnackBar('Shop address is required.');
        return false;
      }
      final phone = _contactController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
      if (phone.length < 10) {
        _showErrorSnackBar('Valid 10-digit contact number is required.');
        return false;
      }
      if (!_sameNumberOnWhatsApp) {
        final wa = _whatsAppController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
        if (wa.length < 10) {
          _showErrorSnackBar('Valid 10-digit WhatsApp number is required.');
          return false;
        }
      }
      return true;
    } else if (step == 3) {
      if (_selectedOpenDays.isEmpty) {
        _showErrorSnackBar('Please select at least 1 open day for your shop.');
        return false;
      }
      if (_selectedPaymentMethods.isEmpty) {
        _showErrorSnackBar('Please select at least 1 accepted payment method.');
        return false;
      }
      return true;
    }
    return true;
  }

  Future<void> _pickShopLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() {
        _shopLogoPath = picked.path;
      });
    }
  }

  Future<void> _pickShopBoardPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() {
        _shopBoardPhotoPath = picked.path;
      });
    }
  }

  void _handleBackNavigation() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    } else {
      Navigator.pop(context);
    }
  }

  void _submitRegistration() async {
    setState(() => _isSubmitting = true);

    String finalLogoUrl = '';
    if (_shopLogoPath != null) {
      try {
        final uploaded = await R2StorageService.uploadMedia(
          File(_shopLogoPath!),
        );
        if (uploaded != null && uploaded.isNotEmpty) {
          finalLogoUrl = uploaded;
        }
      } catch (e) {
        debugPrint('[RegisterShop] logo upload error: $e');
      }
    }

    final categoryIcon = _categories.firstWhere(
      (c) => c['name'] == _selectedCategory,
      orElse: () => {'icon': '🏪'},
    )['icon']!;

    final handle = await AuthService.instance.getUserHandle() ?? '@me';
    final cleanHandle = handle.replaceAll('@', '').trim();

    final newShop = LocalShop(
      id: 'shop_$cleanHandle',
      ownerHandle: cleanHandle,
      name: _shopNameController.text.trim(),
      category: _selectedCategory,
      categoryIcon: categoryIcon,
      location: _addressController.text.trim(),
      distanceKm: double.tryParse(_selectedVisibilityKm.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 1.0,
      isVerified: true,
      imageUrl: finalLogoUrl,
      bannerUrl: finalLogoUrl,
      phone: _contactController.text.trim(),
      deliveryInfo: _homeDeliveryEnabled ? 'Home delivery available' : 'In-store pickup only',
      timings: '$_openingTime - $_closingTime',
      aboutText: _shortDescController.text.trim(),
      isOpen: true,
      sameWhatsapp: _sameNumberOnWhatsApp,
      homeDelivery: _homeDeliveryEnabled,
      viewsCount: 0,
      chatsCount: 0,
      ordersCount: 0,
      status: 'pending',
      products: [],
    );

    await BazarRepository.instance.registerShop(newShop);

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _currentStep = 5;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentStep == 0 || _currentStep == 5,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep == 5) {
          Navigator.pop(context, true);
        } else {
          _handleBackNavigation();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: _currentStep == 5
            ? AppBar(
                backgroundColor: AppColors.surface,
                elevation: 0,
                automaticallyImplyLeading: false,
              )
            : AppBar(
                backgroundColor: AppColors.surface,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: GestureDetector(
                    onTap: _handleBackNavigation,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.chipBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                centerTitle: true,
                title: Text(
                  _getAppBarTitle(),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
        body: _buildCurrentStepBody(),
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_currentStep) {
      case 0:
        return 'Register your shop';
      case 1:
        return 'Shop details';
      case 2:
        return 'Location & contact';
      case 3:
        return 'Timings & delivery';
      case 4:
        return 'Verify your shop';
      case 5:
        return '';
      default:
        return 'Register your shop';
    }
  }

  Widget _buildProgressBar(int stepNumber) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $stepNumber of 4',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: stepNumber / 4.0,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCurrentStepBody() {
    switch (_currentStep) {
      case 0:
        return _buildWelcomeStep();
      case 1:
        return _buildStep1ShopDetails();
      case 2:
        return _buildStep2LocationContact();
      case 3:
        return _buildStep3TimingsDelivery();
      case 4:
        return _buildStep4VerifyShop();
      case 5:
        return _buildStep5ShopSubmitted();
      default:
        return _buildWelcomeStep();
    }
  }

  Widget _buildWelcomeStep() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),

                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Center(
                    child: Text('🏪', style: TextStyle(fontSize: 42)),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Grow your shop in your own neighbourhood',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Free listing, no app download needed for your customers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 24),

                _buildFeatureBullet('🆓', 'Free for the first 60 days'),
                const SizedBox(height: 12),
                _buildFeatureBullet('📍', 'Shown first to neighbours within 2 km'),
                const SizedBox(height: 12),
                _buildFeatureBullet('💬', 'Orders come as Chat, Call or WhatsApp'),
                const SizedBox(height: 12),
                _buildFeatureBullet('🛡️', 'Verified badge once approved'),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _currentStep = 1;
                    });
                  },
                  child: const Text(
                    'Get started',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Takes about 3 minutes',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureBullet(String iconEmoji, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Text(iconEmoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1ShopDetails() {
    final labelStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProgressBar(1),

                Center(
                  child: GestureDetector(
                    onTap: _pickShopLogo,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.divider, width: 1.5),
                        image: _shopLogoPath != null
                            ? DecorationImage(
                                image: FileImage(File(_shopLogoPath!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _shopLogoPath == null
                          ? Icon(
                              Icons.camera_alt_outlined,
                              color: AppColors.textMuted,
                              size: 32,
                            )
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                RichText(
                  text: TextSpan(
                    style: labelStyle,
                    children: [
                      const TextSpan(text: 'SHOP NAME '),
                      TextSpan(text: '*', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _shopNameController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'e.g. Mehta Pharmacy',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 16),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                RichText(
                  text: TextSpan(
                    style: labelStyle,
                    children: [
                      const TextSpan(text: 'CATEGORY '),
                      TextSpan(text: '*', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _categories.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.6,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = _selectedCategory == cat['name'];

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat['name']!;
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(cat['icon']!, style: const TextStyle(fontSize: 15)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                cat['name']!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

                RichText(
                  text: TextSpan(
                    style: labelStyle,
                    children: [
                      const TextSpan(text: 'SHORT DESCRIPTION '),
                      TextSpan(text: '*', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _shortDescController,
                    maxLines: 3,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Medicines, health products, home delivery within 1 km.',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        _buildContinueBottomButton(),
      ],
    );
  }

  Widget _buildStep2LocationContact() {
    final labelStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProgressBar(2),

                RichText(
                  text: TextSpan(
                    style: labelStyle,
                    children: [
                      const TextSpan(text: 'SHOP ADDRESS '),
                      TextSpan(text: '*', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _addressController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Shop 4, Alkapuri Main Road',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary, width: 1.5),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: _isLocating
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('📍', style: TextStyle(fontSize: 16)),
                  label: Text(
                    _isLocating ? 'Detecting current location...' : 'Use my current location',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: _isLocating ? null : _useCurrentLocation,
                ),

                const SizedBox(height: 20),

                Text('VISIBLE TO BUYERS WITHIN', style: labelStyle),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _visibilityKmOptions.map((opt) {
                    final isSelected = _selectedVisibilityKm == opt;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedVisibilityKm = opt;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider),
                        ),
                        child: Text(
                          opt,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                RichText(
                  text: TextSpan(
                    style: labelStyle,
                    children: [
                      const TextSpan(text: 'CONTACT NUMBER (10 DIGITS) '),
                      TextSpan(text: '*', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _contactController,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: '98xxxxxx10',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 16),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Same number on WhatsApp',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Customers can message you directly',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _sameNumberOnWhatsApp,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.primary,
                      inactiveThumbColor: AppColors.textMuted,
                      inactiveTrackColor: AppColors.chipBg,
                      onChanged: (val) {
                        setState(() {
                          _sameNumberOnWhatsApp = val;
                        });
                      },
                    ),
                  ],
                ),

                if (!_sameNumberOnWhatsApp) ...[
                  const SizedBox(height: 14),
                  RichText(
                    text: TextSpan(
                      style: labelStyle,
                      children: [
                        const TextSpan(text: 'WHATSAPP NUMBER (10 DIGITS) '),
                        TextSpan(text: '*', style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _whatsAppController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'e.g. 98xxxxxx12',
                        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 16),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        _buildContinueBottomButton(),
      ],
    );
  }

  Widget _buildStep3TimingsDelivery() {
    final labelStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProgressBar(3),

                RichText(
                  text: TextSpan(
                    style: labelStyle,
                    children: [
                      const TextSpan(text: 'DAYS OPEN '),
                      TextSpan(text: '*', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _daysOfWeek.map((day) {
                    final isSelected = _selectedOpenDays.contains(day['id']);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            if (_selectedOpenDays.length > 1) {
                              _selectedOpenDays.remove(day['id']);
                            }
                          } else {
                            _selectedOpenDays.add(day['id']!);
                          }
                        });
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          day['label']!,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                const Text('TIMINGS', style: TextStyle(color: Color(0xFF5B6B7B), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _pickTimeModal(isOpening: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Opens at', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              const SizedBox(height: 4),
                              Text(
                                _openingTime,
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _pickTimeModal(isOpening: false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Closes at', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              const SizedBox(height: 4),
                              Text(
                                _closingTime,
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Home delivery available',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Customers will see delivery icon on your shop',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _homeDeliveryEnabled,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.primary,
                      inactiveThumbColor: AppColors.textMuted,
                      inactiveTrackColor: AppColors.chipBg,
                      onChanged: (val) {
                        setState(() {
                          _homeDeliveryEnabled = val;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                RichText(
                  text: TextSpan(
                    style: labelStyle,
                    children: [
                      const TextSpan(text: 'PAYMENT METHODS ACCEPTED '),
                      TextSpan(text: '*', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: ['Cash', 'UPI', 'Cards'].map((pm) {
                    final isSelected = _selectedPaymentMethods.contains(pm);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            if (_selectedPaymentMethods.length > 1) {
                              _selectedPaymentMethods.remove(pm);
                            }
                          } else {
                            _selectedPaymentMethods.add(pm);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider),
                        ),
                        child: Text(
                          pm,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        _buildContinueBottomButton(),
      ],
    );
  }

  void _pickTimeModal({required bool isOpening}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpening
          ? const TimeOfDay(hour: 9, minute: 0)
          : const TimeOfDay(hour: 21, minute: 0),
    );

    if (picked != null) {
      final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final minute = picked.minute.toString().padLeft(2, '0');
      final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
      setState(() {
        if (isOpening) {
          _openingTime = '$hour:$minute $period';
        } else {
          _closingTime = '$hour:$minute $period';
        }
      });
    }
  }

  Widget _buildStep4VerifyShop() {
    final labelStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProgressBar(4),

                Text('PHOTO OF SHOP FRONT / BOARD (OPTIONAL)', style: labelStyle),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _pickShopBoardPhoto,
                  child: Container(
                    width: double.infinity,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                      image: _shopBoardPhotoPath != null
                          ? DecorationImage(
                              image: FileImage(File(_shopBoardPhotoPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _shopBoardPhotoPath == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined, color: AppColors.textMuted, size: 36),
                              const SizedBox(height: 8),
                              Text(
                                'Tap to upload shop photo',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),

                const SizedBox(height: 20),

                Text('GST OR BUSINESS REGISTRATION NUMBER (OPTIONAL)', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _gstController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'e.g. 24AAAAA0000A1Z5',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined, color: AppColors.primaryText, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Verified shops get 3x more orders and customer trust.',
                          style: TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              onPressed: _isSubmitting ? null : _submitRegistration,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Submit for review',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep5ShopSubmitted() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded, color: AppColors.primary, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'Shop Submitted!',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'We review shops within 24 hours. You will receive a notification as soon as your shop goes live in Vadodara Bazar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueBottomButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
          ),
          onPressed: () {
            if (_validateStep(_currentStep)) {
              setState(() {
                _currentStep++;
              });
            }
          },
          child: const Text(
            'Continue',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
