import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'bazar_screen.dart';

class LocalShop {
  final String id;
  final String name;
  final String category;
  final String categoryIcon;
  final String location;
  final double distanceKm;
  final bool isVerified;
  final String imageUrl;
  final String phone;
  final String deliveryInfo;
  final String timings;
  final String aboutText;
  final List<BazarProduct> products;

  LocalShop({
    required this.id,
    required this.name,
    required this.category,
    required this.categoryIcon,
    required this.location,
    required this.distanceKm,
    this.isVerified = true,
    required this.imageUrl,
    this.phone = '',
    this.deliveryInfo = '',
    this.timings = '',
    this.aboutText = '',
    required this.products,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'categoryIcon': categoryIcon,
        'location': location,
        'distanceKm': distanceKm,
        'isVerified': isVerified,
        'imageUrl': imageUrl,
        'phone': phone,
        'deliveryInfo': deliveryInfo,
        'timings': timings,
        'aboutText': aboutText,
        'products': products.map((p) => p.toJson()).toList(),
      };

  factory LocalShop.fromJson(Map<String, dynamic> json) => LocalShop(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        category: json['category'] ?? 'General',
        categoryIcon: json['categoryIcon'] ?? '🏪',
        location: json['location'] ?? '',
        distanceKm: json['distanceKm'] is num ? (json['distanceKm'] as num).toDouble() : 0.0,
        isVerified: json['isVerified'] ?? true,
        imageUrl: json['imageUrl'] ?? '',
        phone: json['phone'] ?? '',
        deliveryInfo: json['deliveryInfo'] ?? '',
        timings: json['timings'] ?? '',
        aboutText: json['aboutText'] ?? '',
        products: (json['products'] as List<dynamic>?)
                ?.map((p) => BazarProduct.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
      );
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
  String _selectedTab = 'Products'; // 'Products', 'About', 'Reviews'

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;

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
        actions: [
          // Share Button
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
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.ios_share_rounded,
                color: Colors.black,
                size: 18,
              ),
            ),
          ),

          // Call Button Top Right
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF072E33),
                  content: Text('📞 Calling ${shop.name} (${shop.phone})...'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_rounded,
                color: Colors.black,
                size: 20,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: const BoxDecoration(
          color: Colors.black,
          border: Border(
            top: BorderSide(color: Color(0xFF072E33), width: 1.5),
          ),
        ),
        child: Row(
          children: [
            // Outlined Call Button
            Expanded(
              child: SizedBox(
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
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF072E33),
                        content: Text('📞 Calling ${shop.name} (${shop.phone})...'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text(
                    'Call',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Solid White Chat with Shop Button
            Expanded(
              flex: 2,
              child: SizedBox(
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF072E33),
                        content: Text('💬 Opening direct chat with ${shop.name}...'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text(
                    'Chat with shop',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Shop Header Card (Avatar + Title + Verified Badge + Subtitle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Shop Circle Avatar
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF072E33),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0E525B), width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    shop.categoryIcon,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(width: 14),

                // Shop Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              shop.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (shop.isVerified) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF094B52),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.check, color: Colors.white, size: 12),
                                  SizedBox(width: 3),
                                  Text(
                                    'Verified',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${shop.category}  •  ${shop.location}  •  ${shop.distanceKm} km away',
                        style: const TextStyle(
                          color: Color(0xFF90B4B6),
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

          // 2. Shop Navigation Tabs (Products | About | Reviews)
          Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF072E33), width: 1.5),
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
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Text(
                      tab,
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF90B4B6),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // 3. Tab Body
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
          // 2-Column Products Grid
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

          // Info Banner (🛵 Free home delivery within 1 km · Open now · Closes 9:00 PM)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF072E33),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF0E525B)),
            ),
            child: Row(
              children: [
                const Text('🛵', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${shop.deliveryInfo}  •  ${shop.timings}',
                    style: const TextStyle(
                      color: Colors.white,
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
            const Text('About this Shop', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              shop.aboutText,
              style: const TextStyle(color: Color(0xFF90B4B6), fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            _buildAboutDetailCard('📍 Address', shop.location),
            const SizedBox(height: 10),
            _buildAboutDetailCard('📞 Contact', shop.phone),
            const SizedBox(height: 10),
            _buildAboutDetailCard('🕒 Timings', shop.timings),
            const SizedBox(height: 10),
            _buildAboutDetailCard('🛵 Delivery', shop.deliveryInfo),
          ],
        ),
      );
    } else {
      // Reviews Tab
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF072E33),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF0E525B)),
            ),
            child: Row(
              children: [
                const Text('⭐ 4.8', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Based on 28 neighbor ratings', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('96% positive feedback in Alkapuri', style: TextStyle(color: Color(0xFF90B4B6), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildReviewCard('Rahul Sharma', '⭐ 5.0', 'Super fast delivery within 20 mins! Original medicines.'),
          const SizedBox(height: 10),
          _buildReviewCard('Pooja Patel', '⭐ 5.0', 'Very polite owner, genuine rates and always open on time.'),
        ],
      );
    }
  }

  Widget _buildAboutDetailCard(String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF072E33),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0E525B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF90B4B6), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildReviewCard(String author, String rating, String comment) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF072E33),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0E525B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(author, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              Text(rating, style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(comment, style: const TextStyle(color: Color(0xFF90B4B6), fontSize: 13, height: 1.35)),
        ],
      ),
    );
  }

  Widget _buildShopProductCard(BazarProduct product) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF072E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0E525B)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image Container
          Expanded(
            child: Container(
              color: const Color(0xFF052A2E),
              alignment: Alignment.center,
              child: Image.network(
                product.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) => Center(
                  child: Text(
                    _getProductCategoryEmoji(product.title),
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
            ),
          ),

          // Title & Price
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
                Text(
                  '₹${product.price}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getProductCategoryEmoji(String title) {
    final t = title.toLowerCase();
    if (t.contains('vitamin') || t.contains('tab') || t.contains('med')) return '💊';
    if (t.contains('aid') || t.contains('kit')) return '🩹';
    if (t.contains('thermometer')) return '🌡️';
    if (t.contains('sanitiser') || t.contains('soap')) return '🧴';
    if (t.contains('bread')) return '🍞';
    if (t.contains('brownie') || t.contains('cake')) return '🍰';
    if (t.contains('hair') || t.contains('shampoo')) return '💇';
    return '📦';
  }
}
