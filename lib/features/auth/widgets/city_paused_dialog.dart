import 'package:flutter/material.dart';

class CityPausedDialog extends StatelessWidget {
  const CityPausedDialog({
    super.key,
    this.message,
    this.cityName,
  });

  final String? message;
  final String? cityName;

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF2C7880);
    const lightGreenTint = Color(0xFFE2F0F1);
    const textPrimary = Color(0xFF111827);
    const textSecondary = Color(0xFF6B7280);

    final displayMessage = message ??
        'Nearhood services in ${cityName ?? 'aapke shehar'} are currently paused, but your account and profile data are completely safe.';

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      backgroundColor: Colors.white,
      elevation: 4,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: lightGreenTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.pause_circle_outline_rounded,
                color: primaryGreen,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'City Services Paused',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textPrimary,
                fontFamily: 'Manrope',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              displayMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: textSecondary,
                fontFamily: 'Manrope',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Theek hai (Understood)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Manrope',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
