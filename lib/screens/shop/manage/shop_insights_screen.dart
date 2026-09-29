import 'dart:math';
import 'package:flutter/material.dart';
import '../../../services/bazar_repository.dart';
import '../../bazar/shop_detail_screen.dart';

class ShopInsightsScreen extends StatefulWidget {
  final LocalShop shop;
  final String currentUserHandle;

  const ShopInsightsScreen({
    super.key,
    required this.shop,
    required this.currentUserHandle,
  });

  @override
  State<ShopInsightsScreen> createState() => _ShopInsightsScreenState();
}

class _ShopInsightsScreenState extends State<ShopInsightsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _dailyViews = [
    {'day': 'M', 'views': 0},
    {'day': 'T', 'views': 0},
    {'day': 'W', 'views': 0},
    {'day': 'T', 'views': 0},
    {'day': 'F', 'views': 0},
    {'day': 'S', 'views': 0},
    {'day': 'S', 'views': 0},
  ];

  String? _topProductTitle;
  int _topProductViews = 0;
  int _chatsThisWeek = 0;
  int _chatsLastWeek = 0;
  List<String> _tips = [
    'Tip: Add your first product to start getting customer views and inquiries in your area.',
  ];

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    setState(() => _isLoading = true);
    try {
      final insights = await BazarRepository.instance.fetchShopInsights();
      if (insights['success'] == true && mounted) {
        if (insights['viewsLast7Days'] is List) {
          _dailyViews = List<Map<String, dynamic>>.from(insights['viewsLast7Days']);
        }
        if (insights['topProduct'] is Map && insights['topProduct'] != null) {
          _topProductTitle = insights['topProduct']['title'] as String?;
          _topProductViews = (insights['topProduct']['viewsCount'] as num?)?.toInt() ?? 0;
        } else {
          _topProductTitle = null;
          _topProductViews = 0;
        }
        _chatsThisWeek = (insights['chatsThisWeek'] as num?)?.toInt() ?? 0;
        _chatsLastWeek = (insights['chatsLastWeek'] as num?)?.toInt() ?? 0;
        if (insights['tips'] is List && (insights['tips'] as List).isNotEmpty) {
          _tips = List<String>.from(insights['tips']);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const cardBg = Color(0xFF0A2E33);
    const borderColor = Color(0xFF0F4E56);

    final maxViews = _dailyViews.map((d) => (d['views'] as num).toDouble()).fold<double>(0.0, max);

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
          'Shop insights',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF14B8A6)))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section: Views, last 7 days
                  const Text(
                    'Views, last 7 days',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 7 Days Custom Bar Chart
                  Container(
                    height: 170,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _dailyViews.map((item) {
                        final count = (item['views'] as num).toDouble();
                        final heightFactor = maxViews > 0
                            ? (count / maxViews).clamp(0.06, 1.0)
                            : 0.06;
                        final dayLabel = item['day'].toString();

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (count > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  count.toInt().toString(),
                                  style: const TextStyle(
                                    color: Color(0xFF2DD4BF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            // Bar
                            Container(
                              width: 38,
                              height: 120 * heightFactor,
                              decoration: BoxDecoration(
                                color: count > 0 ? const Color(0xFF0E766E) : const Color(0xFF0A2E33),
                                borderRadius: BorderRadius.circular(6),
                                gradient: count > 0
                                    ? const LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Color(0xFF0F4E56),
                                          Color(0xFF14B8A6),
                                        ],
                                      )
                                    : null,
                                border: count == 0 ? Border.all(color: const Color(0xFF0F4E56).withValues(alpha: 0.4)) : null,
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Day letter
                            Text(
                              dayLabel,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Insight Card 1: Top Product
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                    ),
                    child: _topProductTitle != null && _topProductTitle!.isNotEmpty
                        ? RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.45,
                              ),
                              children: [
                                const TextSpan(text: '🏆 Top product: '),
                                TextSpan(
                                  text: _topProductTitle!,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                TextSpan(text: ' — $_topProductViews views this week'),
                              ],
                            ),
                          )
                        : const Row(
                            children: [
                              Text('🏆 ', style: TextStyle(fontSize: 16)),
                              Expanded(
                                child: Text(
                                  'No products added yet. Add products to start tracking views.',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 14),

                  // Insight Card 2: Chats Growth
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      _chatsThisWeek > 0
                          ? '💬 $_chatsThisWeek chats this week, up from $_chatsLastWeek last week'
                          : '💬 0 chats this week. Share your shop on WhatsApp to get direct customer inquiries.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Insight Card 3: AI Dynamic Smart Growth Tip
                  ..._tips.map(
                    (tip) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                      ),
                      child: Text(
                        tip.startsWith('💡') || tip.startsWith('Tip') ? tip : '💡 $tip',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}
