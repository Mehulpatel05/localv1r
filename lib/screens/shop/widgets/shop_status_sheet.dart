import 'package:flutter/material.dart';
import '../../bazar/shop_detail_screen.dart';
import '../../profile/widgets/support_request_sheet.dart';
import '../register_shop_screen.dart';
import '../../../theme/app_colors.dart';

class ShopStatusSheet {
  static void showUnderReview(
    BuildContext context, {
    required LocalShop shop,
    String? userHandle,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UnderReviewSheetContent(
        shop: shop,
        userHandle: userHandle,
      ),
    );
  }

  static void showRejected(
    BuildContext context, {
    required LocalShop shop,
    String? userHandle,
    VoidCallback? onReapplied,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RejectedSheetContent(
        shop: shop,
        userHandle: userHandle,
        onReapplied: onReapplied,
      ),
    );
  }
}

class _UnderReviewSheetContent extends StatelessWidget {
  final LocalShop shop;
  final String? userHandle;

  const _UnderReviewSheetContent({
    required this.shop,
    this.userHandle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.hourglass_top_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shop Under Review',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nearhood Vadodara Verification Team',
                      style: TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            'Your shop application has been submitted and is currently being reviewed by our Vadodara operations team. We verify address and business details within 24 hours.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.chipBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(Icons.storefront_rounded, 'Shop Name', shop.name),
                const SizedBox(height: 10),
                _buildInfoRow(Icons.category_outlined, 'Category', shop.category),
                const SizedBox(height: 10),
                _buildInfoRow(Icons.place_outlined, 'Location', shop.location),
                const SizedBox(height: 10),
                _buildInfoRow(
                  Icons.access_time_rounded,
                  'Status',
                  '⏳ Pending Approval (Within 24h)',
                  valueColor: AppColors.primaryText,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.primaryText,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Once approved, your shop will go live in Vadodara Bazar and this button will change to "Manage my shop".',
                    style: TextStyle(
                      color: AppColors.primaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  label: const Text(
                    'Contact Support',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    SupportRequestSheet.show(
                      context,
                      userHandle: userHandle ?? shop.ownerHandle,
                      initialPhone: shop.phone,
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _RejectedSheetContent extends StatelessWidget {
  final LocalShop shop;
  final String? userHandle;
  final VoidCallback? onReapplied;

  const _RejectedSheetContent({
    required this.shop,
    this.userHandle,
    this.onReapplied,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(
                  Icons.highlight_off_rounded,
                  color: AppColors.error,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shop Not Approved',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Action Required by Owner',
                      style: TextStyle(
                        color: Color(0xFFB3262A),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            'Your shop application was not approved during review. Please verify your shop name, address in Vadodara, and contact number before re-applying.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.errorSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(Icons.storefront_rounded, 'Shop Name', shop.name),
                const SizedBox(height: 10),
                _buildInfoRow(Icons.category_outlined, 'Category', shop.category),
                const SizedBox(height: 10),
                _buildInfoRow(Icons.place_outlined, 'Location', shop.location),
                const SizedBox(height: 10),
                _buildInfoRow(
                  Icons.cancel_outlined,
                  'Status',
                  'Rejected by Administrator',
                  valueColor: const Color(0xFFB3262A),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    side: BorderSide(color: AppColors.divider, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  label: const Text(
                    'Support',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    SupportRequestSheet.show(
                      context,
                      userHandle: userHandle ?? shop.ownerHandle,
                      initialPhone: shop.phone,
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Update & Re-apply',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterShopScreen()),
                    ).then((_) {
                      if (onReapplied != null) onReapplied!();
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
