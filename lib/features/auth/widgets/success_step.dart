import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Step 3: Success state upon successful OTP verification.
///
/// Features:
/// - 64px green circle with white ✓ (size 30) that pops in (scale 0 -> 1, 350ms, Curves.easeOutBack).
/// - Title: "You're in" (19, 700).
/// - Subtitle: "Finding services near you…" (14, muted).
/// - Automatically calls [onLoggedIn] after 1.2 seconds.
class SuccessStep extends StatefulWidget {
  final VoidCallback onLoggedIn;

  const SuccessStep({
    super.key,
    required this.onLoggedIn,
  });

  @override
  State<SuccessStep> createState() => _SuccessStepState();
}

class _SuccessStepState extends State<SuccessStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController;
  late final Animation<double> _scaleAnimation;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _popController,
      curve: Curves.easeOutBack,
    );

    _popController.forward();

    // After 1.2 seconds, trigger onLoggedIn callback
    _navigationTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        // TODO: Navigate to Home screen
        widget.onLoggedIn();
      }
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nearhoodColors;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Column(
      key: const ValueKey('success_step_view'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        // 64px green circle with white ✓ (size 30) that pops in
        ScaleTransition(
          scale: disableAnimations
              ? const AlwaysStoppedAnimation(1.0)
              : _scaleAnimation,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.btn,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colors.btn.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.check_rounded,
              size: 30,
              color: colors.btnink,
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Title: "You're in" (19, 700)
        Text(
          "You're in",
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.19,
            color: colors.ink,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),

        // Subtitle: "Finding services near you…" (14, muted)
        Text(
          'Finding services near you…',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: colors.muted,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
