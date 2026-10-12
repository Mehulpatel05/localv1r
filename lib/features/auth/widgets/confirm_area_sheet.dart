import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../services/auth_service.dart';

class ConfirmAreaSheet extends StatefulWidget {
  const ConfirmAreaSheet({
    super.key,
    required this.currentAreaName,
    required this.currentCityName,
    required this.onAreaConfirmed,
    required this.onChangeArea,
  });

  final String currentAreaName;
  final String currentCityName;
  final VoidCallback onAreaConfirmed;
  final VoidCallback onChangeArea;

  @override
  State<ConfirmAreaSheet> createState() => _ConfirmAreaSheetState();
}

class _ConfirmAreaSheetState extends State<ConfirmAreaSheet> {
  bool _isConfirming = false;

  Future<void> _handleConfirm() async {
    setState(() => _isConfirming = true);
    final success = await AuthService.instance.confirmArea();
    if (!mounted) return;
    setState(() => _isConfirming = false);
    if (success) {
      Navigator.of(context).pop();
      widget.onAreaConfirmed();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not confirm area. Please try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF0E8A3E);
    const darkGreen = Color(0xFF0B5D2A);
    const lightGreenTint = Color(0xFFE3F4EA);
    const textPrimary = Color(0xFF111827);
    const textSecondary = Color(0xFF6B7280);
    const borderColor = Color(0xFFE5E7EB);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: lightGreenTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: darkGreen,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Confirm your area',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: textPrimary,
              fontFamily: 'Manrope',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Aapka home area ${widget.currentAreaName} set hai. Taaki aapko sahi padosi aur local shops dikhein, kripya ise confirm karein.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: textSecondary,
              fontFamily: 'Manrope',
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6F5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.home_work_outlined,
                  color: primaryGreen,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.currentAreaName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                          fontFamily: 'Manrope',
                        ),
                      ),
                      Text(
                        widget.currentCityName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: textSecondary,
                          fontFamily: 'Manrope',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: lightGreenTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Current',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: primaryGreen,
                      fontFamily: 'Manrope',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isConfirming ? null : _handleConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isConfirming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Haan, area sahi hai',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Manrope',
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onChangeArea();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: textPrimary,
                side: const BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Area badlein (Change area)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Manrope',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
