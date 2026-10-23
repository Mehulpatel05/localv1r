import 'package:flutter/material.dart';
import '../../services/rewards_service.dart';
import '../../services/bazar_repository.dart';
import '../../services/auth_service.dart';
import '../bazar/bazar_screen.dart';
import '../../core/widgets/safe_image.dart';

class BoostListingScreen extends StatefulWidget {
  final String currentUserHandle;
  final BazarProduct? initialProduct;
  final String? listingId;
  final String? listingTitle;
  final int? currentBalance;

  const BoostListingScreen({
    super.key,
    this.currentUserHandle = '',
    this.initialProduct,
    this.listingId,
    this.listingTitle,
    this.currentBalance,
  });

  @override
  State<BoostListingScreen> createState() => _BoostListingScreenState();
}

class _BoostListingScreenState extends State<BoostListingScreen> {
  static const int _boostCost = 300;
  List<BazarProduct> _myListings = [];
  BazarProduct? _selectedProduct;
  bool _isLoading = true;
  bool _isBoosting = false;
  int _balance = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final summary = await RewardsService.instance.fetchSummary();
    final handle = widget.currentUserHandle.isNotEmpty
        ? widget.currentUserHandle
        : (await AuthService.instance.getUserHandle() ?? '');
    final listings = BazarRepository.instance.getUserListings(handle);

    if (mounted) {
      setState(() {
        _balance = widget.currentBalance ?? (summary?.balance ?? 0);
        _myListings = listings.where((l) => !l.isSold).toList();
        if (widget.initialProduct != null) {
          _selectedProduct = widget.initialProduct;
        } else if (widget.listingId != null) {
          try {
            _selectedProduct = _myListings.firstWhere((l) => l.id == widget.listingId);
          } catch (_) {
            _selectedProduct = _myListings.isNotEmpty ? _myListings.first : null;
          }
        } else if (_myListings.isNotEmpty) {
          _selectedProduct = _myListings.first;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmAndBoost() async {
    if (_selectedProduct == null) return;

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
                color: const Color(0xFFEADBE7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt_rounded, size: 34, color: Color(0xFFD97706)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Feature Listing for 24h?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF16243A)),
            ),
            const SizedBox(height: 8),
            Text(
              'This will spend 300 points to place "${_selectedProduct!.title}" at the top of the Bazaar feed.',
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
                        side: const BorderSide(color: Color(0xFFEADBE7), width: 1.2),
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
                        backgroundColor: const Color(0xFF3A0F34),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Confirm (300 pts)', style: TextStyle(fontWeight: FontWeight.bold)),
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

    setState(() => _isBoosting = true);
    final res = await RewardsService.instance.boostListing(_selectedProduct!.id);
    if (!mounted) return;
    setState(() => _isBoosting = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listing boosted! Featured tag active for 24 hours. ✨'),
          backgroundColor: Color(0xFF3A0F34),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Failed to boost listing'),
          backgroundColor: const Color(0xFFC0333A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasEnoughPoints = _balance >= _boostCost;
    final pointsNeeded = _boostCost - _balance;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF16243A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Boost Listing',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF16243A),
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3A0F34)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF59E0B),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.bolt_rounded, size: 20, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Featured in your area',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF78350F),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Your listing will be pinned to the top of the Bazaar feed for 24 hours with a prominent "Featured" tag to get maximum local visibility and faster inquiries.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF92400E),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Cost: 300 pts',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF78350F),
                              ),
                            ),
                            Text(
                              'Your balance: $_balance pts',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Select listing to feature',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16243A),
                    ),
                  ),

                  const SizedBox(height: 10),

                  if (_myListings.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEADBE7), width: 0.8),
                      ),
                      child: const Center(
                        child: Text(
                          'You have no active listings right now. Post an item in Bazaar first!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, color: Color(0xFF5C6B7D)),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _myListings.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final product = _myListings[index];
                        final isSelected = _selectedProduct?.id == product.id;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedProduct = product),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFE8F6EF) : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF3A0F34) : const Color(0xFFEADBE7),
                                width: isSelected ? 1.5 : 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 54,
                                    height: 54,
                                    color: const Color(0xFFE9ECEF),
                                    child: product.imageUrl.isNotEmpty
                                        ? SafeImage(
                                            imageUrl: product.imageUrl,
                                            fit: BoxFit.cover,
                                            errorWidget: const Icon(Icons.image_outlined, color: Color(0xFF5C6B7D)),
                                          )
                                        : const Icon(Icons.image_outlined, color: Color(0xFF5C6B7D)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.title,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF16243A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '₹${product.price}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF3A0F34),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                  color: isSelected ? const Color(0xFF3A0F34) : const Color(0xFFCBD5E1),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 28),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasEnoughPoints ? const Color(0xFF3A0F34) : const Color(0xFFCBD5E1),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: (hasEnoughPoints && _selectedProduct != null && !_isBoosting)
                          ? _confirmAndBoost
                          : null,
                      child: _isBoosting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              hasEnoughPoints ? 'Boost for 300 pts' : 'Need $pointsNeeded more pts',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
