import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/bazar_repository.dart';
import '../../services/r2_storage_service.dart';
import '../../theme/app_colors.dart';
import 'bazar_screen.dart';

class CreateBazarListingScreen extends StatefulWidget {
  final BazarProduct? initialProduct;

  const CreateBazarListingScreen({super.key, this.initialProduct});

  @override
  State<CreateBazarListingScreen> createState() => _CreateBazarListingScreenState();
}

class _CreateBazarListingScreenState extends State<CreateBazarListingScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  final List<String> _pickedImagePaths = [];
  bool _isPickingImage = false;

  String _selectedCategory = 'Electronics';
  String _selectedCondition = 'Used';
  String _selectedLocation = 'Visible within 2 km';
  bool _isPublishing = false;

  final List<Map<String, String>> _categories = [
    {'name': 'Furniture', 'icon': '🪑'},
    {'name': 'Electronics', 'icon': '📱'},
    {'name': 'Clothes', 'icon': '👗'},
    {'name': 'Home food', 'icon': '🍰'},
    {'name': 'Books', 'icon': '📚'},
    {'name': 'Other', 'icon': '💬'},
  ];

  final List<String> _locationOptions = [
    'Visible within 2 km',
    'Visible within 5 km',
    'Visible within 10 km',
    'All Vadodara',
  ];

  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    if (widget.initialProduct != null) {
      final product = widget.initialProduct!;
      _titleController.text = product.title;
      _priceController.text = product.price.toString();
      _selectedCategory = product.category;
      if (!_categories.any((c) => c['name'] == _selectedCategory)) {
        _selectedCategory = 'Electronics';
      }
      _existingImageUrl = product.imageUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_pickedImagePaths.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Maximum 5 photos/videos allowed.'),
          backgroundColor: AppColors.textPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      setState(() => _isPickingImage = true);
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (picked != null) {
        setState(() {
          _pickedImagePaths.add(picked.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  void _removeImage(int index) {
    setState(() {
      _pickedImagePaths.removeAt(index);
    });
  }

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Visibility Radius',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            ..._locationOptions.map((opt) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    opt == _selectedLocation
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: opt == _selectedLocation ? AppColors.primary : AppColors.textMuted,
                  ),
                  title: Text(
                    opt,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                  ),
                  onTap: () {
                    setState(() {
                      _selectedLocation = opt;
                    });
                    Navigator.pop(ctx);
                  },
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _publishListing() async {
    final title = _titleController.text.trim();
    final priceStr = _priceController.text.replaceAll(',', '').trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a title for your listing.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (priceStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a price.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final price = int.tryParse(priceStr) ?? 0;

    setState(() => _isPublishing = true);

    String imageUrl = _existingImageUrl ?? '';
    if (_pickedImagePaths.isNotEmpty) {
      try {
        final file = File(_pickedImagePaths.first);
        if (await file.exists()) {
          final uploaded = await R2StorageService.uploadImage(file);
          if (uploaded != null && uploaded.isNotEmpty) {
            imageUrl = uploaded;
          } else {
            imageUrl = _pickedImagePaths.first;
          }
        }
      } catch (e) {
        debugPrint('[CreateBazarListingScreen] Image upload error: $e');
        imageUrl = _pickedImagePaths.first;
      }
    }

    if (widget.initialProduct != null) {
      final updated = await BazarRepository.instance.updateListing(
        id: widget.initialProduct!.id,
        title: title,
        price: price,
        description: 'Condition: $_selectedCondition. Visibility: $_selectedLocation.',
        category: _selectedCategory,
        condition: _selectedCondition,
        location: _selectedLocation,
        imageUrl: imageUrl,
      );
      if (mounted) {
        setState(() => _isPublishing = false);
        if (updated) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFFFEF3C7), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Listing updated successfully!',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        }
        Navigator.pop(context, true);
      }
      return;
    }

    final newProduct = await BazarRepository.instance.createListing(
      title: title,
      price: price,
      description: 'Condition: $_selectedCondition. Visibility: $_selectedLocation.',
      category: _selectedCategory,
      condition: _selectedCondition,
      location: _selectedLocation,
      imageUrl: imageUrl,
    );

    if (mounted) {
      if (newProduct != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                Icon(
                  imageUrl.isNotEmpty ? Icons.star_rounded : Icons.check_circle_rounded,
                  color: const Color(0xFFFEF3C7),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  imageUrl.isNotEmpty ? 'Listed · +10 pts' : 'Item listed successfully!',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      }
      Navigator.pop(context, newProduct);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
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
          widget.initialProduct != null ? 'Edit listing' : 'Sell an item',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('PHOTOS & VIDEO · UP TO 5', style: labelStyle),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 13, color: Color(0xFFD97706)),
                      SizedBox(width: 3),
                      Text(
                        '+10 pts (photo required)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 76,
                      height: 76,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider, width: 1.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isPickingImage)
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                                strokeWidth: 2,
                              ),
                            )
                          else ...[
                            Icon(Icons.add_rounded, color: AppColors.primary, size: 24),
                            const SizedBox(height: 2),
                            Text(
                              'Add',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty)
                    Stack(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BazarProduct.buildProductImage(
                              _existingImageUrl!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 14,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _existingImageUrl = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                  ..._pickedImagePaths.asMap().entries.map((entry) {
                    final index = entry.key;
                    final path = entry.value;
                    return Stack(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                            image: DecorationImage(
                              image: FileImage(File(path)),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 14,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Text('TITLE', style: labelStyle),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _titleController,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Item title (e.g. Wooden Table)',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 16),
                  border: InputBorder.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            Text('PRICE', style: labelStyle),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '₹',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        hintText: '7,500',
                        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 16),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Text('CATEGORY', style: labelStyle),
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
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.divider,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          cat['icon']!,
                          style: const TextStyle(fontSize: 15),
                        ),
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

            Text('CONDITION', style: labelStyle),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.chipBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCondition = 'New';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedCondition == 'New' ? AppColors.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _selectedCondition == 'New'
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'New',
                          style: TextStyle(
                            color: _selectedCondition == 'New' ? AppColors.textPrimary : AppColors.textMuted,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCondition = 'Used';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedCondition == 'Used' ? AppColors.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _selectedCondition == 'Used'
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Used',
                          style: TextStyle(
                            color: _selectedCondition == 'Used' ? AppColors.textPrimary : AppColors.textMuted,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Text('LOCATION', style: labelStyle),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showLocationPicker,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    const Text('📍', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$_selectedLocation  ▼',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Text('PREVIEW', style: labelStyle),
            const SizedBox(height: 10),
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
                onPressed: _isPublishing ? null : _publishListing,
                child: _isPublishing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        widget.initialProduct != null ? 'Save changes' : 'Publish listing',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
