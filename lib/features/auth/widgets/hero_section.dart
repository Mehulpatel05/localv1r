import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import 'logo_pin.dart';
import 'nearby_pin_chip.dart';
import 'street_painter.dart';

/// Top header section matching the HTML `.top` specification.
///
/// Features:
/// - Exact height (300px on Login, 210px on OTP)
/// - Abstract streets using the exact HTML Bézier paths
/// - Brand row: LogoPin (28x36) + "nearhood" (22px 800)
/// - Floating service chips with staggered drop-in on Login screen
class TopSection extends StatefulWidget {
  final bool isOtp;

  const TopSection({
    super.key,
    this.isOtp = false,
  });

  @override
  State<TopSection> createState() => _TopSectionState();
}

class _TopSectionState extends State<TopSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _chipController;
  late final Animation<double> _chip1Anim;
  late final Animation<double> _chip2Anim;
  late final Animation<double> _chip3Anim;

  @override
  void initState() {
    super.initState();
    // 700ms + 240ms stagger = ~940ms
    _chipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 940),
    );

    const cubicCurve = Cubic(0.2, 0.9, 0.3, 1.2);

    _chip1Anim = CurvedAnimation(
      parent: _chipController,
      curve: const Interval(0.0, 700 / 940, curve: cubicCurve),
    );

    _chip2Anim = CurvedAnimation(
      parent: _chipController,
      curve: const Interval(120 / 940, 820 / 940, curve: cubicCurve),
    );

    _chip3Anim = CurvedAnimation(
      parent: _chipController,
      curve: const Interval(240 / 940, 1.0, curve: cubicCurve),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final disableAnimations =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        if (disableAnimations) {
          _chipController.value = 1.0;
        } else {
          _chipController.forward();
        }
      }
    });
  }

  @override
  void dispose() {
    _chipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nearhoodColors;
    final statusBar = MediaQuery.paddingOf(context).top;
    final double targetHeight = widget.isOtp ? 210.0 : 300.0;

    return Container(
      height: targetHeight + statusBar,
      width: double.infinity,
      color: colors.bg,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background abstract streets
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: StreetPainter(
                  strokeColor: colors.streets,
                  isOtp: widget.isOtp,
                ),
              ),
            ),
          ),

          // Brand row: padding 46px 24px 0
          Positioned(
            top: 46.0 + statusBar,
            left: 24.0,
            right: 24.0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const LogoPin(
                  width: 28,
                  height: 36,
                ),
                const SizedBox(width: 10),
                Text(
                  'nearhood',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.44, // -0.02em * 22
                    color: colors.ink,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),

          // Floating chips (only on login screen)
          if (!widget.isOtp) ...[
            // Chip 1: Plumber · 0.4 km (top: 120, left: 22)
            Positioned(
              top: 120.0 + statusBar,
              left: 22.0,
              child: NearbyPinChip(
                label: 'Plumber · 0.4 km',
                animation: _chip1Anim,
              ),
            ),

            // Chip 2: Tiffin · 0.8 km (top: 164, right: 22)
            Positioned(
              top: 164.0 + statusBar,
              right: 22.0,
              child: NearbyPinChip(
                label: 'Tiffin · 0.8 km',
                animation: _chip2Anim,
              ),
            ),

            // Chip 3: Salon · 1.2 km (top: 214, left: 70)
            Positioned(
              top: 214.0 + statusBar,
              left: 70.0,
              child: NearbyPinChip(
                label: 'Salon · 1.2 km',
                animation: _chip3Anim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
