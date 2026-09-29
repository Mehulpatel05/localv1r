import 'package:flutter/material.dart';
import '../../../services/bazar_repository.dart';
import '../../bazar/shop_detail_screen.dart';

class EditShopDetailsScreen extends StatefulWidget {
  final LocalShop shop;

  const EditShopDetailsScreen({
    super.key,
    required this.shop,
  });

  @override
  State<EditShopDetailsScreen> createState() => _EditShopDetailsScreenState();
}

class _EditShopDetailsScreenState extends State<EditShopDetailsScreen> {
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _descController;
  late String _selectedCategory;
  late bool _sameWhatsapp;
  late bool _homeDelivery;
  late TimeOfDay _openingTime;
  late TimeOfDay _closingTime;
  bool _isSaving = false;

  final List<Map<String, String>> _categories = [
    {'name': 'Pharmacy', 'icon': '💊'},
    {'name': 'Kirana', 'icon': '🛒'},
    {'name': 'Bakery', 'icon': '🥐'},
    {'name': 'Fashion', 'icon': '👗'},
    {'name': 'Electronics', 'icon': '📱'},
    {'name': 'Cafe', 'icon': '☕'},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.shop.name);
    _addressController = TextEditingController(text: widget.shop.location);
    _phoneController = TextEditingController(text: widget.shop.phone);
    _descController = TextEditingController(text: widget.shop.aboutText);
    _selectedCategory = widget.shop.category.isNotEmpty ? widget.shop.category : 'Pharmacy';
    _sameWhatsapp = widget.shop.sameWhatsapp;
    _homeDelivery = widget.shop.homeDelivery;

    // Parse timings
    _openingTime = const TimeOfDay(hour: 9, minute: 0);
    _closingTime = const TimeOfDay(hour: 21, minute: 0);
    if (widget.shop.timings.contains('-')) {
      final parts = widget.shop.timings.split('-');
      if (parts.length == 2) {
        _openingTime = _parseTimeOfDay(parts[0].trim()) ?? _openingTime;
        _closingTime = _parseTimeOfDay(parts[1].trim()) ?? _closingTime;
      }
    }
  }

  TimeOfDay? _parseTimeOfDay(String timeStr) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPm = clean.contains('PM');
      final isAm = clean.contains('AM');
      final timeDigits = clean.replaceAll(RegExp(r'[^\d:]'), '');
      final parts = timeDigits.split(':');
      if (parts.isNotEmpty) {
        int hour = int.parse(parts[0]);
        int min = parts.length > 1 ? int.parse(parts[1]) : 0;
        if (isPm && hour < 12) hour += 12;
        if (isAm && hour == 12) hour = 0;
        return TimeOfDay(hour: hour, minute: min);
      }
    } catch (_) {}
    return null;
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isOpening}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpening ? _openingTime : _closingTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF14B8A6),
              onPrimary: Colors.black,
              surface: Color(0xFF0A2E33),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isOpening) {
          _openingTime = picked;
        } else {
          _closingTime = picked;
        }
      });
    }
  }

  Future<void> _saveChanges() async {
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();

    if (name.isEmpty || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid Shop Name and Address'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final catObj = _categories.firstWhere(
      (c) => c['name'] == _selectedCategory,
      orElse: () => {'name': _selectedCategory, 'icon': '🏪'},
    );

    final timingsStr = '${_formatTimeOfDay(_openingTime)} - ${_formatTimeOfDay(_closingTime)}';

    final updated = LocalShop(
      id: widget.shop.id,
      ownerHandle: widget.shop.ownerHandle,
      name: name,
      category: _selectedCategory,
      categoryIcon: catObj['icon'] ?? '🏪',
      location: address,
      distanceKm: widget.shop.distanceKm,
      isVerified: widget.shop.isVerified,
      imageUrl: widget.shop.imageUrl,
      bannerUrl: widget.shop.bannerUrl,
      phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : widget.shop.phone,
      deliveryInfo: _homeDelivery ? 'Home delivery available' : 'In-store pickup only',
      timings: timingsStr,
      aboutText: _descController.text.trim(),
      isOpen: widget.shop.isOpen,
      sameWhatsapp: _sameWhatsapp,
      homeDelivery: _homeDelivery,
      viewsCount: widget.shop.viewsCount,
      chatsCount: widget.shop.chatsCount,
      ordersCount: widget.shop.ordersCount,
      status: widget.shop.status,
      products: widget.shop.products,
    );

    await BazarRepository.instance.updateShop(updated);

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Shop details updated successfully!'),
          backgroundColor: Color(0xFF0D5E56),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const cardBg = Color(0xFF0A2E33);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
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
        title: const Text(
          'Edit shop details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14.0),
            child: TextButton(
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. BASIC INFO SECTION
            const Text(
              'Basic info',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),

            const Text(
              'SHOP NAME',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF0F4E56)),
              ),
              child: TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: 'Enter shop name',
                  hintStyle: TextStyle(color: Color(0xFF64748B)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                ),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'CATEGORY',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),

            // Category Chips Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory.toLowerCase() == cat['name']!.toLowerCase();
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedCategory = cat['name']!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : cardBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isSelected ? Colors.white : const Color(0xFF0F4E56),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(cat['icon']!, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(
                              cat['name']!,
                              style: TextStyle(
                                color: isSelected ? Colors.black : Colors.white,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 28),

            // 2. LOCATION & CONTACT SECTION
            const Text(
              'Location & contact',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),

            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF0F4E56)),
              ),
              child: TextField(
                controller: _addressController,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                decoration: const InputDecoration(
                  hintText: 'Shop address, e.g. Shop 4, Alkapuri Main Road',
                  hintStyle: TextStyle(color: Color(0xFF64748B)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Same number on WhatsApp toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Same number on WhatsApp',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Transform.scale(
                  scale: 0.9,
                  child: Switch(
                    value: _sameWhatsapp,
                    onChanged: (val) => setState(() => _sameWhatsapp = val),
                    activeTrackColor: const Color(0xFF14B8A6),
                    activeThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFF1E293B),
                    inactiveThumbColor: Colors.grey,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // 3. TIMINGS & DELIVERY SECTION
            const Text(
              'Timings & delivery',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),

            // Opening & Closing Time Pickers Row
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickTime(isOpening: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF0F4E56)),
                      ),
                      child: Center(
                        child: Text(
                          _formatTimeOfDay(_openingTime),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickTime(isOpening: false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF0F4E56)),
                      ),
                      child: Center(
                        child: Text(
                          _formatTimeOfDay(_closingTime),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Home delivery toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Home delivery',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Transform.scale(
                  scale: 0.9,
                  child: Switch(
                    value: _homeDelivery,
                    onChanged: (val) => setState(() => _homeDelivery = val),
                    activeTrackColor: const Color(0xFF14B8A6),
                    activeThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFF1E293B),
                    inactiveThumbColor: Colors.grey,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        color: Colors.black,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            onPressed: _isSaving ? null : _saveChanges,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                  )
                : const Text(
                    'Save changes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
