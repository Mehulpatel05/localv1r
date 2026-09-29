import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'create_bazar_listing_screen.dart';
import 'shop_detail_screen.dart';
import '../chat/personal_chat_screen.dart';
import '../../core/models/user_profile.dart';
import '../../services/bazar_repository.dart';
import '../../services/auth_service.dart';

class BazarProduct {
  final String id;
  final String title;
  final int price;
  final String category;
  final double distanceKm;
  final String imageUrl;
  final String sellerHandle;
  final String location;
  final String description;
  final int viewsCount;
  final int chatsCount;
  bool isSold;
  final DateTime createdAt;

  BazarProduct({
    required this.id,
    required this.title,
    required this.price,
    required this.category,
    required this.distanceKm,
    required this.imageUrl,
    required this.sellerHandle,
    required this.location,
    required this.description,
    this.viewsCount = 0,
    this.chatsCount = 0,
    this.isSold = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'price': price,
        'category': category,
        'distanceKm': distanceKm,
        'imageUrl': imageUrl,
        'sellerHandle': sellerHandle,
        'location': location,
        'description': description,
        'viewsCount': viewsCount,
        'chatsCount': chatsCount,
        'isSold': isSold,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BazarProduct.fromJson(Map<String, dynamic> json) {
    String img = (json['imageUrl'] as String?) ?? '';
    if (img.isEmpty && json['imageUrls'] is List && (json['imageUrls'] as List).isNotEmpty) {
      img = (json['imageUrls'] as List).first.toString();
    }
    if (img.isEmpty && json['image_urls_json'] is String) {
      try {
        final decoded = jsonDecode(json['image_urls_json']);
        if (decoded is List && decoded.isNotEmpty) {
          img = decoded.first.toString();
        }
      } catch (_) {}
    }

    final sHandle = (json['sellerHandle'] ?? json['seller_handle'] ?? '') as String;
    final views = json['viewsCount'] ?? json['views_count'] ?? 0;
    final chats = json['chatsCount'] ?? json['chats_count'] ?? 0;
    final isActive = json['is_active'];
    final isSold = json['isSold'] ?? (isActive != null ? isActive == 0 : false);

    return BazarProduct(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      price: json['price'] is num
          ? (json['price'] as num).toInt()
          : (int.tryParse(json['price']?.toString() ?? '0') ?? 0),
      category: (json['category'] ?? 'Other').toString(),
      distanceKm: json['distanceKm'] is num
          ? (json['distanceKm'] as num).toDouble()
          : (json['distance_km'] is num ? (json['distance_km'] as num).toDouble() : 0.8),
      imageUrl: img,
      sellerHandle: sHandle,
      location: (json['location'] ?? 'Vadodara').toString(),
      description: (json['description'] ?? '').toString(),
      viewsCount: views is num ? views.toInt() : 0,
      chatsCount: chats is num ? chats.toInt() : 0,
      isSold: isSold == true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : (json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now()),
    );
  }

  static Widget buildProductImage(
    String imageUrl, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    IconData fallbackIcon = Icons.storefront_rounded,
    double fallbackIconSize = 36,
  }) {
    if (imageUrl.trim().isEmpty) {
      return Container(
        width: width,
        height: height,
        color: const Color(0xFF0E525B),
        child: Center(
          child: Icon(fallbackIcon, color: Colors.white54, size: fallbackIconSize),
        ),
      );
    }

    final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    if (!isNetwork) {
      try {
        final file = File(imageUrl);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: fit,
            width: width,
            height: height,
            errorBuilder: (ctx, err, stack) => Container(
              width: width,
              height: height,
              color: const Color(0xFF0E525B),
              child: Center(
                child: Icon(fallbackIcon, color: Colors.white54, size: fallbackIconSize),
              ),
            ),
          );
        }
      } catch (_) {}
    }

    return Image.network(
      imageUrl,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (ctx, err, stack) => Container(
        width: width,
        height: height,
        color: const Color(0xFF0E525B),
        child: Center(
          child: Icon(fallbackIcon, color: Colors.white54, size: fallbackIconSize),
        ),
      ),
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: const Color(0xFF0E525B),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }
}

class BazarScreen extends StatefulWidget {
  final bool initialShowMyListings;
  final String currentUserHandle;

  const BazarScreen({
    super.key,
    this.initialShowMyListings = false,
    this.currentUserHandle = '',
  });

  @override
  State<BazarScreen> createState() => _BazarScreenState();
}

class _BazarScreenState extends State<BazarScreen> {
  late bool _showMyListings;
  String _selectedCategory = 'All';
  String _myListingsTab = 'Active'; // 'Active' or 'Sold'
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<String> _categories = [
    'All',
    'Furniture',
    'Electronics',
    'Clothes',
    'Home food',
    'Books',
    'Other',
  ];

  Future<void> _openPostScreen() async {
    final newProduct = await Navigator.push<BazarProduct>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateBazarListingScreen(),
      ),
    );

    if (newProduct != null) {
      setState(() {
        _showMyListings = true;
        _myListingsTab = 'Active';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF072E33),
            content: Text('🎉 Listed "${newProduct.title}" on Bazaar!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<BazarProduct> _allProducts = [];
  List<LocalShop> _localShops = [];
  String _activeHandle = '';

  @override
  void initState() {
    super.initState();
    _showMyListings = widget.initialShowMyListings;
    _activeHandle = widget.currentUserHandle;
    _resolveActiveHandle();

    BazarRepository.instance.addListener(_onBazarRepoChanged);
    _initBazarData();
  }

  Future<void> _resolveActiveHandle() async {
    if (_activeHandle.isEmpty) {
      final h = await AuthService.instance.getUserHandle();
      if (mounted && h != null && h.isNotEmpty) {
        setState(() {
          _activeHandle = h;
        });
      }
    }
  }

  Future<void> _initBazarData() async {
    await BazarRepository.instance.init();
    _onBazarRepoChanged();
  }

  void _onBazarRepoChanged() {
    if (!mounted) return;
    setState(() {
      final seenIds = <String>{};
      final uniqueProducts = <BazarProduct>[];
      for (final p in BazarRepository.instance.products) {
        if (seenIds.add(p.id)) {
          uniqueProducts.add(p);
        }
      }
      _allProducts = uniqueProducts;
      _localShops = List.from(BazarRepository.instance.shops);
    });
  }

  @override
  void dispose() {
    BazarRepository.instance.removeListener(_onBazarRepoChanged);
    _searchController.dispose();
    super.dispose();
  }

  List<BazarProduct> get _filteredProducts {
    return _allProducts.where((product) {
      // Exclude items marked as sold from general browse
      if (product.isSold) return false;

      // Category filter
      if (_selectedCategory != 'All' && product.category != _selectedCategory) {
        return false;
      }

      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = product.title.toLowerCase().contains(q);
        final matchCat = product.category.toLowerCase().contains(q);
        final matchDesc = product.description.toLowerCase().contains(q);
        return matchTitle || matchCat || matchDesc;
      }

      return true;
    }).toList();
  }

  List<BazarProduct> get _userMyListings {
    final active = (_activeHandle.isNotEmpty ? _activeHandle : widget.currentUserHandle)
        .replaceAll('@', '')
        .trim()
        .toLowerCase();
    return _allProducts.where((p) {
      final seller = p.sellerHandle.replaceAll('@', '').trim().toLowerCase();
      if (active.isNotEmpty) {
        return seller == active || seller == 'me' || seller.contains(active);
      }
      return seller == 'me';
    }).where((p) {
      if (_myListingsTab == 'Active') {
        return !p.isSold;
      } else {
        return p.isSold;
      }
    }).toList();
  }

  void _toggleMarkAsSold(BazarProduct product) {
    setState(() {
      product.isSold = !product.isSold;
    });

    final statusMsg = product.isSold
        ? 'Item marked as Sold!'
        : 'Item relisted as Active!';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF072E33),
        content: Text(
          statusMsg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _openProductDetail(BazarProduct product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildProductDetailSheet(product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    final showBackButton = canPop || _showMyListings;

    return PopScope(
      canPop: !_showMyListings && canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showMyListings) {
          setState(() {
            _showMyListings = false;
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                  onPressed: () {
                    if (_showMyListings) {
                      setState(() {
                        _showMyListings = false;
                      });
                    } else if (canPop) {
                      Navigator.pop(context);
                    }
                  },
                )
              : null,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
                decoration: const InputDecoration(
                  hintText: 'Search products in Bazaar...',
                  hintStyle: TextStyle(color: Color(0xFF90B4B6), fontSize: 15),
                  border: InputBorder.none,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _showMyListings ? 'My Listings' : 'Bazaar',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Near Alkapuri, Vadodara',
                    style: TextStyle(
                      color: Color(0xFF90B4B6),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
        actions: [
          if (!_showMyListings)
            IconButton(
              icon: Icon(
                _isSearching ? Icons.close : Icons.search_rounded,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = '';
                    _searchController.clear();
                  }
                });
              },
            ),
          // Toggle View Action Button (My Listings vs Browse)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF072E33),
                side: const BorderSide(color: Color(0xFF0E525B)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              icon: Icon(
                _showMyListings ? Icons.storefront_rounded : Icons.shopping_bag_outlined,
                size: 16,
                color: Colors.white,
              ),
              label: Text(
                _showMyListings ? 'Bazaar' : 'My Listings',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              onPressed: () {
                setState(() {
                  _showMyListings = !_showMyListings;
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 4,
        onPressed: _openPostScreen,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Post Item',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      body: _showMyListings ? _buildMyListingsView() : _buildBrowseBazarView(),
    ),
  );
}

  // --- BROWSE BAZAAR VIEW ---
  Widget _buildBrowseBazarView() {
    final products = _filteredProducts;

    return RefreshIndicator(
      onRefresh: () => BazarRepository.instance.fetchListings(),
      color: Colors.white,
      backgroundColor: const Color(0xFF072E33),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Horizontal Filter Chips
          Container(
            height: 48,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: Colors.white,
                    backgroundColor: const Color(0xFF072E33),
                    side: BorderSide(
                      color: isSelected ? Colors.white : const Color(0xFF0E525B),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    showCheckmark: false,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategory = cat;
                        });
                      }
                    },
                  ),
                );
              },
            ),
          ),

          // Local shops near you Section (Matching Image 1: media_1790655154584.png)
          _buildLocalShopsSection(),

          // Section Header: Items for sale
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Items for sale',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // 2-Column Product Grid
          products.isEmpty
              ? _buildEmptyState('No products found matching your search.')
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _buildProductCard(product);
                  },
                ),
        ],
      ),
    ),
  );
}

  Widget _buildLocalShopsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Local shops near you',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_localShops.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShopDetailScreen(shop: _localShops.first),
                      ),
                    );
                  },
                  child: const Text(
                    'See all >',
                    style: TextStyle(
                      color: Color(0xFF90B4B6),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _localShops.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF072E33),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF0E525B)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.storefront_rounded, color: Color(0xFF90B4B6), size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No local shops registered near you yet.',
                          style: TextStyle(color: Color(0xFF90B4B6), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : SizedBox(
                height: 104,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _localShops.length,
                  itemBuilder: (context, index) {
                    final shop = _localShops[index];
                    return _buildLocalShopAvatarItem(shop);
                  },
                ),
              ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildLocalShopAvatarItem(LocalShop shop) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ShopDetailScreen(shop: shop),
          ),
        );
      },
      child: Container(
        width: 76,
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: const Color(0xFF072E33),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF0E525B),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    shop.categoryIcon,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                if (shop.isVerified)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.black,
                        size: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              shop.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Product Card in Grid
  Widget _buildProductCard(BazarProduct product) {
    return GestureDetector(
      onTap: () => _openProductDetail(product),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF072E33),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF0E525B),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Container with Network Image & fallback
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BazarProduct.buildProductImage(
                      product.imageUrl,
                      fit: BoxFit.cover,
                      fallbackIcon: Icons.storefront_rounded,
                      fallbackIconSize: 40,
                    ),
                  ),

                  // Distance Tag
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${product.distanceKm} km',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Card Body
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '₹${product.price}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E525B),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          product.category,
                          style: const TextStyle(
                            color: Color(0xFF90B4B6),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- MY LISTINGS VIEW ---
  Widget _buildMyListingsView() {
    final listings = _userMyListings;
    final activeHandle = widget.currentUserHandle.replaceAll('@', '').trim().toLowerCase();
    final allUserListings = _allProducts.where((p) {
      final seller = p.sellerHandle.replaceAll('@', '').trim().toLowerCase();
      if (activeHandle.isNotEmpty) {
        return seller == activeHandle || seller == 'me';
      }
      return seller == 'me';
    }).toList();

    final activeCount = allUserListings.where((p) => !p.isSold).length;
    final soldCount = allUserListings.where((p) => p.isSold).length;

    return Column(
      children: [
        // Tabs: Active / Sold
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF072E33),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF0E525B)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _myListingsTab = 'Active';
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _myListingsTab == 'Active' ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Active ($activeCount)',
                      style: TextStyle(
                        color: _myListingsTab == 'Active' ? Colors.black : const Color(0xFF90B4B6),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _myListingsTab = 'Sold';
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _myListingsTab == 'Sold' ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Sold ($soldCount)',
                      style: TextStyle(
                        color: _myListingsTab == 'Sold' ? Colors.black : const Color(0xFF90B4B6),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // List of My Listings matching Screenshot 2 specs
        Expanded(
          child: listings.isEmpty
              ? _buildEmptyState(_myListingsTab == 'Active'
                  ? 'You have no active listings. Tap "+ Sell Item" to list a product!'
                  : 'No sold items yet.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  itemCount: listings.length,
                  itemBuilder: (context, index) {
                    final item = listings[index];
                    return _buildMyListingCard(item);
                  },
                ),
        ),
      ],
    );
  }

  // Card for My Listing (With View / Chat Count and Mark as Sold button)
  Widget _buildMyListingCard(BazarProduct item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF072E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0E525B)),
      ),
      child: Row(
        children: [
          // Image Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 80,
              height: 80,
              child: BazarProduct.buildProductImage(
                item.imageUrl,
                fit: BoxFit.cover,
                fallbackIcon: Icons.shopping_bag_outlined,
                fallbackIconSize: 32,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${item.price}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),

                // Stats: 38 views · 3 chats
                Text(
                  '${item.viewsCount} views  •  ${item.chatsCount} chats',
                  style: const TextStyle(
                    color: Color(0xFF90B4B6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Mark as Sold / Relist Button
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: item.isSold ? const Color(0xFF0E525B) : Colors.white,
              foregroundColor: item.isSold ? Colors.white : Colors.black,
              side: BorderSide(
                color: item.isSold ? const Color(0xFF0E525B) : Colors.white,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _toggleMarkAsSold(item),
            child: Text(
              item.isSold ? 'Relist' : 'Mark as Sold',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Product Detail Bottom Sheet
  Widget _buildProductDetailSheet(BazarProduct product) {
    return Container(
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

          // Product Image Banner
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: BazarProduct.buildProductImage(
                product.imageUrl,
                fit: BoxFit.cover,
                fallbackIcon: Icons.storefront_rounded,
                fallbackIconSize: 50,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title & Price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '₹${product.price}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Location & Distance
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: Color(0xFF90B4B6), size: 16),
              const SizedBox(width: 4),
              Text(
                '${product.location} (${product.distanceKm} km away)',
                style: const TextStyle(color: Color(0xFF90B4B6), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Description
          const Text(
            'Description',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            product.description,
            style: const TextStyle(
              color: Color(0xFF90B4B6),
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Chat / Contact Seller Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
              label: Text(
                'Chat with Seller (${product.sellerHandle.displayHandle})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                Navigator.pop(context);
                final myHandle = await AuthService.instance.getUserHandle() ?? '@me';
                final cleanMy = myHandle.replaceAll('@', '').trim().toLowerCase();
                final cleanSeller = product.sellerHandle.replaceAll('@', '').trim().toLowerCase();

                if (cleanMy.isNotEmpty && cleanSeller.isNotEmpty && cleanMy == cleanSeller) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Color(0xFF072E33),
                      content: Text('ℹ️ This is your own product listing.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                // Record listing chat inquiry in background
                BazarRepository.instance.recordListingChatInquiry(product.id);

                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PersonalChatScreen(
                      currentUserHandle: myHandle,
                      partnerHandle: product.sellerHandle,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF072E33),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.storefront_rounded,
                color: Color(0xFF90B4B6),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF90B4B6),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
