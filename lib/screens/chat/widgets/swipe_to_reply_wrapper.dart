import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Custom horizontal drag gesture recognizer that only accepts drags
/// in the direction allowed for this message bubble:
/// - If [isMe] is true: Only accepts drag to the left (dx < 0).
/// - If [isMe] is false: Only accepts drag to the right (dx > 0).
///
/// Any gesture in the opposing direction returns false from
/// [hasSufficientGlobalDistanceToAccept], cleanly yielding to vertical
/// list scrolling or parent gesture recognizers.
class DirectionalHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  bool isMe;

  DirectionalHorizontalDragGestureRecognizer({
    required this.isMe,
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
  });

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    // If isMe is true (own message, right-aligned): ONLY allow drag to the left (globalDistanceMoved < 0)
    if (isMe && globalDistanceMoved >= 0) {
      return false;
    }
    // If isMe is false (received message, left-aligned): ONLY allow drag to the right (globalDistanceMoved > 0)
    if (!isMe && globalDistanceMoved <= 0) {
      return false;
    }
    return super.hasSufficientGlobalDistanceToAccept(
      pointerDeviceKind,
      deviceTouchSlop,
    );
  }
}

/// A WhatsApp / Instagram-grade swipe-to-reply gesture wrapper for chat message bubbles.
///
/// Features:
/// - Direction locking based on sender ([isMe] == true -> right-to-left only; [isMe] == false -> left-to-right only).
/// - 1:1 finger tracking up to 65px, with rubber-band resistance beyond that (capped at 85px).
/// - Progressive reply icon reveal: 0-20px invisible, 20-45px fade & scale in.
/// - 45px trigger threshold: tactile [HapticFeedback.lightImpact] + icon scale bounce (1.0 -> 1.16 -> 1.0).
/// - Released >= 45px: triggers [onSwipeReply] and springs back using [Curves.easeOutBack] (~280ms).
/// - Released < 45px: glides back using [Curves.easeOutCubic] (~180ms) without triggering reply.
/// - Does not interfere with vertical list scrolling.
/// - Multi-touch safe (only one bubble swiped at a time).
class SwipeToReplyWrapper extends StatefulWidget {
  final String messageId;
  final bool isMe;
  final VoidCallback onSwipeReply;
  final Widget child;
  final bool enabled;

  const SwipeToReplyWrapper({
    super.key,
    required this.messageId,
    required this.isMe,
    required this.onSwipeReply,
    required this.child,
    this.enabled = true,
  });

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper>
    with TickerProviderStateMixin {
  /// Ensures only one bubble across the whole chat can be actively swiped at a time.
  static String? _activeSwipingMessageId;

  late AnimationController _returnController;
  late Animation<double> _returnAnimation;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  double _accumulatedDrag = 0.0;
  double _currentDisplacement = 0.0;
  bool _thresholdReached = false;
  bool _isDragging = false;

  // Gesture & threshold constants
  static const double _kTriggerThreshold = 45.0;
  static const double _kHysteresisThreshold = 38.0;
  static const double _kMaxDragLimit = 65.0;
  static const double _kMaxDisplacementCap = 85.0;

  @override
  void initState() {
    super.initState();

    _returnController = AnimationController(vsync: this);
    _returnAnimation = const AlwaysStoppedAnimation<double>(0.0);
    _returnController.addListener(() {
      setState(() {
        _currentDisplacement = _returnAnimation.value;
      });
    });
    _returnController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _currentDisplacement = 0.0;
          _accumulatedDrag = 0.0;
          _thresholdReached = false;
        });
      }
    });

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.16)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 40.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.16, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 60.0,
      ),
    ]).animate(_bounceController);
    _bounceController.addListener(() {
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant SwipeToReplyWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messageId != oldWidget.messageId) {
      if (_activeSwipingMessageId == oldWidget.messageId) {
        _activeSwipingMessageId = null;
      }
      _isDragging = false;
      _thresholdReached = false;
      _currentDisplacement = 0.0;
      _accumulatedDrag = 0.0;
      if (_returnController.isAnimating) _returnController.stop();
      if (_bounceController.isAnimating) _bounceController.stop();
    }
  }

  @override
  void dispose() {
    if (_activeSwipingMessageId == widget.messageId) {
      _activeSwipingMessageId = null;
    }
    _returnController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    if (_activeSwipingMessageId != null &&
        _activeSwipingMessageId != widget.messageId) {
      return;
    }

    if (_returnController.isAnimating) {
      _returnController.stop();
    }

    _activeSwipingMessageId = widget.messageId;
    _isDragging = true;
    _accumulatedDrag = 0.0;
    _currentDisplacement = 0.0;
    _thresholdReached = false;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    if (_activeSwipingMessageId != widget.messageId) return;

    final delta = details.primaryDelta ?? 0.0;

    setState(() {
      _accumulatedDrag += delta;

      // Lock direction:
      if (widget.isMe) {
        // Only negative (drag left) allowed
        if (_accumulatedDrag > 0) _accumulatedDrag = 0;
      } else {
        // Only positive (drag right) allowed
        if (_accumulatedDrag < 0) _accumulatedDrag = 0;
      }

      final rawMagnitude = _accumulatedDrag.abs();

      // 1:1 finger tracking up to 65px, then rubber-band resistance
      if (rawMagnitude <= _kMaxDragLimit) {
        _currentDisplacement = rawMagnitude;
      } else {
        final excess = rawMagnitude - _kMaxDragLimit;
        _currentDisplacement =
            (_kMaxDragLimit + (excess * 0.22)).clamp(0.0, _kMaxDisplacementCap);
      }

      // 45px trigger threshold check
      if (_currentDisplacement >= _kTriggerThreshold && !_thresholdReached) {
        _thresholdReached = true;
        HapticFeedback.lightImpact();
        _bounceController.forward(from: 0.0);
      } else if (_currentDisplacement < _kHysteresisThreshold &&
          _thresholdReached) {
        // Finger pulled back below threshold before release -> reset trigger
        _thresholdReached = false;
      }
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    if (_activeSwipingMessageId == widget.messageId) {
      _activeSwipingMessageId = null;
    }

    final triggered = _thresholdReached;
    final startDisplacement = _currentDisplacement;

    if (startDisplacement <= 0.0) {
      _thresholdReached = false;
      return;
    }

    if (triggered) {
      // User passed threshold -> fire reply
      widget.onSwipeReply();

      // Spring / overshoot return curve (~280ms)
      _returnController.duration = const Duration(milliseconds: 280);
      _returnAnimation = Tween<double>(
        begin: startDisplacement,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _returnController,
        curve: Curves.easeOutBack,
      ));
    } else {
      // Released before 45px -> smooth ease-out return (~180ms)
      _returnController.duration = const Duration(milliseconds: 180);
      _returnAnimation = Tween<double>(
        begin: startDisplacement,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _returnController,
        curve: Curves.easeOutCubic,
      ));
    }

    _thresholdReached = false;
    _returnController.forward(from: 0.0);
  }

  void _handleDragCancel() {
    if (!_isDragging) return;
    _isDragging = false;
    if (_activeSwipingMessageId == widget.messageId) {
      _activeSwipingMessageId = null;
    }

    _thresholdReached = false;
    final startDisplacement = _currentDisplacement;

    if (startDisplacement > 0.0) {
      _returnController.duration = const Duration(milliseconds: 180);
      _returnAnimation = Tween<double>(
        begin: startDisplacement,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _returnController,
        curve: Curves.easeOutCubic,
      ));
      _returnController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Displacement value clamped for visuals
    final double displayDistance =
        _currentDisplacement.clamp(0.0, _kMaxDisplacementCap);

    // Opacity: 0 to 20px -> 0.0; 20 to 45px -> 0.0 to 1.0; >= 45px -> 1.0
    final double iconOpacity = displayDistance < 20.0
        ? 0.0
        : ((displayDistance - 20.0) / (_kTriggerThreshold - 20.0))
            .clamp(0.0, 1.0);

    // Scale: 0 to 20px -> 0.6; 20 to 45px -> 0.6 to 1.0; plus bounce pop
    final double baseScale = displayDistance < 20.0
        ? 0.6
        : (0.6 +
                0.4 *
                    ((displayDistance - 20.0) / (_kTriggerThreshold - 20.0))
                        .clamp(0.0, 1.0))
            .clamp(0.6, 1.0);
    final double bounceMultiplier =
        _bounceController.isAnimating ? _bounceAnimation.value : 1.0;
    final double iconScale = baseScale * bounceMultiplier;

    // Translation along X axis:
    // If isMe: bubble translates to the left (-_currentDisplacement)
    // If !isMe: bubble translates to the right (+_currentDisplacement)
    final double translationX =
        widget.isMe ? -_currentDisplacement : _currentDisplacement;

    final recognizer = <Type, GestureRecognizerFactory>{
      DirectionalHorizontalDragGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<
              DirectionalHorizontalDragGestureRecognizer>(
        () => DirectionalHorizontalDragGestureRecognizer(isMe: widget.isMe),
        (DirectionalHorizontalDragGestureRecognizer instance) {
          instance
            ..isMe = widget.isMe
            ..onStart = _handleDragStart
            ..onUpdate = _handleDragUpdate
            ..onEnd = _handleDragEnd
            ..onCancel = _handleDragCancel;
        },
      ),
    };

    return RawGestureDetector(
      gestures: recognizer,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          // ── Reply Arrow Icon Behind Bubble ────────────────────────────────
          Positioned(
            left: widget.isMe ? null : 16.0,
            right: widget.isMe ? 16.0 : null,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: iconOpacity,
                child: Transform.scale(
                  scale: iconScale,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? const Color(0xFF2563EB).withValues(alpha: 0.22)
                          : const Color(0xFF2563EB).withValues(alpha: 0.12),
                    ),
                    child: Center(
                      child: Transform.flip(
                        // If !isMe (received message): user swipes right -> flip arrow so it points right towards the bubble
                        // If isMe (own message): user swipes left -> default Icons.reply_rounded points left towards the bubble
                        flipX: !widget.isMe,
                        child: const Icon(
                          Icons.reply_rounded,
                          size: 19,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── The Message Bubble (Translated by Finger) ─────────────────────
          Transform.translate(
            offset: Offset(translationX, 0.0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
