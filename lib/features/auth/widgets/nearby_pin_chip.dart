import 'package:flutter/material.dart';

class NearbyPinChip extends StatelessWidget {
  final String service;
  final String distance;
  final Color dotColor;
  final Animation<double>? animation;

  const NearbyPinChip({
    super.key,
    required this.service,
    required this.distance,
    required this.dotColor,
    this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final chipContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            service,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              height: 1.15,
            ),
          ),
          Text(
            ' · $distance',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
              height: 1.15,
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
        final translateY = -12.0 * (1.0 - progress);
        final scale = 0.92 + (progress * 0.08);

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
