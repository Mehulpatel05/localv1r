import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';

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
    if (isMe && globalDistanceMoved >= 0) {
      return false;
    }
    if (!isMe && globalDistanceMoved <= 0) {
      return false;
    }
    return super.hasSufficientGlobalDistanceToAccept(
      pointerDeviceKind,
      deviceTouchSlop,
    );
  }
}

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
  static String? _activeSwipingMessageId;

  late AnimationController _returnController;
  late Animation<double> _returnAnimation;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  double _accumulatedDrag = 0.0;
  double _currentDisplacement = 0.0;
  bool _thresholdReached = false;
  bool _isDragging = false;

  static const double _kTriggerThreshold = 30.0;
  static const double _kHysteresisThreshold = 25.0;
  static const double _kMaxDragLimit = 60.0;
  static const double _kMaxDisplacementCap = 60.0;

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

      if (widget.isMe) {
        if (_accumulatedDrag > 0) _accumulatedDrag = 0;
      } else {
        if (_accumulatedDrag < 0) _accumulatedDrag = 0;
      }

      final rawMagnitude = _accumulatedDrag.abs();

      if (rawMagnitude <= _kMaxDragLimit) {
        _currentDisplacement = rawMagnitude;
      } else {
        final excess = rawMagnitude - _kMaxDragLimit;
        _currentDisplacement =
            (_kMaxDragLimit + (excess * 0.22)).clamp(0.0, _kMaxDisplacementCap);
      }

      if (_currentDisplacement >= _kTriggerThreshold && !_thresholdReached) {
        _thresholdReached = true;
        HapticFeedback.lightImpact();
        _bounceController.forward(from: 0.0);
      } else if (_currentDisplacement < _kHysteresisThreshold &&
          _thresholdReached) {
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
      widget.onSwipeReply();

      _returnController.duration = const Duration(milliseconds: 250);
      _returnAnimation = Tween<double>(
        begin: startDisplacement,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _returnController,
        curve: Curves.easeOutBack,
      ));
    } else {
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
    final double displayDistance =
        _currentDisplacement.clamp(0.0, _kMaxDisplacementCap);

    final double iconOpacity = displayDistance < 20.0
        ? 0.0
        : ((displayDistance - 20.0) / (_kTriggerThreshold - 20.0))
            .clamp(0.0, 1.0);

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
                      color: AppColors.primarySoft,
                    ),
                    child: Center(
                      child: Transform.flip(
                        flipX: !widget.isMe,
                        child: Icon(
                          Icons.reply_rounded,
                          size: 19,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(translationX, 0.0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
