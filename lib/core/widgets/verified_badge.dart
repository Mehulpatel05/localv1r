import 'package:flutter/material.dart';

class VerifiedBadge extends StatelessWidget {
  final bool isVerified;
  final String? badgeText;
  final String? handle;
  final double iconSize;
  final double fontSize;
  final bool showText;
  final Color iconColor;
  final bool compact;

  const VerifiedBadge({
    super.key,
    this.isVerified = false,
    this.badgeText,
    this.handle,
    double? size,
    double? iconSize,
    this.fontSize = 9.5,
    this.showText = true,
    this.iconColor = const Color(0xFF2C7880),
    this.compact = false,
  }) : iconSize = size ?? iconSize ?? 14.0;

  bool get _hasBadgeText => badgeText != null && badgeText!.trim().isNotEmpty;
  bool get _isFounding => _hasBadgeText && badgeText!.toUpperCase().contains('FOUNDING');

  @override
  Widget build(BuildContext context) {
    if (!isVerified && !_hasBadgeText) {
      return const SizedBox.shrink();
    }

    if (showText && _isFounding) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5)
                : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(compact ? 4 : 6),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.8),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_rounded,
                  color: const Color(0xFFD97706),
                  size: fontSize + 1.5,
                ),
                const SizedBox(width: 3),
                Text(
                  badgeText!.toUpperCase(),
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFB45309),
                    letterSpacing: 0.2,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (showText && _hasBadgeText && badgeText!.toUpperCase() != 'VERIFIED') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5)
                : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(compact ? 4 : 6),
              border: Border.all(
                color: const Color(0xFF0284C7).withValues(alpha: 0.6),
                width: 0.8,
              ),
            ),
            child: Text(
              badgeText!.toUpperCase(),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0369A1),
                letterSpacing: 0.2,
                height: 1.1,
              ),
            ),
          ),
          if (isVerified) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.verified_rounded,
              color: iconColor,
              size: iconSize,
            ),
          ],
        ],
      );
    }

    if (isVerified) {
      return Padding(
        padding: const EdgeInsets.only(left: 3),
        child: Icon(
          Icons.verified_rounded,
          color: iconColor,
          size: iconSize,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
