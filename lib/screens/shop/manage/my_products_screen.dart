import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/bazar_repository.dart';
import '../../../services/r2_storage_service.dart';
import '../../bazar/bazar_screen.dart';

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
  int _selectedFilterIndex = 0; // 0 = Active, 1 = Out of stock
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
          backgroundColor: isNowActive ? const Color(0xFF0D5E56) : const Color(0xFF334155),
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
    String selectedCategory = existing?.category ?? 'Pharmacy';
    String? localImagePath;
    String? currentImageUrl = existing?.imageUrl;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF071B1E),
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
                        color: Colors.white24,
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isEdit)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await BazarRepository.instance.deleteProduct(existing.id);
                            _loadProducts();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Image Picker Row
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
                        color: const Color(0xFF0A2E33),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF0F4E56)),
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
                                  child: Image.network(
                                    currentImageUrl,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined, color: Color(0xFF2DD4BF), size: 28),
                                    SizedBox(height: 6),
                                    Text(
                                      'Add product photo',
                                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                    ),
                                  ],
                                ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Title field
                  const Text('PRODUCT NAME', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0A2E33),
                      hintText: 'e.g., Vitamin C tabs 500mg',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Price field
                  const Text('PRICE (₹)', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0A2E33),
                      hintText: 'e.g., 180',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                      prefixText: '₹ ',
                      prefixStyle: const TextStyle(color: Color(0xFF2DD4BF), fontWeight: FontWeight.bold),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
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
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
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
          'My products',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF14B8A6)))
          : Column(
              children: [
                const SizedBox(height: 8),

                // Filter Chips Row: Active (X) | Out of stock (Y)
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

                // Products List
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
                                style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedFilterIndex == 0
                                    ? 'Tap "+ Add product" below to list your first item!'
                                    : 'All your items are currently in stock.',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
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
                                color: cardBg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isInStock ? const Color(0xFF0F4E56) : const Color(0xFF1F2937),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Product Photo or Emoji Container
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF062327),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Center(
                                      child: product.imageUrl.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(14),
                                              child: Image.network(
                                                product.imageUrl,
                                                width: 52,
                                                height: 52,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => Text(
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

                                  // Product Title & Subtitle (Price + Views or Out of stock)
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.title,
                                          style: TextStyle(
                                            color: isInStock ? Colors.white : const Color(0xFF94A3B8),
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
                                            color: isInStock ? const Color(0xFF94A3B8) : const Color(0xFFF87171),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Stock Switch Toggle
                                  Transform.scale(
                                    scale: 0.85,
                                    child: Switch(
                                      value: isInStock,
                                      onChanged: (val) => _toggleProductStock(product, val),
                                      activeTrackColor: const Color(0xFF14B8A6),
                                      activeThumbColor: Colors.white,
                                      inactiveTrackColor: const Color(0xFF1E293B),
                                      inactiveThumbColor: Colors.grey,
                                    ),
                                  ),

                                  const SizedBox(width: 4),

                                  // Edit Pencil Button
                                  GestureDetector(
                                    onTap: () => _showAddEditProductModal(existing: product),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF0F4E56),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.edit,
                                          color: Color(0xFFFDE047),
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
          color: isSelected ? Colors.white : const Color(0xFF0A2E33),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? Colors.white : const Color(0xFF0F4E56),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 13.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
