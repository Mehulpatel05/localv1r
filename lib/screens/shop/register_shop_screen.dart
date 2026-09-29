import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../bazar/shop_detail_screen.dart';
import '../../services/bazar_repository.dart';

class RegisterShopScreen extends StatefulWidget {
  const RegisterShopScreen({super.key});

  @override
  State<RegisterShopScreen> createState() => _RegisterShopScreenState();
}

class _RegisterShopScreenState extends State<RegisterShopScreen> {
  int _currentStep = 0; // 0 = Welcome screen, 1 = Step 1, 2 = Step 2, 3 = Step 3, 4 = Step 4

  // --- FORM DATA STATE ---
  // Step 1: Shop details
  String? _shopLogoPath;
  final TextEditingController _shopNameController = TextEditingController();
  String _selectedCategory = 'Pharmacy';
  final TextEditingController _shortDescController = TextEditingController();

  final List<Map<String, String>> _categories = [
    {'name': 'Kirana', 'icon': '🛒'},
    {'name': 'Pharmacy', 'icon': '💊'},
    {'name': 'Bakery', 'icon': '🥐'},
    {'name': 'Salon', 'icon': '💇'},
    {'name': 'Tailor', 'icon': '👗'},
    {'name': 'Other', 'icon': '💬'},
  ];

  // Step 2: Location & contact
  final TextEditingController _addressController = TextEditingController();
  String _selectedVisibilityKm = '2 km';
  final List<String> _visibilityKmOptions = ['1 km', '2 km', '5 km', '10 km', '30 km'];
  final TextEditingController _contactController = TextEditingController();
  bool _sameNumberOnWhatsApp = true;

  // Step 3: Timings & delivery
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

  // Step 4: Verify your shop
  String? _shopBoardPhotoPath;
  final TextEditingController _gstController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _shopNameController.dispose();
    _shortDescController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    _gstController.dispose();
    super.dispose();
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

  void _submitRegistration() {
    setState(() => _isSubmitting = true);

    final categoryIcon = _categories.firstWhere(
      (c) => c['name'] == _selectedCategory,
      orElse: () => {'icon': '🏪'},
    )['icon']!;

    final newShop = LocalShop(
      id: 'shop_${DateTime.now().millisecondsSinceEpoch}',
      name: _shopNameController.text.trim().isEmpty ? 'My Shop' : _shopNameController.text.trim(),
      category: _selectedCategory,
      categoryIcon: categoryIcon,
      location: _addressController.text.trim().isEmpty ? 'Local Area' : _addressController.text.trim(),
      distanceKm: double.tryParse(_selectedVisibilityKm.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 1.0,
      isVerified: true,
      imageUrl: _shopLogoPath ?? '',
      phone: _contactController.text.trim(),
      deliveryInfo: _homeDeliveryEnabled ? 'Home delivery available' : 'In-store pickup only',
      timings: '$_openingTime - $_closingTime',
      aboutText: _shortDescController.text.trim(),
      products: [],
    );

    BazarRepository.instance.registerShop(newShop);

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _currentStep = 5;
      });
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
        backgroundColor: Colors.black,
        appBar: _currentStep == 5
            ? AppBar(
                backgroundColor: Colors.black,
                elevation: 0,
                automaticallyImplyLeading: false,
              )
            : AppBar(
                backgroundColor: Colors.black,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: GestureDetector(
                    onTap: _handleBackNavigation,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                centerTitle: true,
                title: Text(
                  _getAppBarTitle(),
                  style: const TextStyle(
                    color: Colors.white,
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
          style: const TextStyle(
            color: Color(0xFF90B4B6),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: stepNumber / 4.0,
            backgroundColor: const Color(0xFF072E33),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
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

  // --- WELCOME STEP (Image 1) ---
  Widget _buildWelcomeStep() {
    const cardBg = Color(0xFF072E33);
    const borderColor = Color(0xFF0E525B);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),

                // 24h Shop Icon Banner
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: const Center(
                    child: Text('🏪', style: TextStyle(fontSize: 42)),
                  ),
                ),

                const SizedBox(height: 20),

                // Headline
                const Text(
                  'Grow your shop in your own neighbourhood',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 8),

                // Subtitle
                const Text(
                  'Free listing, no app download needed for your customers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF90B4B6),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 24),

                // Feature Bullets
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

        // Bottom Action Button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
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
              const Text(
                'Takes about 3 minutes',
                style: TextStyle(color: Color(0xFF90B4B6), fontSize: 12),
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
        color: const Color(0xFF072E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0E525B)),
      ),
      child: Row(
        children: [
          Text(iconEmoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 1: SHOP DETAILS (Image 2) ---
  Widget _buildStep1ShopDetails() {
    const cardBg = Color(0xFF072E33);
    const borderColor = Color(0xFF0E525B);
    const labelStyle = TextStyle(
      color: Color(0xFF90B4B6),
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

                // Circular Photo Upload Button
                Center(
                  child: GestureDetector(
                    onTap: _pickShopLogo,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: cardBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: borderColor, width: 1.5),
                        image: _shopLogoPath != null
                            ? DecorationImage(
                                image: FileImage(File(_shopLogoPath!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _shopLogoPath == null
                          ? const Icon(
                              Icons.camera_alt_outlined,
                              color: Color(0xFF90B4B6),
                              size: 32,
                            )
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // SHOP NAME
                const Text('SHOP NAME', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _shopNameController,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Mehta Pharmacy',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // CATEGORY
                const Text('CATEGORY', style: labelStyle),
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
                          color: isSelected ? Colors.white : cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelected ? Colors.white : borderColor),
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
                                  color: isSelected ? Colors.black : Colors.white,
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

                // SHORT DESCRIPTION
                const Text('SHORT DESCRIPTION', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _shortDescController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'Medicines, health products, home delivery within 1 km.',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
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

  // --- STEP 2: LOCATION & CONTACT (Image 3) ---
  Widget _buildStep2LocationContact() {
    const cardBg = Color(0xFF072E33);
    const borderColor = Color(0xFF0E525B);
    const labelStyle = TextStyle(
      color: Color(0xFF90B4B6),
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

                // SHOP ADDRESS
                const Text('SHOP ADDRESS', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _addressController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'Shop 4, Alkapuri Main Road',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Use my current location Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: const Text('📍', style: TextStyle(fontSize: 16)),
                  label: const Text(
                    'Use my current location',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFF072E33),
                        content: Text('📍 Location updated to current GPS position.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

                // VISIBLE TO BUYERS WITHIN (Options up to 30 km as requested)
                const Text('VISIBLE TO BUYERS WITHIN', style: labelStyle),
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
                          color: isSelected ? Colors.white : cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isSelected ? Colors.white : borderColor),
                        ),
                        child: Text(
                          opt,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // CONTACT NUMBER
                const Text('CONTACT NUMBER', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _contactController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: '98xxxxxx10',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Same number on WhatsApp Switch
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Same number on WhatsApp',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Customers can message you directly',
                            style: TextStyle(color: Color(0xFF90B4B6), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _sameNumberOnWhatsApp,
                      activeThumbColor: Colors.white,
                      activeTrackColor: const Color(0xFF14B8A6),
                      inactiveThumbColor: Colors.grey,
                      inactiveTrackColor: cardBg,
                      onChanged: (val) {
                        setState(() {
                          _sameNumberOnWhatsApp = val;
                        });
                      },
                    ),
                  ],
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

  // --- STEP 3: TIMINGS & DELIVERY (Image 4) ---
  Widget _buildStep3TimingsDelivery() {
    const cardBg = Color(0xFF072E33);
    const borderColor = Color(0xFF0E525B);
    const labelStyle = TextStyle(
      color: Color(0xFF90B4B6),
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

                // OPEN DAYS
                const Text('OPEN DAYS', style: labelStyle),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _daysOfWeek.map((dayItem) {
                    final dayId = dayItem['id']!;
                    final dayLabel = dayItem['label']!;
                    final isSelected = _selectedOpenDays.contains(dayId);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedOpenDays.remove(dayId);
                          } else {
                            _selectedOpenDays.add(dayId);
                          }
                        });
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : cardBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? Colors.white : borderColor),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          dayLabel,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // OPENING TIME
                const Text('OPENING TIME', style: labelStyle),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: const TimeOfDay(hour: 9, minute: 0),
                          );
                          if (time != null && mounted) {
                            setState(() {
                              _openingTime = time.format(context);
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _openingTime,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: const TimeOfDay(hour: 21, minute: 0),
                          );
                          if (time != null && mounted) {
                            setState(() {
                              _closingTime = time.format(context);
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _closingTime,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Home delivery Switch
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Home delivery',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Within your visible area',
                            style: TextStyle(color: Color(0xFF90B4B6), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _homeDeliveryEnabled,
                      activeThumbColor: Colors.white,
                      activeTrackColor: const Color(0xFF14B8A6),
                      inactiveThumbColor: Colors.grey,
                      inactiveTrackColor: cardBg,
                      onChanged: (val) {
                        setState(() {
                          _homeDeliveryEnabled = val;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // PAYMENT ACCEPTED
                const Text('PAYMENT ACCEPTED', style: labelStyle),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildPaymentChip('💵 Cash', 'Cash'),
                    const SizedBox(width: 10),
                    _buildPaymentChip('📲 UPI', 'UPI'),
                    const SizedBox(width: 10),
                    _buildPaymentChip('💳 Card', 'Card'),
                  ],
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

  Widget _buildPaymentChip(String label, String value) {
    final isSelected = _selectedPaymentMethods.contains(value);
    const cardBg = Color(0xFF072E33);
    const borderColor = Color(0xFF0E525B);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedPaymentMethods.remove(value);
            } else {
              _selectedPaymentMethods.add(value);
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? Colors.white : borderColor),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // --- STEP 4: VERIFY YOUR SHOP (Image 5) ---
  Widget _buildStep4VerifyShop() {
    const cardBg = Color(0xFF072E33);
    const borderColor = Color(0xFF0E525B);
    const labelStyle = TextStyle(
      color: Color(0xFF90B4B6),
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

                const Text(
                  'Optional, but verified shops get a badge and are shown higher in Bazaar.',
                  style: TextStyle(color: Color(0xFF90B4B6), fontSize: 13.5, height: 1.4),
                ),

                const SizedBox(height: 20),

                // Photo of your shop board Button
                GestureDetector(
                  onTap: _pickShopBoardPhoto,
                  child: Container(
                    width: double.infinity,
                    height: 80,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor),
                      image: _shopBoardPhotoPath != null
                          ? DecorationImage(
                              image: FileImage(File(_shopBoardPhotoPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: _shopBoardPhotoPath == null
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Text('📷', style: TextStyle(fontSize: 20)),
                              SizedBox(width: 10),
                              Text(
                                'Photo of your shop board',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),

                const SizedBox(height: 20),

                // GST NUMBER (OPTIONAL)
                const Text('GST NUMBER (OPTIONAL)', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _gstController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: '—',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Security Note Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: const [
                      Text('🛡️', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'We only use this to confirm the shop is real. It is never shown publicly.',
                          style: TextStyle(
                            color: Color(0xFF90B4B6),
                            fontSize: 13,
                            height: 1.35,
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

        // Submit Button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
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
                            color: Colors.black,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Submit for review',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Review usually takes under 24 hours',
                style: TextStyle(color: Color(0xFF90B4B6), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContinueBottomButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
          ),
          onPressed: () {
            setState(() {
              _currentStep++;
            });
          },
          child: const Text(
            'Continue',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // --- STEP 5: SHOP SUBMITTED SUCCESS SCREEN (Matching media_1790654844118.png) ---
  Widget _buildStep5ShopSubmitted() {
    final shopName = _shopNameController.text.trim().isEmpty ? 'My Shop' : _shopNameController.text.trim();
    final categoryIcon = _categories.firstWhere(
      (c) => c['name'] == _selectedCategory,
      orElse: () => {'icon': '🏪'},
    )['icon']!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: Column(
        children: [
          const Spacer(),

          // Top Teal Checkmark Circle
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFF14B8A6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.black,
              size: 46,
            ),
          ),

          const SizedBox(height: 24),

          // Headline: Shop submitted!
          const Text(
            'Shop submitted!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          // Subtitle
          Text(
            "We're reviewing $shopName. You'll get a notification within 24 hours.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF90B4B6),
              fontSize: 14.5,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 32),

          // Shop Preview Card (Matching image media_1790654844118.png)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF072E33),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF0E525B), width: 1.5),
            ),
            child: Row(
              children: [
                // Category/Logo Icon Square
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF073F46),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      categoryIcon,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Shop Meta Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shopName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_selectedCategory  •  Alkapuri',
                        style: const TextStyle(
                          color: Color(0xFF90B4B6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Pending verification Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF074047),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Pending verification',
                          style: TextStyle(
                            color: Color(0xFF90B4B6),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Buttons Stack (Preview my shop page & Done)
          Column(
            children: [
              // Outlined Button: Preview my shop page
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  onPressed: _openShopPreviewSheet,
                  child: const Text(
                    'Preview my shop page',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Solid White Button: Done
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ],
      ),
    );
  }

  void _openShopPreviewSheet() {
    final shopName = _shopNameController.text.trim().isEmpty ? 'My Shop' : _shopNameController.text.trim();
    final address = _addressController.text.trim().isEmpty ? 'Location N/A' : _addressController.text.trim();
    final phone = _contactController.text.trim().isEmpty ? 'Phone N/A' : _contactController.text.trim();
    final desc = _shortDescController.text.trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF072E33),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Color(0xFF0E525B), width: 1.5),
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E525B),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('🏪', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shopName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_selectedCategory  •  Visible within $_selectedVisibilityKm',
                        style: const TextStyle(color: Color(0xFF90B4B6), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF0E525B)),
            const SizedBox(height: 12),
            _buildPreviewDetailRow('📍 Address', address),
            const SizedBox(height: 8),
            _buildPreviewDetailRow('📞 Contact', '$phone (${_sameNumberOnWhatsApp ? 'WhatsApp Enabled' : 'Calls Only'})'),
            const SizedBox(height: 8),
            _buildPreviewDetailRow('🕒 Timings', '$_openingTime - $_closingTime'),
            const SizedBox(height: 8),
            _buildPreviewDetailRow('🚚 Delivery', _homeDeliveryEnabled ? 'Home delivery available' : 'In-store pickup only'),
            const SizedBox(height: 8),
            _buildPreviewDetailRow('💳 Payments', _selectedPaymentMethods.join(', ')),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Description', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(desc, style: const TextStyle(color: Color(0xFF90B4B6), fontSize: 13)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF90B4B6), fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
