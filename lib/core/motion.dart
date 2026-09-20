import 'package:flutter/material.dart';

/// Central source of truth for all motion and animation across the app.
/// Follows iOS-like restraint: fast start, soft landing, no overshoot.
class AppMotion {
  AppMotion._();

  // ---------------------------------------------------------------------------
  // Duration Scale (Ceilings)
  // ---------------------------------------------------------------------------
  /// Press-down / press-up feedback (100ms)
  static const Duration durationInstant = Duration(milliseconds: 100);

  /// Icon state, nav indicator, toggle, badge (180ms)
  static const Duration durationMicro = Duration(milliseconds: 180);

  /// Tab body switch, fade-in, expand/collapse (220ms)
  static const Duration durationStandard = Duration(milliseconds: 220);

  /// Screen push (280ms)
  static const Duration durationPageIn = Duration(milliseconds: 280);

  /// Screen pop (240ms)
  static const Duration durationPageOut = Duration(milliseconds: 240);

  // ---------------------------------------------------------------------------
  // Standard Curves
  // ---------------------------------------------------------------------------
  /// Entering / appearing: fast start, soft landing
  static const Curve enterCurve = Curves.easeOutCubic;

  /// Exiting / disappearing
  static const Curve exitCurve = Curves.easeInCubic;

  /// Reversible or interruptible interactions
  static const Curve interactiveCurve = Curves.easeInOut;

  // ---------------------------------------------------------------------------
  // Movement Distances (8–16 logical pixels)
  // ---------------------------------------------------------------------------
  /// Micro translation (8px) for tab switch & item pop
  static const double distanceMicro = 8.0;

  /// Standard translation (12px)
  static const double distanceStandard = 12.0;

  /// Page translation (16px)
  static const double distancePage = 16.0;

  // ---------------------------------------------------------------------------
  // Accessibility Helpers (Reduce Motion Support)
  // ---------------------------------------------------------------------------
  /// Checks if the operating system has "Reduce Motion" enabled.
  static bool isReduceMotion(BuildContext context) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// Returns Duration.zero if the user has Reduce Motion enabled,
  /// otherwise returns the requested standard duration.
  static Duration getDuration(BuildContext context, Duration baseDuration) {
    return isReduceMotion(context) ? Duration.zero : baseDuration;
  }

  static Duration instant(BuildContext context) => getDuration(context, durationInstant);
  static Duration micro(BuildContext context) => getDuration(context, durationMicro);
  static Duration standard(BuildContext context) => getDuration(context, durationStandard);
  static Duration pageIn(BuildContext context) => getDuration(context, durationPageIn);
  static Duration pageOut(BuildContext context) => getDuration(context, durationPageOut);
}
