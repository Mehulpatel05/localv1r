import 'dart:math';
import 'package:flutter/material.dart';
import '../../../services/bazar_repository.dart';
import '../../bazar/shop_detail_screen.dart';
import '../../../theme/app_colors.dart';

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
    final maxViews = _dailyViews.map((d) => (d['views'] as num).toDouble()).fold<double>(0.0, max);

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
        centerTitle: true,
        title: Text(
          'Shop insights',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Views, last 7 days',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: 24),

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
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            Container(
                              width: 38,
                              height: 120 * heightFactor,
                              decoration: BoxDecoration(
                                color: count > 0 ? AppColors.primary : AppColors.chipBg,
                                borderRadius: BorderRadius.circular(6),
                                border: count == 0 ? Border.all(color: AppColors.divider) : null,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              dayLabel,
                              style: TextStyle(
                                color: AppColors.textMuted,
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

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: _topProductTitle != null && _topProductTitle!.isNotEmpty
                        ? RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: AppColors.textPrimary,
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
                        : Row(
                            children: [
                              const Text('🏆 ', style: TextStyle(fontSize: 16)),
                              Expanded(
                                child: Text(
                                  'No products added yet. Add products to start tracking views.',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 14),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(
                      _chatsThisWeek > 0
                          ? '💬 $_chatsThisWeek chats this week, up from $_chatsLastWeek last week'
                          : '💬 0 chats this week. Share your shop on WhatsApp to get direct customer inquiries.',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  ..._tips.map(
                    (tip) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Text(
                        tip.startsWith('💡') || tip.startsWith('Tip') ? tip : '💡 $tip',
                        style: TextStyle(
                          color: AppColors.textPrimary,
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
