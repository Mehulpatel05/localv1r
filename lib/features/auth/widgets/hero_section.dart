import 'package:flutter/material.dart';
import 'logo_pin.dart';
import 'nearby_pin_chip.dart';
import 'street_painter.dart';

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
    final statusBar = MediaQuery.paddingOf(context).top;
    final double targetHeight = widget.isOtp ? 180.0 : 290.0;

    return Container(
      height: targetHeight + statusBar,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF085A2B),
            Color(0xFF0C6E35),
            Color(0xFF0A6832),
          ],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: StreetPainter(
                  strokeColor: const Color(0xFF22C55E),
                  isOtp: widget.isOtp,
                ),
              ),
            ),
          ),
          Positioned(
            top: 36.0 + statusBar,
            left: 24.0,
            right: 24.0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const LogoPin(
                    width: 24,
                    height: 32,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'nearhood',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isOtp) ...[
            Positioned(
              top: 112.0 + statusBar,
              left: 24.0,
              child: NearbyPinChip(
                service: 'Plumber',
                distance: '0.4 km',
                dotColor: const Color(0xFF22C55E),
                animation: _chip1Anim,
              ),
            ),
            Positioned(
              top: 158.0 + statusBar,
              right: 30.0,
              child: NearbyPinChip(
                service: 'Tiffin',
                distance: '0.8 km',
                dotColor: const Color(0xFFF59E0B),
                animation: _chip2Anim,
              ),
            ),
            Positioned(
              top: 212.0 + statusBar,
              left: 56.0,
              child: NearbyPinChip(
                service: 'Salon',
                distance: '1.2 km',
                dotColor: const Color(0xFFEC4899),
                animation: _chip3Anim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
