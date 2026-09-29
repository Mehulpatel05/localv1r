import 'package:flutter/material.dart';
import '../../../services/bazar_repository.dart';
import '../../bazar/shop_detail_screen.dart';
import 'my_products_screen.dart';
import 'edit_shop_details_screen.dart';
import 'shop_insights_screen.dart';

class MyShopDashboardScreen extends StatefulWidget {
  final LocalShop? initialShop;
  final String currentUserHandle;

  const MyShopDashboardScreen({
    super.key,
    this.initialShop,
    required this.currentUserHandle,
  });

  @override
  State<MyShopDashboardScreen> createState() => _MyShopDashboardScreenState();
}

class _MyShopDashboardScreenState extends State<MyShopDashboardScreen> {
  late LocalShop _shop;
  bool _isLoading = true;
  bool _isOpen = true;
  int _activeCount = 0;
  int _outOfStockCount = 0;
  int _viewsThisWeek = 0;
  int _chatsCount = 0;
  int _ordersCount = 0;

  @override
  void initState() {
    super.initState();
    _shop = widget.initialShop ??
        LocalShop(
          id: 'shop_${widget.currentUserHandle.replaceAll('@', '')}',
          ownerHandle: widget.currentUserHandle,
          name: 'My Shop',
          category: 'Pharmacy',
          categoryIcon: '💊',
          location: 'Alkapuri, Vadodara',
          distanceKm: 0.8,
          isVerified: true,
          imageUrl: '',
          phone: '',
          timings: '9:00 AM - 9:00 PM',
          aboutText: '',
          products: [],
        );
    _isOpen = _shop.isOpen;
    _loadShopData();
  }

  Future<void> _loadShopData() async {
    setState(() => _isLoading = true);
    try {
      final fetched = await BazarRepository.instance.fetchMyShop();
      final products = await BazarRepository.instance.fetchMyShopProducts();
      if (mounted) {
        setState(() {
          if (fetched != null) {
            _shop = fetched;
            _isOpen = fetched.isOpen;
            _viewsThisWeek = fetched.viewsCount;
            _chatsCount = fetched.chatsCount;
            _ordersCount = fetched.ordersCount;
          }
          _activeCount = products.where((p) => !p.isSold).length;
          _outOfStockCount = products.where((p) => p.isSold).length;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleShopOpen(bool value) async {
    setState(() {
      _isOpen = value;
    });

    await BazarRepository.instance.toggleShopStatus(_shop.id, value);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? '🟢 Shop is now OPEN. Customers see you in Bazaar!'
                : '🔴 Shop is now CLOSED. Customers will see you as closed.',
          ),
          backgroundColor: value ? const Color(0xFF0D5E56) : const Color(0xFF4A1515),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showDeactivateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111A1B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF1F383D)),
        ),
        title: const Row(
          children: [
            Icon(Icons.pause_circle_outline, color: Color(0xFFF87171), size: 26),
            SizedBox(width: 10),
            Text(
              'Deactivate Shop?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Your shop will be hidden from the Bazaar feed temporarily. Your listed products and settings will remain safe.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _toggleShopOpen(false);
            },
            child: const Text('Deactivate', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showBoostShopBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1F22),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF0E766E).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF14B8A6)),
              ),
              child: const Text(
                '✨ COMING SOON',
                style: TextStyle(
                  color: Color(0xFF2DD4BF),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF14454C).withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Text('🚀', style: TextStyle(fontSize: 36)),
            ),
            const SizedBox(height: 14),
            const Text(
              'Boost My Shop',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Get 10x more reach and appear at the very top of Vadodara Bazaar for 7 days. Starting at just ₹49.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF072E33),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF0F5A63)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFF2DD4BF), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Feature is under active development and launching in the next update!',
                      style: TextStyle(color: Color(0xFF2DD4BF), fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const cardBg = Color(0xFF0A2E33);
    const borderColor = Color(0xFF0F4E56);

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
          'My shop',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: Color(0xFF1E3A40),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.settings, color: Colors.white70, size: 20),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditShopDetailsScreen(shop: _shop),
                    ),
                  ).then((_) => _loadShopData());
                },
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF14B8A6)))
          : RefreshIndicator(
              color: const Color(0xFF14B8A6),
              backgroundColor: const Color(0xFF0A2E33),
              onRefresh: _loadShopData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Header Shop Info Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          // Shop Icon / Logo Box
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: const Color(0xFF062327),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF145E68)),
                            ),
                            child: Center(
                              child: _shop.imageUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.network(
                                        _shop.imageUrl,
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Text(
                                          _shop.categoryIcon,
                                          style: const TextStyle(fontSize: 28),
                                        ),
                                      ),
                                    )
                                  : Text(
                                      _shop.categoryIcon,
                                      style: const TextStyle(fontSize: 28),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Shop Name, Badge & Subtitle
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _shop.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.3,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F4E56),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.check, size: 12, color: Color(0xFF2DD4BF)),
                                          SizedBox(width: 3),
                                          Text(
                                            'Verified',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_shop.category} · ${_shop.location.split(',').first}',
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // 2. Shop Open / Closed Toggle Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Shop open',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _isOpen
                                    ? 'Customers see you as open right now'
                                    : 'Shop is currently marked as closed',
                                style: TextStyle(
                                  color: _isOpen ? const Color(0xFF94A3B8) : const Color(0xFFF87171),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Transform.scale(
                          scale: 0.9,
                          child: Switch(
                            value: _isOpen,
                            onChanged: _toggleShopOpen,
                            activeTrackColor: const Color(0xFF14B8A6),
                            activeThumbColor: Colors.white,
                            inactiveTrackColor: const Color(0xFF1E293B),
                            inactiveThumbColor: Colors.grey,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // 3. 3 Metrics Grid Row (Views | Chats | Orders)
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            count: '$_viewsThisWeek',
                            label: 'Views this week',
                            cardBg: cardBg,
                            borderColor: borderColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricCard(
                            count: '$_chatsCount',
                            label: 'Chats',
                            cardBg: cardBg,
                            borderColor: borderColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricCard(
                            count: '$_ordersCount',
                            label: 'Orders',
                            cardBg: cardBg,
                            borderColor: borderColor,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // 4. Section Title: Manage
                    const Text(
                      'Manage',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 5. Manage List Items
                    _buildManageItem(
                      emoji: '📦',
                      title: 'Manage products',
                      subtitle: '$_activeCount active · $_outOfStockCount out of stock',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MyProductsScreen(
                              currentUserHandle: widget.currentUserHandle,
                              shopId: _shop.id,
                            ),
                          ),
                        ).then((_) => _loadShopData());
                      },
                    ),

                    _buildManageItem(
                      emoji: '✏️',
                      title: 'Edit shop details',
                      subtitle: 'Name, timings, location, contact',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditShopDetailsScreen(shop: _shop),
                          ),
                        ).then((_) => _loadShopData());
                      },
                    ),

                    _buildManageItem(
                      emoji: '📊',
                      title: 'Shop insights',
                      subtitle: 'Views, top product, chats',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShopInsightsScreen(
                              shop: _shop,
                              currentUserHandle: widget.currentUserHandle,
                            ),
                          ),
                        );
                      },
                    ),

                    _buildManageItem(
                      emoji: '🚀',
                      title: 'Boost my shop',
                      badgeText: 'COMING SOON',
                      subtitle: 'Coming Soon · 10x more reach in Bazaar',
                      onTap: _showBoostShopBottomSheet,
                    ),

                    _buildManageItem(
                      emoji: '⏸️',
                      title: 'Deactivate shop',
                      titleColor: const Color(0xFFF87171),
                      subtitle: 'Hide your shop temporarily',
                      onTap: _showDeactivateDialog,
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMetricCard({
    required String count,
    required String label,
    required Color cardBg,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Text(
            count,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildManageItem({
    required String emoji,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color titleColor = Colors.white,
    String? badgeText,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: const Color(0xFF0F4E56).withValues(alpha: 0.3),
          highlightColor: const Color(0xFF0F4E56).withValues(alpha: 0.15),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF072E33),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (badgeText != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0E766E).withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF14B8A6), width: 0.8),
                              ),
                              child: Text(
                                badgeText,
                                style: const TextStyle(
                                  color: Color(0xFF2DD4BF),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF64748B),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
