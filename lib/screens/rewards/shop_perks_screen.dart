import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/rewards_model.dart';
import '../../services/rewards_service.dart';

class ShopPerksScreen extends StatefulWidget {
  final String currentUserHandle;

  const ShopPerksScreen({
    super.key,
    this.currentUserHandle = '',
  });

  @override
  State<ShopPerksScreen> createState() => _ShopPerksScreenState();
}

class _ShopPerksScreenState extends State<ShopPerksScreen> {
  List<ShopPerkItem> _perks = [];
  final List<UnlockedCouponItem> _myUnlockedCoupons = [];
  bool _isLoading = true;
  int _balance = 0;

  @override
  void initState() {
    super.initState();
    _loadPerks();
  }

  Future<void> _loadPerks() async {
    final summary = await RewardsService.instance.fetchSummary();
    final perks = await RewardsService.instance.fetchShopPerks();

    if (mounted) {
      setState(() {
        _balance = summary?.balance ?? 0;
        _perks = perks;
        _isLoading = false;
      });
    }
  }

  Future<void> _unlockCoupon(ShopPerkItem perk) async {
    if (_balance < perk.costPoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You need ${perk.costPoints - _balance} more points to unlock this offer.'),
          backgroundColor: const Color(0xFFC0333A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD5ECDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_offer_rounded, size: 30, color: Color(0xFFD97706)),
            ),
            const SizedBox(height: 16),
            Text(
              'Unlock ${perk.title}?',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF16243A)),
            ),
            const SizedBox(height: 8),
            Text(
              'Spend ${perk.costPoints} points for a 7-day coupon at ${perk.shopName}.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF5C6B7D), height: 1.4),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD5ECDD), width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF16243A))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E8A3E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Unlock (${perk.costPoints} pts)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final res = await RewardsService.instance.unlockCoupon(perk.id);
    if (!mounted) return;

    if (res != null) {
      setState(() {
        _myUnlockedCoupons.insert(0, res);
        _balance -= perk.costPoints;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Coupon unlocked: ${res.code}! Valid for 7 days.'),
          backgroundColor: const Color(0xFF0E8A3E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyCouponCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coupon code copied! Show it to the shopkeeper at checkout.'),
        backgroundColor: Color(0xFF0E8A3E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF16243A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Shop Perks',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF16243A),
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0E8A3E)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_myUnlockedCoupons.isNotEmpty) ...[
                    const Text(
                      'My Unlocked Coupons',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16243A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _myUnlockedCoupons.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final c = _myUnlockedCoupons[index];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF78350F),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Code: ${c.code}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                      color: Color(0xFF0E8A3E),
                                    ),
                                  ),
                                ],
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0E8A3E),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () => _copyCouponCode(c.code),
                                child: const Text('Copy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Available Perks',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16243A),
                        ),
                      ),
                      Text(
                        'Your balance: $_balance pts',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0E8A3E),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  if (_perks.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD5ECDD), width: 0.8),
                      ),
                      child: const Center(
                        child: Text(
                          'No active shop perks available in your area yet. Local shops will be adding discounts soon!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, color: Color(0xFF5C6B7D), height: 1.4),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _perks.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final perk = _perks[index];
                        final canAfford = _balance >= perk.costPoints;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFD5ECDD), width: 0.8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F6EF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.storefront_rounded, color: Color(0xFF0E8A3E), size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      perk.title,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF16243A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${perk.shopName} · ${perk.category}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF5C6B7D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: canAfford ? const Color(0xFF0E8A3E) : const Color(0xFFF1F5F9),
                                  foregroundColor: canAfford ? Colors.white : const Color(0xFF64748B),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () => _unlockCoupon(perk),
                                child: Text(
                                  '${perk.costPoints} pts',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F6EF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFD5ECDD), width: 0.8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.store_mall_directory_rounded, size: 28, color: Color(0xFF0E8A3E)),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Own a local business?',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF16243A),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Register your shop in Bazaar to offer perks & discount coupons to neighbours.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF5C6B7D),
                                  height: 1.35,
                                ),
                              ),
                            ],
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
