import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Floating nearby service chip pill matching the exact HTML/CSS spec.
///
/// Specification:
/// - Background: `var(--bg)`, Border: `1px solid var(--line)`, Radius: `999px`
/// - Shadow: `0 6px 16px rgba(0, 0, 0, 0.08)`
/// - Bullet: 8x8 circle filled with `var(--ink)`
/// - Text: 12.5px, font-weight 600, color `var(--ink)`
/// - Padding: `7px 12px 7px 10px` (L:10, T:7, R:12, B:7)
class NearbyPinChip extends StatelessWidget {
  final String label;
  final Animation<double>? animation;

  const NearbyPinChip({
    super.key,
    required this.label,
    this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nearhoodColors;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    Widget chipContent = Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.line, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 8x8 solid dot: background var(--ink)
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colors.ink,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.ink,
              height: 1.2,
            ),
          ),
        ],
      ),
    );

    if (animation == null || disableAnimations) {
      return chipContent;
    }

    return AnimatedBuilder(
      animation: animation!,
      builder: (context, child) {
        final progress = animation!.value;
        final opacity = progress.clamp(0.0, 1.0);
        final translateY = -14.0 * (1.0 - progress);
        final scale = 0.9 + (progress * 0.1);

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, translateY),
            child: Transform.scale(
              scale: scale,
              child: child,
            ),
          ),
        );
      },
      child: chipContent,
    );
  }
}
