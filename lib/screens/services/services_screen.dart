import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/location/location_service.dart';
import '../../core/location/location_chip.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import 'service_detail_screen.dart';
import 'services_post_screen.dart';
import 'widgets/service_card_widget.dart';

class ServicesScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const ServicesScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  late final PostRepository _localRepo;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedCategory = ''; // '' = All
  String _selectedPriceRange = 'All'; // 'All', 'Under ₹300', '₹300–₹1000', 'Above ₹1000'

  final List<Map<String, dynamic>> _categoriesRow1 = [
    {'name': 'Plumbing', 'icon': Icons.build_rounded},
    {'name': 'Electrical', 'icon': Icons.bolt_rounded},
    {'name': 'Home', 'icon': Icons.home_rounded},
    {'name': 'Cleaning', 'icon': Icons.cleaning_services_rounded},
    {'name': 'Tutors', 'icon': Icons.menu_book_rounded},
  ];

  final List<Map<String, dynamic>> _categoriesRow2 = [
    {'name': 'Drivers', 'icon': Icons.directions_car_rounded},
    {'name': 'Cook', 'icon': Icons.restaurant_rounded},
    {'name': 'IT', 'icon': Icons.laptop_chromebook_rounded},
    {'name': 'Other', 'icon': Icons.more_horiz_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _localRepo = PostRepository(context.read<LocationService>());
    _localRepo.setCategory(PostCategory.services);
    _localRepo.addListener(_onRepoChanged);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
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

  int _parsePrice(String? priceStr) {
    if (priceStr == null || priceStr.isEmpty) return 299;
    final digits = priceStr.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 299;
  }

  List<Post> _getFilteredPosts(List<Post> posts) {
    return posts.where((post) {
      final title = (post.serviceTitle ?? '').toLowerCase();
      final content = post.content.toLowerCase();
      final category = (post.serviceCategoryText ?? '').toLowerCase();
      final area = (post.areaName ?? '').toLowerCase();
      final priceVal = _parsePrice(post.servicePrice);

      // 1. Search Query Filter
      if (_searchQuery.isNotEmpty) {
        final matches = title.contains(_searchQuery) ||
            content.contains(_searchQuery) ||
            category.contains(_searchQuery) ||
            area.contains(_searchQuery);
        if (!matches) return false;
      }

      // 2. Category Filter
      if (_selectedCategory.isNotEmpty) {
        final sc = _selectedCategory.toLowerCase();
        if (!category.contains(sc) && !title.contains(sc) && !content.contains(sc)) {
          return false;
        }
      }

      // 3. Price Filter
      if (_selectedPriceRange == 'Under ₹300') {
        if (priceVal > 300) return false;
      } else if (_selectedPriceRange == '₹300–₹1000') {
        if (priceVal < 300 || priceVal > 1000) return false;
      } else if (_selectedPriceRange == 'Above ₹1000') {
        if (priceVal < 1000) return false;
      }

      return true;
    }).toList();
  }

  void _openOfferService() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServicesPostScreen(
          repository: _localRepo,
          authorHandle: widget.currentUserHandle,
        ),
      ),
    );
    _localRepo.refresh();
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141414) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Category Filter
                const Text(
                  'Category',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Electrical', 'Plumbing', 'Cleaning', 'Tutors'].map((c) {
                    final isSel = _selectedCategory == c;
                    return ChoiceChip(
                      label: Text(c),
                      selected: isSel,
                      onSelected: (val) {
                        setModalState(() {
                          _selectedCategory = val ? c : '';
                        });
                        setState(() {});
                      },
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFFEFF6FF),
                      labelStyle: TextStyle(
                        color: isSel ? const Color(0xFF2563EB) : const Color(0xFF475569),
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: isSel ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                // Price Filter
                const Text(
                  'Price',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['All', 'Under ₹300', '₹300–₹1000', 'Above ₹1000'].map((p) {
                    final isSel = _selectedPriceRange == p;
                    return ChoiceChip(
                      label: Text(p),
                      selected: isSel,
                      onSelected: (val) {
                        setModalState(() {
                          _selectedPriceRange = p;
                        });
                        setState(() {});
                      },
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFFEFF6FF),
                      labelStyle: TextStyle(
                        color: isSel ? const Color(0xFF2563EB) : const Color(0xFF475569),
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: isSel ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        setModalState(() {
                          _selectedCategory = '';
                          _selectedPriceRange = 'All';
                        });
                        setState(() {});
                      },
                      child: const Text('Reset', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white : Colors.black,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allPosts = _localRepo.allPosts;
    final filteredPosts = _getFilteredPosts(allPosts);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Services',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        actions: const [
          Center(child: LocationChip()),
          SizedBox(width: 14),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.white : Colors.black,
          foregroundColor: isDark ? Colors.black : Colors.white,
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.25),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const StadiumBorder(),
        ),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text(
          'Offer a Service',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
            letterSpacing: -0.2,
          ),
        ),
        onPressed: _openOfferService,
      ),
      body: RefreshIndicator(
        onRefresh: _localRepo.refresh,
        color: isDark ? Colors.white : Colors.black,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.only(bottom: 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Headline & Intro (Image 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Find local help',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Trusted services from people around your community',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Search Bar (Image 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(fontSize: 14.5, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'Search for a service...',
                      hintStyle: TextStyle(color: isDark ? const Color(0xFF6E6E6E) : const Color(0xFF94A3B8), fontSize: 14),
                      prefixIcon: Icon(Icons.search_rounded, color: isDark ? const Color(0xFF6E6E6E) : const Color(0xFF94A3B8), size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded, color: isDark ? const Color(0xFF6E6E6E) : const Color(0xFF94A3B8), size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Category Selector Chips Row 1
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _categoriesRow1.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = _categoriesRow1[index];
                    final name = cat['name'] as String;
                    final icon = cat['icon'] as IconData;
                    final isSelected = _selectedCategory == name;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = isSelected ? '' : name;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4)),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isSelected
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              size: 14,
                              color: isSelected
                                  ? (isDark ? Colors.black : Colors.white)
                                  : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF4B5563)),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? (isDark ? Colors.black : Colors.white)
                                    : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF4B5563)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // Category Selector Chips Row 2
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _categoriesRow2.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = _categoriesRow2[index];
                    final name = cat['name'] as String;
                    final icon = cat['icon'] as IconData;
                    final isSelected = _selectedCategory == name;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = isSelected ? '' : name;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4)),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isSelected
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              size: 14,
                              color: isSelected
                                  ? (isDark ? Colors.black : Colors.white)
                                  : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF4B5563)),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? (isDark ? Colors.black : Colors.white)
                                    : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF4B5563)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Section Header: Near you + Filter Button (Image 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text(
                        '📍 Near you — services available around your area',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: _showFilterBottomSheet,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.tune_rounded, size: 16, color: Color(0xFF0F172A)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Body: Loading Skeleton, Empty State, or 2-Column Grid
              if (_localRepo.isLoading) ...[
                _buildSkeletonGrid(),
              ] else if (filteredPosts.isEmpty) ...[
                _buildEmptyState(),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredPosts.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.67,
                    ),
                    itemBuilder: (context, index) {
                      final post = filteredPosts[index];
                      return ServiceCardWidget(
                        post: post,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ServiceDetailScreen(
                                post: post,
                                repository: _localRepo,
                                currentUserHandle: widget.currentUserHandle,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 1. Loading Skeleton State (Image 4 Group 4)
  Widget _buildSkeletonGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          childAspectRatio: 0.67,
        ),
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 10,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                    ),
                  ),
                ),
                Expanded(
                  flex: 10,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Container(
                          width: 80,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          width: 120,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          width: 90,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 2. Empty State (Image 4 Group 5)
  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                shape: BoxShape.circle,
                border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
              ),
              child: Icon(
                Icons.handyman_outlined,
                size: 36,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No local services yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Be the first person in your area to offer a service.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Offer a Service',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              onPressed: _openOfferService,
            ),
          ],
        ),
      ),
    );
  }
}
