import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/bazar_repository.dart';
import '../../../services/r2_storage_service.dart';
import '../../bazar/bazar_screen.dart';
import '../../../theme/app_colors.dart';
import '../../../core/widgets/safe_image.dart';

class MyProductsScreen extends StatefulWidget {
  final String currentUserHandle;
  final String? shopId;

  const MyProductsScreen({
    super.key,
    required this.currentUserHandle,
    this.shopId,
  });

  @override
  State<MyProductsScreen> createState() => _MyProductsScreenState();
}

class _MyProductsScreenState extends State<MyProductsScreen> {
  bool _isLoading = true;
  int _selectedFilterIndex = 0;
  List<BazarProduct> _allProducts = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final list = await BazarRepository.instance.fetchMyShopProducts();
      if (mounted) {
        setState(() {
          _allProducts = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<BazarProduct> get _activeProducts => _allProducts.where((p) => !p.isSold).toList();
  List<BazarProduct> get _outOfStockProducts => _allProducts.where((p) => p.isSold).toList();

  List<BazarProduct> get _displayedProducts =>
      _selectedFilterIndex == 0 ? _activeProducts : _outOfStockProducts;

  void _toggleProductStock(BazarProduct product, bool isNowActive) async {
    setState(() {
      product.isSold = !isNowActive;
    });

    await BazarRepository.instance.toggleProductStock(product.id, isNowActive);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNowActive
                ? '✅ "${product.title}" is now IN STOCK'
                : '⚠️ "${product.title}" marked OUT OF STOCK',
          ),
          backgroundColor: AppColors.textPrimary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showAddEditProductModal({BazarProduct? existing}) {
    final isEdit = existing != null;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final priceController = TextEditingController(text: existing != null ? '${existing.price}' : '');
    final descController = TextEditingController(text: existing?.description ?? '');
    String selectedCategory = existing?.category ?? 'General Store';
    String? localImagePath;
    String? currentImageUrl = existing?.imageUrl;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isEdit ? 'Edit Product' : 'Add New Product',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isEdit)
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: AppColors.error),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await BazarRepository.instance.deleteProduct(existing.id);
                            _loadProducts();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                      if (picked != null) {
                        setModalState(() {
                          localImagePath = picked.path;
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 110,
                      decoration: BoxDecoration(
                        color: AppColors.chipBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: localImagePath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(
                                File(localImagePath!),
                                fit: BoxFit.cover,
                              ),
                            )
                          : (currentImageUrl != null && currentImageUrl.isNotEmpty)
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: SafeImage(
                                    imageUrl: currentImageUrl,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined, color: AppColors.primary, size: 28),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Add product photo',
                                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                    ),
                                  ],
                                ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text('PRODUCT NAME', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.chipBg,
                      hintText: 'e.g., Vitamin C tabs 500mg',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text('PRICE (₹)', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.chipBg,
                      hintText: 'e.g., 180',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                      prefixText: '₹ ',
                      prefixStyle: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final title = titleController.text.trim();
                              final price = int.tryParse(priceController.text.trim()) ?? 0;
                              if (title.isEmpty || price <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter valid product name & price')),
                                );
                                return;
                              }

                              setModalState(() => isSubmitting = true);

                              String finalImageUrl = currentImageUrl ?? '';
                              if (localImagePath != null) {
                                final uploaded = await R2StorageService.uploadMedia(
                                  File(localImagePath!),
                                );
                                if (uploaded != null && uploaded.isNotEmpty) {
                                  finalImageUrl = uploaded;
                                }
                              }

                              if (isEdit) {
                                final updated = BazarProduct(
                                  id: existing.id,
                                  title: title,
                                  price: price,
                                  category: selectedCategory,
                                  distanceKm: existing.distanceKm,
                                  imageUrl: finalImageUrl,
                                  sellerHandle: widget.currentUserHandle,
                                  location: existing.location,
                                  description: descController.text.trim(),
                                  viewsCount: existing.viewsCount,
                                  chatsCount: existing.chatsCount,
                                  isSold: existing.isSold,
                                );
                                await BazarRepository.instance.addProduct(updated);
                              } else {
                                await BazarRepository.instance.createListing(
                                  title: title,
                                  price: price,
                                  description: descController.text.trim().isNotEmpty ? descController.text.trim() : title,
                                  category: selectedCategory,
                                  condition: 'New',
                                  location: 'Vadodara',
                                  imageUrl: finalImageUrl,
                                );
                              }

                              if (mounted && ctx.mounted) {
                                Navigator.of(ctx).pop();
                                _loadProducts();
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              isEdit ? 'Save Changes' : '+ Add Product',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getCategoryEmoji(String title, String category) {
    final lower = title.toLowerCase();
    if (lower.contains('tab') || lower.contains('capsule') || lower.contains('vitamin') || lower.contains('med')) return '💊';
    if (lower.contains('kit') || lower.contains('aid') || lower.contains('bandage')) return '🩹';
    if (lower.contains('thermometer') || lower.contains('digital') || lower.contains('meter')) return '🌡️';
    if (lower.contains('sanit') || lower.contains('hand') || lower.contains('wash') || lower.contains('soap')) return '🧴';
    if (lower.contains('mask')) return '😷';
    if (category == 'Bakery') return '🥐';
    if (category == 'Kirana') return '🛒';
    return '📦';
  }

  @override
  Widget build(BuildContext context) {
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
          'My products',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      _buildFilterChip(
                        label: 'Active (${_activeProducts.length})',
                        isSelected: _selectedFilterIndex == 0,
                        onTap: () => setState(() => _selectedFilterIndex = 0),
                      ),
                      const SizedBox(width: 10),
                      _buildFilterChip(
                        label: 'Out of stock (${_outOfStockProducts.length})',
                        isSelected: _selectedFilterIndex == 1,
                        onTap: () => setState(() => _selectedFilterIndex = 1),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                Expanded(
                  child: _displayedProducts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _selectedFilterIndex == 0 ? '📦' : '✅',
                                style: const TextStyle(fontSize: 44),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _selectedFilterIndex == 0
                                    ? 'No active products'
                                    : 'No out-of-stock products',
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedFilterIndex == 0
                                    ? 'Tap "+ Add product" below to list your first item!'
                                    : 'All your items are currently in stock.',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 90),
                          itemCount: _displayedProducts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final product = _displayedProducts[index];
                            final isInStock = !product.isSold;
                            final emoji = _getCategoryEmoji(product.title, product.category);

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: AppColors.divider,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: AppColors.chipBg,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Center(
                                      child: product.imageUrl.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(14),
                                              child: SafeImage(
                                                imageUrl: product.imageUrl,
                                                width: 52,
                                                height: 52,
                                                fit: BoxFit.cover,
                                                errorWidget: Text(
                                                  emoji,
                                                  style: const TextStyle(fontSize: 24),
                                                ),
                                              ),
                                            )
                                          : Text(
                                              emoji,
                                              style: const TextStyle(fontSize: 24),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.title,
                                          style: TextStyle(
                                            color: isInStock ? AppColors.textPrimary : AppColors.textMuted,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          isInStock
                                              ? '₹${product.price} · ${product.viewsCount > 0 ? product.viewsCount : 40} views'
                                              : 'Out of stock',
                                          style: TextStyle(
                                            color: isInStock ? AppColors.textMuted : AppColors.error,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  Transform.scale(
                                    scale: 0.85,
                                    child: Switch(
                                      value: isInStock,
                                      onChanged: (val) => _toggleProductStock(product, val),
                                      activeTrackColor: AppColors.primary,
                                      activeThumbColor: Colors.white,
                                      inactiveTrackColor: AppColors.chipBg,
                                      inactiveThumbColor: AppColors.textMuted,
                                    ),
                                  ),

                                  const SizedBox(width: 4),

                                  GestureDetector(
                                    onTap: () => _showAddEditProductModal(existing: product),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: AppColors.chipBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.edit,
                                          color: AppColors.textPrimary,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        color: AppColors.surface,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            onPressed: () => _showAddEditProductModal(),
            child: const Text(
              '+ Add product',
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

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.chipBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontSize: 13.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
