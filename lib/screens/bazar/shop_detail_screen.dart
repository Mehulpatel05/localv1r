import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'bazar_screen.dart';
import '../../services/auth_service.dart';
import '../../services/bazar_repository.dart';
import '../chat/personal_chat_screen.dart';
import '../shop/manage/my_shop_dashboard_screen.dart';
import '../../core/widgets/verified_badge.dart';
import '../../core/services/badge_cache_service.dart';
import '../../core/widgets/safe_image.dart';
import '../../theme/app_colors.dart';

class LocalShop {
  final String id;
  final String ownerHandle;
  final String name;
  final String category;
  final String categoryIcon;
  final String location;
  final double distanceKm;
  final bool isVerified;
  final String? authorBadge;
  final String imageUrl;
  final String bannerUrl;
  final String phone;
  final String deliveryInfo;
  final String timings;
  final String aboutText;
  final bool isOpen;
  final bool sameWhatsapp;
  final bool homeDelivery;
  final int viewsCount;
  final int chatsCount;
  final int ordersCount;
  final String status;
  final List<BazarProduct> products;

  LocalShop({
    required this.id,
    this.ownerHandle = '',
    required this.name,
    required this.category,
    required this.categoryIcon,
    required this.location,
    required this.distanceKm,
    this.isVerified = false,
    this.authorBadge,
    required this.imageUrl,
    this.bannerUrl = '',
    this.phone = '',
    this.deliveryInfo = '',
    this.timings = '9:00 AM - 9:00 PM',
    this.aboutText = '',
    this.isOpen = true,
    this.sameWhatsapp = true,
    this.homeDelivery = true,
    this.viewsCount = 0,
    this.chatsCount = 0,
    this.ordersCount = 0,
    this.status = 'active',
    required this.products,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerHandle': ownerHandle,
        'name': name,
        'category': category,
        'categoryIcon': categoryIcon,
        'location': location,
        'distanceKm': distanceKm,
        'isVerified': isVerified,
        'authorBadge': authorBadge,
        'imageUrl': imageUrl,
        'bannerUrl': bannerUrl,
        'phone': phone,
        'deliveryInfo': deliveryInfo,
        'timings': timings,
        'aboutText': aboutText,
        'isOpen': isOpen,
        'sameWhatsapp': sameWhatsapp,
        'homeDelivery': homeDelivery,
        'viewsCount': viewsCount,
        'chatsCount': chatsCount,
        'ordersCount': ordersCount,
        'status': status,
        'products': products.map((p) => p.toJson()).toList(),
      };

  static String resolveCategoryIcon(dynamic icon, dynamic category) {
    final rawIcon = (icon ?? '').toString().trim();
    if (rawIcon.isNotEmpty && rawIcon != '💊' && rawIcon != '🏪') {
      return rawIcon;
    }
    final cat = (category ?? '').toString().toLowerCase();
    if (cat.contains('cloth') || cat.contains('tailor') || cat.contains('fashion')) return '🛍️';
    if (cat.contains('mobile') || cat.contains('electronic')) return '📱';
    if (cat.contains('cafe') || cat.contains('bakery') || cat.contains('food')) return '🍞';
    if (cat.contains('salon') || cat.contains('beauty')) return '✂️';
    if (cat.contains('kirana') || cat.contains('grocery') || cat.contains('general')) return '🛒';
    return '🛍️';
  }

  factory LocalShop.fromJson(Map<String, dynamic> json) {
    final owner = (json['ownerHandle'] ?? json['owner_handle'] ?? '') as String;
    final isVer = json['isVerified'] == true || json['is_verified'] == 1;
    final badge = (json['authorBadge'] ?? json['author_badge'] ?? json['badge']) as String?;
    if (owner.isNotEmpty) {
      BadgeCacheService.instance.setBadge(
        owner.replaceAll('@', ''),
        isVerified: isVer,
        badgeText: badge,
      );
    }

    return LocalShop(
      id: json['id'] ?? '',
      ownerHandle: owner,
      name: json['name'] ?? json['shop_name'] ?? json['shopName'] ?? '',
      category: json['category'] ?? 'General',
      categoryIcon: resolveCategoryIcon(json['categoryIcon'], json['category']),
      location: json['location'] ?? json['address'] ?? '',
      distanceKm: json['distanceKm'] is num ? (json['distanceKm'] as num).toDouble() : 0.8,
      isVerified: isVer,
      authorBadge: badge,
      imageUrl: json['imageUrl'] ?? json['logo_r2_path'] ?? json['banner_r2_path'] ?? '',
      bannerUrl: json['bannerUrl'] ?? json['banner_r2_path'] ?? '',
      phone: json['phone'] ?? '',
      deliveryInfo: json['deliveryInfo'] ?? '',
      timings: json['timings'] ?? '9:00 AM - 9:00 PM',
      aboutText: json['aboutText'] ?? json['description'] ?? '',
      isOpen: json['isOpen'] ?? (json['status'] != 'inactive'),
      sameWhatsapp: json['sameWhatsapp'] ?? true,
      homeDelivery: json['homeDelivery'] ?? true,
      viewsCount: json['viewsCount'] ?? (json['stats']?['viewsThisWeek'] ?? 0),
      chatsCount: json['chatsCount'] ?? (json['stats']?['chatsCount'] ?? 0),
      ordersCount: json['ordersCount'] ?? (json['stats']?['ordersCount'] ?? 0),
      status: json['status'] ?? 'active',
      products: (json['products'] as List<dynamic>?)
              ?.map((p) => BazarProduct.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ShopDetailScreen extends StatefulWidget {
  final LocalShop shop;

  const ShopDetailScreen({
    super.key,
    required this.shop,
  });

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  String _selectedTab = 'Products';

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;

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
        actions: [
          FutureBuilder<String?>(
            future: AuthService.instance.getUserHandle(),
            builder: (context, snapshot) {
              final currentHandle = snapshot.data?.replaceAll('@', '').trim().toLowerCase() ?? '';
              final shopOwner = shop.ownerHandle.replaceAll('@', '').trim().toLowerCase();
              final isOwner = (currentHandle.isNotEmpty && shopOwner.isNotEmpty && currentHandle == shopOwner) ||
                              shop.id == 'shop_$currentHandle';

              if (!isOwner) return const SizedBox.shrink();

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MyShopDashboardScreen(
                        initialShop: shop,
                        currentUserHandle: '@$currentHandle',
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.settings_outlined, color: AppColors.primaryText, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Manage',
                        style: TextStyle(
                          color: AppColors.primaryText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          GestureDetector(
            onTap: () {
              SharePlus.instance.share(
                ShareParams(
                  text: 'Check out ${shop.name} on Nearhood Bazaar! ${shop.category} in ${shop.location}.',
                ),
              );
            },
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AppColors.chipBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.ios_share_rounded,
                color: AppColors.textPrimary,
                size: 18,
              ),
            ),
          ),

          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.textPrimary,
                  content: Text('📞 Calling ${shop.name} (${shop.phone})...'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: AppColors.chipBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.call_rounded,
                color: AppColors.textPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: FutureBuilder<String?>(
        future: AuthService.instance.getUserHandle(),
        builder: (context, snapshot) {
          final currentHandle = snapshot.data?.replaceAll('@', '').trim().toLowerCase() ?? '';
          final shopOwner = shop.ownerHandle.replaceAll('@', '').trim().toLowerCase();
          final isOwner = (currentHandle.isNotEmpty && shopOwner.isNotEmpty && currentHandle == shopOwner) ||
                          shop.id == 'shop_$currentHandle';

          return Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.divider, width: 1.5),
              ),
            ),
            child: isOwner
                ? SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primarySoft,
                        foregroundColor: AppColors.primaryText,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                          side: BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      icon: Icon(Icons.dashboard_outlined, color: AppColors.primaryText, size: 20),
                      label: const Text(
                        'Manage My Shop',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MyShopDashboardScreen(
                              initialShop: shop,
                              currentUserHandle: '@$currentHandle',
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: AppColors.chipBg,
                              foregroundColor: AppColors.textPrimary,
                              side: BorderSide(color: AppColors.divider, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            icon: const Icon(Icons.call_outlined, size: 18),
                            label: const Text(
                              'Call',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () {
                              if (shop.phone.trim().isNotEmpty) {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: AppColors.surface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide(color: AppColors.divider),
                                    ),
                                    title: Row(
                                      children: [
                                        Icon(Icons.phone_in_talk_rounded, color: AppColors.primary, size: 24),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            shop.name,
                                            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Shop Contact Number:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                        const SizedBox(height: 6),
                                        Text(
                                          shop.phone,
                                          style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                        ),
                                        if (shop.timings.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          Text('🕒 Timings: ${shop.timings}', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                        ],
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: Text('Close', style: TextStyle(color: AppColors.textMuted)),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Shop phone number not available.'),
                                    backgroundColor: AppColors.textPrimary,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                            label: const Text(
                              'Chat with shop',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () async {
                              final myHandle = await AuthService.instance.getUserHandle() ?? '@me';
                              final targetHandle = shop.ownerHandle.isNotEmpty
                                  ? shop.ownerHandle
                                  : shop.id.replaceAll('shop_', '');

                              BazarRepository.instance.recordShopChatInquiry(shop.id);

                              if (!context.mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PersonalChatScreen(
                                    currentUserHandle: myHandle,
                                    partnerHandle: targetHandle,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.divider, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: shop.imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: SafeImage(
                            imageUrl: shop.imageUrl,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorWidget: const Icon(
                              Icons.storefront_rounded,
                              color: AppColors.primary,
                              size: 30,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.storefront_rounded,
                          color: AppColors.primary,
                          size: 30,
                        ),
                ),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              shop.name,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          VerifiedBadge(
                            handle: shop.ownerHandle,
                            isVerified: shop.isVerified,
                            badgeText: shop.authorBadge,
                            size: 16,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${shop.category}  •  ${shop.location}  •  ${shop.distanceKm} km away',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.divider, width: 1.5),
              ),
            ),
            child: Row(
              children: ['Products', 'About', 'Reviews'].map((tab) {
                final isSelected = _selectedTab == tab;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTab = tab;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Text(
                      tab,
                      style: TextStyle(
                        color: isSelected ? AppColors.primaryText : AppColors.textMuted,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          Expanded(
            child: _buildTabBody(shop),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody(LocalShop shop) {
    if (_selectedTab == 'Products') {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (shop.products.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Text('📦', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text(
                    'No products listed yet',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This shop has not listed any catalog products yet.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.82,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: shop.products.length,
              itemBuilder: (context, index) {
                final product = shop.products[index];
                return _buildShopProductCard(product);
              },
            ),

          const SizedBox(height: 16),

          if (shop.deliveryInfo.isNotEmpty || shop.timings.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  const Text('🛵', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${shop.deliveryInfo.isNotEmpty ? shop.deliveryInfo : "Home delivery available"}  •  ${shop.timings.isNotEmpty ? shop.timings : "Open Today"}',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),
        ],
      );
    } else if (_selectedTab == 'About') {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About this Shop', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              shop.aboutText.isNotEmpty
                  ? shop.aboutText
                  : 'Local verified seller on Bazaar. Dedicated to serving neighbors with quality products.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            _buildAboutDetailCard('📍 Address', shop.location.isNotEmpty ? shop.location : 'Vadodara'),
            if (shop.phone.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildAboutDetailCard('📞 Contact', shop.phone),
            ],
            const SizedBox(height: 10),
            _buildAboutDetailCard('🕒 Timings', shop.timings.isNotEmpty ? shop.timings : 'Open Daily'),
            const SizedBox(height: 10),
            _buildAboutDetailCard('🛵 Delivery', shop.deliveryInfo.isNotEmpty ? shop.deliveryInfo : 'Home Delivery & In-store pickup'),
          ],
        ),
      );
    } else {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const Text('⭐', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verified Bazaar Seller', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Customer ratings and verified reviews will appear here as orders complete.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No reviews written yet.\nBe the first neighbor to order & review!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildAboutDetailCard(String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _openProductDetail(BazarProduct product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                height: 180,
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
              children: [
                Expanded(
                  child: Text(
                    product.title,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '₹${product.price}',
                  style: TextStyle(color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            if (product.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                product.description,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text(
                  'Inquire about this item',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final myHandle = await AuthService.instance.getUserHandle() ?? '@me';
                  final targetHandle = widget.shop.ownerHandle.isNotEmpty
                      ? widget.shop.ownerHandle
                      : widget.shop.id.replaceAll('shop_', '');

                  BazarRepository.instance.recordListingChatInquiry(product.id);
                  BazarRepository.instance.recordShopChatInquiry(widget.shop.id);

                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PersonalChatScreen(
                        currentUserHandle: myHandle,
                        partnerHandle: targetHandle,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopProductCard(BazarProduct product) {
    return GestureDetector(
      onTap: () => _openProductDetail(product),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                color: AppColors.chipBg,
                alignment: Alignment.center,
                child: BazarProduct.buildProductImage(
                  product.imageUrl,
                  fit: BoxFit.cover,
                  fallbackIcon: Icons.storefront_rounded,
                  fallbackIconSize: 40,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${product.price}',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
