import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../bazar/bazar_screen.dart';
import '../bazar/shop_detail_screen.dart';
import '../../services/bazar_repository.dart';
import '../../services/post_repository.dart';
import '../../core/services/name_cache_service.dart';
import '../../core/widgets/safe_image.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  String _selectedTab = 'Items';

  List<BazarProduct> _savedItems = [];
  List<LocalShop> _savedShops = [];
  List<Map<String, String>> _savedPosts = [];

  @override
  void initState() {
    super.initState();
    BazarRepository.instance.addListener(_refreshSavedData);
    PostRepository.instance.addListener(_refreshSavedData);
    _refreshSavedData();
  }

  @override
  void dispose() {
    BazarRepository.instance.removeListener(_refreshSavedData);
    PostRepository.instance.removeListener(_refreshSavedData);
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
      _savedPosts = PostRepository.instance.posts
          .where((p) => p.isSaved)
          .map((p) => {
                'id': p.id,
                'title': p.content.isNotEmpty ? (p.content.length > 50 ? '${p.content.substring(0, 50)}...' : p.content) : 'Post by ${getDisplayName(p.authorHandle)}',
                'author': getDisplayName(p.authorHandle),
                'time': p.timeAgo,
              })
          .toList();
    });
  }

  void _unsaveItem(BazarProduct product) {
    BazarRepository.instance.toggleSaveProduct(product.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.primary,
        content: Text('Removed "${product.title}" from saved items.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _unsaveShop(LocalShop shop) {
    BazarRepository.instance.toggleSaveShop(shop.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.primary,
        content: Text('Removed "${shop.name}" from saved shops.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
              decoration: const BoxDecoration(
                color: AppColors.chipBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textPrimary,
                size: 20,
              ),
            ),
          ),
        ),
        centerTitle: true,
        title: const Text(
          'Saved',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                bottom: BorderSide(color: AppColors.divider, width: 1.0),
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
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Text(
                      tab,
                      style: TextStyle(
                        color: isSelected ? AppColors.primary : AppColors.textMuted,
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
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.bookmark_rounded, color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post['title']!,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${post['author']}  •  ${post['time']}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
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
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: AppColors.primarySoft,
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
                                    color: AppColors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (shop.isVerified) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${shop.category}  •  ${shop.location}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.favorite_rounded, color: AppColors.error),
                        onPressed: () => _unsaveShop(shop),
                      ),
                    ],
                  ),
                );
              },
            );
    }
  }

  Widget _buildSavedItemCard(BazarProduct product) {
    return Container(
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: product.imageUrl.isNotEmpty
                      ? SafeImage(
                          imageUrl: product.imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: Container(
                            color: AppColors.chipBg,
                            alignment: Alignment.center,
                            child: const Icon(Icons.shopping_bag_outlined, color: AppColors.textMuted, size: 40),
                          ),
                        )
                      : Container(
                          color: AppColors.chipBg,
                          alignment: Alignment.center,
                          child: const Icon(Icons.shopping_bag_outlined, color: AppColors.textMuted, size: 40),
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
                        color: Colors.black.withValues(alpha: 0.4),
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
                    color: AppColors.textPrimary,
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
                        color: AppColors.primaryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${product.distanceKm} km',
                      style: const TextStyle(
                        color: AppColors.textMuted,
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
          Icon(icon, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
