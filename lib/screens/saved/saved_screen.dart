import 'dart:io';
import 'package:flutter/material.dart';
import '../bazar/bazar_screen.dart';
import '../bazar/shop_detail_screen.dart';
import '../../services/bazar_repository.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  String _selectedTab = 'Items'; // 'Items', 'Posts', 'Shops'

  List<BazarProduct> _savedItems = [];
  List<LocalShop> _savedShops = [];
  List<Map<String, String>> _savedPosts = [];

  @override
  void initState() {
    super.initState();
    BazarRepository.instance.addListener(_refreshSavedData);
    _refreshSavedData();
  }

  @override
  void dispose() {
    BazarRepository.instance.removeListener(_refreshSavedData);
    super.dispose();
  }

  void _refreshSavedData() {
    if (!mounted) return;
    setState(() {
      _savedItems = BazarRepository.instance.products
          .where((p) => BazarRepository.instance.isProductSaved(p.id))
          .toList();
      _savedShops = BazarRepository.instance.shops
          .where((s) => BazarRepository.instance.isShopSaved(s.id))
          .toList();
      _savedPosts = [];
    });
  }

  void _unsaveItem(BazarProduct product) {
    BazarRepository.instance.toggleSaveProduct(product.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF072E33),
        content: Text('Removed "${product.title}" from saved items.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _unsaveShop(LocalShop shop) {
    BazarRepository.instance.toggleSaveShop(shop.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF072E33),
        content: Text('Removed "${shop.name}" from saved shops.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          'Saved',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // View Tabs (Items | Posts | Shops) matching media_1790655700167.png
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF072E33), width: 1.5),
              ),
            ),
            child: Row(
              children: ['Items', 'Posts', 'Shops'].map((tab) {
                final isSelected = _selectedTab == tab;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTab = tab;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

          // Tab Body View
          Expanded(
            child: _buildTabBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody() {
    if (_selectedTab == 'Items') {
      return _savedItems.isEmpty
          ? _buildEmptyState('No saved items yet.', Icons.favorite_border_rounded)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.78,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: _savedItems.length,
              itemBuilder: (context, index) {
                final product = _savedItems[index];
                return _buildSavedItemCard(product);
              },
            );
    } else if (_selectedTab == 'Posts') {
      return _savedPosts.isEmpty
          ? _buildEmptyState('No saved posts yet.', Icons.bookmark_outline_rounded)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _savedPosts.length,
              itemBuilder: (context, index) {
                final post = _savedPosts[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF072E33),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF0E525B)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E525B),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.bookmark_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post['title']!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${post['author']}  •  ${post['time']}',
                              style: const TextStyle(color: Color(0xFF90B4B6), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
    } else {
      // Shops tab
      return _savedShops.isEmpty
          ? _buildEmptyState('No saved shops yet.', Icons.storefront_rounded)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _savedShops.length,
              itemBuilder: (context, index) {
                final shop = _savedShops[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF072E33),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF0E525B)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: Color(0xFF0E525B),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(shop.categoryIcon, style: const TextStyle(fontSize: 26)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  shop.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (shop.isVerified) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.check_circle, color: Color(0xFF14B8A6), size: 16),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${shop.category}  •  ${shop.location}',
                              style: const TextStyle(color: Color(0xFF90B4B6), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.favorite_rounded, color: Colors.white),
                        onPressed: () => _unsaveShop(shop),
                      ),
                    ],
                  ),
                );
              },
            );
    }
  }

  // Saved Item Card (Matching media_1790655700167.png)
  Widget _buildSavedItemCard(BazarProduct product) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF072E33),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0E525B)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Container with Heart Icon top right
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: product.imageUrl.isNotEmpty
                      ? (product.imageUrl.startsWith('http')
                          ? Image.network(product.imageUrl, fit: BoxFit.cover)
                          : Image.file(File(product.imageUrl), fit: BoxFit.cover))
                      : Container(
                          color: const Color(0xFF0E525B),
                          alignment: Alignment.center,
                          child: const Icon(Icons.shopping_bag_outlined, color: Colors.white54, size: 40),
                        ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: () => _unsaveItem(product),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Details Container
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '₹${product.price}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${product.distanceKm} km',
                      style: const TextStyle(
                        color: Color(0xFF90B4B6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF90B4B6), size: 48),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
