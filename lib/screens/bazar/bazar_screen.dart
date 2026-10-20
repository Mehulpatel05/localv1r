import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/location/location_service.dart';
import 'create_bazar_listing_screen.dart';
import 'shop_detail_screen.dart';
import '../chat/personal_chat_screen.dart';
import '../../services/bazar_repository.dart';
import '../../services/auth_service.dart';
import '../../core/services/name_cache_service.dart';
import '../../services/rewards_service.dart';
import '../rewards/boost_listing_screen.dart';
import '../rewards/shop_perks_screen.dart';
import '../../core/widgets/verified_badge.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/sliding_category_tab_bar.dart';
import '../../core/widgets/safe_image.dart';
import '../../core/services/badge_cache_service.dart';
import '../shop/register_shop_screen.dart';
import '../../theme/app_colors.dart';

class BazarProduct {
  final String id;
  final String title;
  final int price;
  final String category;
  final double distanceKm;
  final String imageUrl;
  final String sellerHandle;
  final String? sellerName;
  final String location;
  final String description;
  final int viewsCount;
  final int chatsCount;
  bool isSold;
  final bool isBoosted;
  final int boostHoursLeft;
  final bool isVerified;
  final String? authorBadge;
  final DateTime createdAt;

  BazarProduct({
    required this.id,
    required this.title,
    required this.price,
    required this.category,
    required this.distanceKm,
    required this.imageUrl,
    required this.sellerHandle,
    this.sellerName,
    required this.location,
    required this.description,
    this.viewsCount = 0,
    this.chatsCount = 0,
    this.isSold = false,
    this.isBoosted = false,
    this.boostHoursLeft = 0,
    this.isVerified = false,
    this.authorBadge,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get displaySellerName {
    return NameCacheService.instance.getDisplayName(sellerHandle, fallback: sellerName);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'price': price,
        'category': category,
        'distanceKm': distanceKm,
        'imageUrl': imageUrl,
        'sellerHandle': sellerHandle,
        'sellerName': sellerName,
        'location': location,
        'description': description,
        'viewsCount': viewsCount,
        'chatsCount': chatsCount,
        'isSold': isSold,
        'isBoosted': isBoosted,
        'boostHoursLeft': boostHoursLeft,
        'isVerified': isVerified,
        'authorBadge': authorBadge,
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
    final sName = (json['sellerDisplayName'] ?? json['sellerName'] ?? json['seller_display_name']) as String?;
    final cleanSellerName = (sName != null && sName.trim().isNotEmpty) ? sName.trim() : null;
    if (cleanSellerName != null && sHandle.isNotEmpty) {
      NameCacheService.instance.setCachedName(sHandle.replaceAll('@', ''), cleanSellerName);
    }

    final isVerified = json['isVerified'] == true || json['is_verified'] == 1;
    final authorBadge = (json['authorBadge'] ?? json['author_badge'] ?? json['badge']) as String?;
    if (sHandle.isNotEmpty) {
      BadgeCacheService.instance.setBadge(
        sHandle.replaceAll('@', ''),
        isVerified: isVerified,
        badgeText: authorBadge,
      );
    }

    final views = json['viewsCount'] ?? json['views_count'] ?? 0;
    final chats = json['chatsCount'] ?? json['chats_count'] ?? 0;
    final isActive = json['is_active'];
    final isSold = json['isSold'] ?? (isActive != null ? isActive == 0 : false);
    final isBoosted = json['is_boosted'] == true || json['isBoosted'] == true;
    final boostHours = json['boost_hours_left'] is num
        ? (json['boost_hours_left'] as num).toInt()
        : (json['boostHoursLeft'] is num ? (json['boostHoursLeft'] as num).toInt() : 0);

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
      sellerName: cleanSellerName,
      location: (json['location'] ?? 'Vadodara').toString(),
      description: (json['description'] ?? '').toString(),
      viewsCount: views is num ? views.toInt() : 0,
      chatsCount: chats is num ? chats.toInt() : 0,
      isSold: isSold == true,
      isBoosted: isBoosted,
      boostHoursLeft: boostHours,
      isVerified: isVerified,
      authorBadge: authorBadge,
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
        color: AppColors.chipBg,
        child: Center(
          child: Icon(fallbackIcon, color: AppColors.textMuted, size: fallbackIconSize),
        ),
      );
    }

    return SafeImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width ?? double.infinity,
      height: height,
      placeholder: Container(
        width: width,
        height: height,
        color: AppColors.chipBg,
        child: Center(
          child: Icon(fallbackIcon, color: AppColors.textMuted.withValues(alpha: 0.5), size: fallbackIconSize),
        ),
      ),
      errorWidget: Container(
        width: width,
        height: height,
        color: AppColors.chipBg,
        child: Center(
          child: Icon(fallbackIcon, color: AppColors.textMuted, size: fallbackIconSize),
        ),
      ),
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
  String _myListingsTab = 'Active';
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
        _allProducts.removeWhere((p) => p.id == newProduct.id);
        _allProducts.insert(0, newProduct);
        _showMyListings = true;
        _myListingsTab = 'Active';
      });

      RewardsService.instance.addPoints(10);
      unawaited(BazarRepository.instance.fetchListings());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.textPrimary,
            content: Text(
              RewardsService.isRewardsEnabled
                  ? '🎉 Listed "${newProduct.title}" on Bazaar! (+10 pts)'
                  : '🎉 Listed "${newProduct.title}" on Bazaar!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    await Future.wait([
      BazarRepository.instance.fetchListings(),
      BazarRepository.instance.fetchShops(),
    ]);
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
      _localShops = BazarRepository.instance.shops
          .where((s) => s.status == 'active')
          .toList();
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
      if (product.isSold) return false;

      if (_selectedCategory != 'All' && product.category != _selectedCategory) {
        return false;
      }

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
        backgroundColor: AppColors.textPrimary,
        content: Text(
          statusMsg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _confirmDeleteProduct(BazarProduct product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Listing',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${product.title}"? This item will be permanently removed.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await BazarRepository.instance.deleteProduct(product.id);
              if (mounted) {
                _onBazarRepoChanged();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Listing deleted successfully'),
                    backgroundColor: AppColors.textPrimary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
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
    final isPushedFromProfile = widget.initialShowMyListings;
    final canPop = Navigator.canPop(context);
    final showBackButton = isPushedFromProfile || _showMyListings || _isSearching;

    return PopScope(
      canPop: isPushedFromProfile
          ? !_isSearching && canPop
          : !_isSearching && !_showMyListings,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearching) {
          setState(() {
            _isSearching = false;
            _searchQuery = '';
            _searchController.clear();
          });
          return;
        }
        if (!isPushedFromProfile && _showMyListings) {
          setState(() {
            _showMyListings = false;
          });
          return;
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: showBackButton
              ? IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
                  onPressed: () {
                    if (_isSearching) {
                      setState(() {
                        _isSearching = false;
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    } else if (isPushedFromProfile) {
                      Navigator.pop(context);
                    } else if (_showMyListings) {
                      setState(() {
                        _showMyListings = false;
                      });
                    }
                  },
                )
              : null,
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search products in Bazaar...',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15),
                    border: InputBorder.none,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _showMyListings ? 'My Listings' : 'Bazaar',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final locService = context.watch<LocationService>();
                        final areaName = (locService.area?.name != null && locService.area!.name.trim().isNotEmpty)
                            ? locService.area!.name
                            : locService.city.name;
                        final cityName = locService.city.name;
                        final label = areaName == cityName ? cityName : '$areaName, $cityName';
                        return Text(
                          label,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ],
                ),
          actions: [
            if (!_showMyListings)
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.close : Icons.search_rounded,
                  color: AppColors.textPrimary,
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
            if (RewardsService.isRewardsEnabled)
              Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PressableScale(
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push(
                    PageRouteBuilder(
                      opaque: true,
                      transitionDuration: const Duration(milliseconds: 260),
                      reverseTransitionDuration: const Duration(milliseconds: 240),
                      pageBuilder: (_, animation, secondaryAnimation) => const ShopPerksScreen(),
                      transitionsBuilder: (_, animation, _, child) {
                        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                        return SlideTransition(
                          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved),
                          child: child,
                        );
                      },
                    ),
                  );
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: const Center(
                    child: ShopPerksLogo(size: 24),
                  ),
                ),
              ),
            ),
            if (!isPushedFromProfile)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: PressableScale(
                  onTap: () {
                    setState(() {
                      _showMyListings = !_showMyListings;
                      _isSearching = false;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _showMyListings ? AppColors.primary : AppColors.chipBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _showMyListings ? AppColors.primary : AppColors.divider,
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      _showMyListings ? Icons.storefront_rounded : Icons.shopping_bag_outlined,
                      size: 18,
                      color: _showMyListings ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
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

  Widget _buildBrowseBazarView() {
    final products = _filteredProducts;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          BazarRepository.instance.fetchListings(),
          BazarRepository.instance.fetchShops(),
        ]);
        _onBazarRepoChanged();
      },
      color: AppColors.primary,
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 42,
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SlidingCategoryTabBar(
                categories: _categories,
                selectedIndex: _categories.indexOf(_selectedCategory).clamp(0, _categories.length - 1),
                isScrollable: true,
                onSelected: (index) {
                  setState(() {
                    _selectedCategory = _categories[index];
                  });
                },
              ),
            ),

            _buildShopPerksBanner(),
            _buildLocalShopsSection(),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Items for sale',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            products.isEmpty
                ? _buildEmptyState('No products found matching your search.')
                : products.length == 1
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 88 + MediaQuery.paddingOf(context).bottom),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final cardWidth = (constraints.maxWidth - 20) / 3;
                            return Align(
                              alignment: Alignment.topLeft,
                              child: SizedBox(
                                width: cardWidth,
                                child: AspectRatio(
                                  aspectRatio: 0.72,
                                  child: _buildProductCard(products.first),
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 88 + MediaQuery.paddingOf(context).bottom),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
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
              Text(
                'Local shops near you',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_localShops.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    if (_localShops.length == 1) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ShopDetailScreen(shop: _localShops.first),
                        ),
                      );
                    } else {
                      _showAllShopsSheet(context);
                    }
                  },
                  child: Text(
                    'See all >',
                    style: TextStyle(
                      color: AppColors.primary,
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
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: AppColors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'No local shops registered near you yet.',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Own a shop in your neighbourhood?',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(builder: (_) => const RegisterShopScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Register free',
                            style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
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

  void _showAllShopsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
              Text(
                'All Local Shops',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _localShops.length,
                  separatorBuilder: (_, _) => Divider(color: AppColors.divider, height: 1),
                  itemBuilder: (context, index) {
                    final shop = _localShops[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      leading: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.divider, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: shop.imageUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(23),
                                child: SafeImage(
                                  imageUrl: shop.imageUrl,
                                  width: 46,
                                  height: 46,
                                  fit: BoxFit.cover,
                                  errorWidget: const Icon(
                                    Icons.storefront_rounded,
                                    color: AppColors.primary,
                                    size: 22,
                                  ),
                                ),
                              )
                            : (shop.categoryIcon.isNotEmpty &&
                                    shop.categoryIcon != '💊' &&
                                    shop.categoryIcon != '🏪')
                                ? Text(shop.categoryIcon, style: const TextStyle(fontSize: 22))
                                : const Icon(
                                    Icons.storefront_rounded,
                                    color: AppColors.primary,
                                    size: 22,
                                  ),
                      ),
                      title: Text(
                        shop.name,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        '${shop.category} • ${shop.location}',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: shop.isOpen ? AppColors.primarySoft : AppColors.errorSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          shop.isOpen ? 'OPEN' : 'CLOSED',
                          style: TextStyle(
                            color: shop.isOpen ? AppColors.primaryText : const Color(0xFFB3262A),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShopDetailScreen(shop: shop),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.divider,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: shop.imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(33),
                          child: SafeImage(
                            imageUrl: shop.imageUrl,
                            width: 66,
                            height: 66,
                            fit: BoxFit.cover,
                            errorWidget: const Icon(
                              Icons.storefront_rounded,
                              color: AppColors.primary,
                              size: 30,
                            ),
                          ),
                        )
                      : (shop.categoryIcon.isNotEmpty &&
                              shop.categoryIcon != '💊' &&
                              shop.categoryIcon != '🏪')
                          ? Text(
                              shop.categoryIcon,
                              style: const TextStyle(fontSize: 32),
                            )
                          : const Icon(
                              Icons.storefront_rounded,
                              color: AppColors.primary,
                              size: 30,
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
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
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
              style: TextStyle(
                color: AppColors.textPrimary,
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

  Widget _buildProductCard(BazarProduct product) {
    return GestureDetector(
      onTap: () => _openProductDetail(product),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.divider,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BazarProduct.buildProductImage(
                      product.imageUrl,
                      fit: BoxFit.cover,
                      fallbackIcon: Icons.storefront_rounded,
                      fallbackIconSize: 28,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${product.distanceKm} km',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (product.isBoosted)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFF59E0B),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 10,
                              color: Color(0xFFD97706),
                            ),
                            SizedBox(width: 1),
                            Text(
                              'Boost',
                              style: TextStyle(
                                color: Color(0xFFB45309),
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '₹${product.price}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          product.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SlidingCategoryTabBar(
            categories: [
              'Active ($activeCount)',
              'Sold ($soldCount)',
            ],
            selectedIndex: _myListingsTab == 'Active' ? 0 : 1,
            onSelected: (index) {
              setState(() {
                _myListingsTab = index == 0 ? 'Active' : 'Sold';
              });
            },
          ),
        ),
        if (_myListingsTab == 'Sold')
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '🏆 Top Seller Badge',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$soldCount/5 items',
                      style: const TextStyle(
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (soldCount / 5).clamp(0.0, 1.0),
                    backgroundColor: AppColors.chipBg,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  soldCount >= 5
                      ? '🎉 You unlocked the Top Seller badge!'
                      : 'Sell ${5 - soldCount} more ${5 - soldCount == 1 ? "item" : "items"} to unlock Top Seller badge',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                BazarRepository.instance.fetchListings(),
                BazarRepository.instance.fetchShops(),
              ]);
              _onBazarRepoChanged();
            },
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: listings.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 300,
                        child: _buildEmptyState(_myListingsTab == 'Active'
                            ? 'You have no active listings. Tap "+ Sell Item" to list a product!'
                            : 'No sold items yet.'),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 88 + MediaQuery.paddingOf(context).bottom),
                    itemCount: listings.length,
                    itemBuilder: (context, index) {
                      final item = listings[index];
                      return _buildMyListingCard(item);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildMyListingCard(BazarProduct item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
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

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${item.price}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),

                Text(
                  '${item.viewsCount} views  •  ${item.chatsCount} chats',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (RewardsService.isRewardsEnabled && !item.isSold) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEF3C7),
                    foregroundColor: const Color(0xFFB45309),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFFD97706)),
                  label: Text(
                    item.isBoosted ? 'Boosted (${item.boostHoursLeft}h)' : 'Boost',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  onPressed: item.isBoosted
                      ? null
                      : () async {
                          final res = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BoostListingScreen(
                                listingId: item.id,
                                listingTitle: item.title,
                                currentBalance: RewardsService.instance.summary?.balance ?? 0,
                              ),
                            ),
                          );
                          if (res == true && mounted) {
                            _initBazarData();
                          }
                        },
                ),
                const SizedBox(height: 6),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.chipBg,
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text(
                  'Edit',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateBazarListingScreen(initialProduct: item),
                    ),
                  );
                  if (res == true && mounted) {
                    _initBazarData();
                  }
                },
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: item.isSold ? AppColors.chipBg : AppColors.primarySoft,
                  foregroundColor: item.isSold ? AppColors.textPrimary : AppColors.primaryText,
                  side: BorderSide(
                    color: item.isSold ? AppColors.divider : AppColors.primarySoft,
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
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _confirmDeleteProduct(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Delete',
                        style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductDetailSheet(BazarProduct product) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

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

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '₹${product.price}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Icon(Icons.location_on_outlined, color: AppColors.textMuted, size: 16),
              const SizedBox(width: 4),
              Text(
                '${product.location} (${product.distanceKm} km away)',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.chipBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                UserAvatar(
                  handle: product.sellerHandle,
                  size: 36,
                  fontSize: 13.5,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              product.displaySellerName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          VerifiedBadge(
                            handle: product.sellerHandle,
                            isVerified: product.isVerified,
                            badgeText: product.authorBadge,
                            size: 14,
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      const Text(
                        'Seller',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Text(
            'Description',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            product.description,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
              label: Text(
                'Chat with Seller (${product.displaySellerName})',
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
                    SnackBar(
                      backgroundColor: AppColors.textPrimary,
                      content: const Text('ℹ️ This is your own product listing.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

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
              decoration: BoxDecoration(
                color: AppColors.chipBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.storefront_rounded,
                color: AppColors.textMuted,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopPerksBanner() {
    if (!RewardsService.isRewardsEnabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: PressableScale(
        onTap: () {
          Navigator.of(context, rootNavigator: true).push(
            PageRouteBuilder(
              opaque: true,
              transitionDuration: const Duration(milliseconds: 260),
              reverseTransitionDuration: const Duration(milliseconds: 240),
              pageBuilder: (_, animation, secondaryAnimation) => const ShopPerksScreen(),
              transitionsBuilder: (_, animation, _, child) {
                final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                return SlideTransition(
                  position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved),
                  child: child,
                );
              },
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const ShopPerksLogo(size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Shop Perks',
                          style: TextStyle(
                            color: Color(0xFF78350F),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'REWARDS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Redeem points for exclusive local discounts & coupons',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Color(0xFFD97706),
                  size: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShopPerksLogo extends StatelessWidget {
  final double size;

  const ShopPerksLogo({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(size * 0.28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD97706).withValues(alpha: 0.35),
                  blurRadius: size * 0.2,
                  offset: Offset(0, size * 0.08),
                ),
              ],
            ),
          ),
          Transform.rotate(
            angle: -0.1,
            child: Container(
              width: size * 0.65,
              height: size * 0.5,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(size * 0.1),
              ),
              child: Center(
                child: Icon(
                  Icons.percent_rounded,
                  size: size * 0.34,
                  color: const Color(0xFFD97706),
                ),
              ),
            ),
          ),
          Positioned(
            top: size * 0.06,
            right: size * 0.06,
            child: Icon(
              Icons.auto_awesome,
              size: size * 0.32,
              color: const Color(0xFFFEF3C7),
            ),
          ),
        ],
      ),
    );
  }
}
