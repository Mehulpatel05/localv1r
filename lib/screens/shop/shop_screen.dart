import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/motion.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/location/location_service.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import 'shop_detail_screen.dart';
import 'shop_post_screen.dart';
import 'widgets/shop_card_widget.dart';

/// Redesigned Buy & Sell Marketplace Screen matching Images 2 & 3
class ShopScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const ShopScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late final PostRepository _localRepo;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory; // null means 'All'

  final List<Map<String, dynamic>> _categories = [
    {'name': 'Electronics', 'icon': Icons.devices_other_rounded},
    {'name': 'Furniture', 'icon': Icons.chair_rounded},
    {'name': 'Vehicles', 'icon': Icons.directions_car_rounded},
    {'name': 'Books', 'icon': Icons.menu_book_rounded},
    {'name': 'Fashion', 'icon': Icons.checkroom_rounded},
    {'name': 'Home', 'icon': Icons.home_rounded},
    {'name': 'Accessories', 'icon': Icons.watch_rounded},
    {'name': 'Other', 'icon': Icons.more_horiz_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _localRepo = PostRepository(context.read<LocationService>());
    _localRepo.setCategory(PostCategory.shop);
    _localRepo.addListener(_onRepoChanged);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _localRepo.removeListener(_onRepoChanged);
    _localRepo.dispose();
    super.dispose();
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  List<Post> get _filteredPosts {
    var list = _localRepo.allPosts;

    // Filter by selected category pill
    if (_selectedCategory != null) {
      list = list.where((p) {
        final cat = p.shopCategory ?? '';
        if (cat.toLowerCase() == _selectedCategory!.toLowerCase()) return true;
        // Fallback checks on title/content if legacy post
        final title = (p.shopTitle ?? p.content).toLowerCase();
        return title.contains(_selectedCategory!.toLowerCase());
      }).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      list = list.where((p) {
        final title = (p.shopTitle ?? '').toLowerCase();
        final content = p.content.toLowerCase();
        final area = (p.areaName ?? p.areaId ?? '').toLowerCase();
        final cat = (p.shopCategory ?? '').toLowerCase();
        return title.contains(_searchQuery) ||
            content.contains(_searchQuery) ||
            area.contains(_searchQuery) ||
            cat.contains(_searchQuery);
      }).toList();
    }

    return list;
  }

  void _openAreaPicker() {
    final locService = context.read<LocationService>();
    final city = locService.city;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Explore Buy & Sell in Area',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: city.areas.length + 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        final isSelected = locService.area == null;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          leading: Icon(
                            Icons.location_city_rounded,
                            color: isSelected ? const Color(0xFF00B074) : const Color(0xFF64748B),
                          ),
                          title: Text(
                            'All ${city.name}',
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? const Color(0xFF00B074) : const Color(0xFF1E293B),
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00B074))
                              : null,
                          onTap: () {
                            locService.setArea(null);
                            Navigator.pop(ctx);
                          },
                        );
                      }
                      final area = city.areas[i - 1];
                      final isSelected = locService.area?.id == area.id;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        leading: Icon(
                          Icons.location_on_rounded,
                          color: isSelected ? const Color(0xFF00B074) : const Color(0xFF64748B),
                        ),
                        title: Text(
                          area.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? const Color(0xFF00B074) : const Color(0xFF1E293B),
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00B074))
                            : null,
                        onTap: () {
                          locService.setArea(area);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locService = context.watch<LocationService>();
    final areaLabel = locService.area?.name ?? locService.city.name;
    final posts = _filteredPosts;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Buy & Sell',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Things people are selling near you',
              style: TextStyle(
                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          // Area Selector Pill (Image 3 Header)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: InkWell(
              onTap: _openAreaPicker,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: isDark ? Colors.white : Colors.black,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      areaLabel,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: isDark ? Colors.white : Colors.black,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _localRepo.refresh,
        color: isDark ? Colors.white : Colors.black,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // ── Search Bar & Category Filter Bar ─────────────────────
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Column(
                  children: [
                    // Search Bar
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13.5,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search products, electronics, furniture...',
                          hintStyle: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFF94A3B8),
                            size: 20,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Horizontal Category Chips Row (Image 3)
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final cat = _categories[i];
                          final name = cat['name'] as String;
                          final isSelected = _selectedCategory == name;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (_selectedCategory == name) {
                                  _selectedCategory = null; // deselect -> all
                                } else {
                                  _selectedCategory = name;
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: AnimatedContainer(
                              duration: AppMotion.durationMicro,
                              curve: AppMotion.interactiveCurve,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF1E293B) : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    cat['icon'] as IconData,
                                    size: 14,
                                    color: isSelected ? Colors.white : const Color(0xFF475569),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : const Color(0xFF334155),
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Product Grid or States ───────────────────────────────
            if (_localRepo.isLoading)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.68,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _buildShimmerCard(),
                    childCount: 6,
                  ),
                ),
              )
            else if (posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.68,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final post = posts[i];
                      return ShopCardWidget(
                        post: post,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ShopDetailScreen(
                                post: post,
                                repository: _localRepo,
                                currentUserHandle: widget.currentUserHandle,
                              ),
                            ),
                          );
                        },
                      );
                    },
                    childCount: posts.length,
                  ),
                ),
              ),
          ],
        ),
      ),

      // ── Centered Floating Pill FAB (Image 3) ───────────────────────
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.white : Colors.black,
          foregroundColor: isDark ? Colors.black : Colors.white,
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.25),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: const StadiumBorder(),
        ),
        icon: const Icon(Icons.shopping_bag_rounded, size: 18),
        label: const Text(
          'Sell a Product',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShopPostScreen(
                repository: _localRepo,
                authorHandle: widget.currentUserHandle,
              ),
            ),
          );
          _localRepo.refresh();
        },
      ),
    );
  }

  // ── Skeleton Shimmer Loading Placeholder Card (Image 2 State 1) ───────────
  Widget _buildShimmerCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shimmer Image Box
          Expanded(
            flex: 11,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFE2E8F0),
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
            ),
          ),
          Expanded(
            flex: 9,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Price Line (Soft green tint)
                      Container(
                        width: 65,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Title Line 1
                      Container(
                        width: double.infinity,
                        height: 11,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Title Line 2
                      Container(
                        width: 90,
                        height: 11,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                  // Location Dot & Line
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE2E8F0),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 50,
                        height: 9,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty State (Image 2 State 2) ─────────────────────────────────────────
  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular Storefront Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                shape: BoxShape.circle,
                border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
              ),
              child: Center(
                child: Icon(
                  Icons.storefront_rounded,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Headline
            Text(
              'Nothing for sale nearby',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),

            // Subtitle
            Text(
              'Be the first person in your area to list something.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 24),

            // Sell a Product Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.shopping_bag_rounded, size: 18),
              label: const Text(
                'Sell a Product',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShopPostScreen(
                      repository: _localRepo,
                      authorHandle: widget.currentUserHandle,
                    ),
                  ),
                );
                _localRepo.refresh();
              },
            ),
            const SizedBox(height: 14),

            // Refresh Link Button
            TextButton.icon(
              onPressed: _localRepo.refresh,
              icon: Icon(Icons.refresh_rounded, size: 16, color: isDark ? Colors.white : Colors.black),
              label: Text(
                'Refresh',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
