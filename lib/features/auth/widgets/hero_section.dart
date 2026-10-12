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
    final double targetHeight = widget.isOtp ? 80.0 : 130.0;

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
            top: (widget.isOtp ? 12.0 : 16.0) + statusBar,
            left: 20.0,
            right: 20.0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: widget.isOtp ? 36 : 40,
                  height: widget.isOtp ? 36 : 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: LogoPin(
                    width: widget.isOtp ? 18 : 20,
                    height: widget.isOtp ? 24 : 26,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'nearhood',
                      style: TextStyle(
                        fontSize: widget.isOtp ? 22 : 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    if (!widget.isOtp)
                      const Text(
                        'Your neighbourhood community',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFDCFCE7),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                if (!widget.isOtp)
                  NearbyPinChip(
                    service: 'Live local',
                    distance: '500m',
                    dotColor: const Color(0xFF22C55E),
                    animation: _chip1Anim,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
