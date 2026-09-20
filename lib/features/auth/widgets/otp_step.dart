import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/auth_repository.dart';
import '../../../core/theme.dart';

/// OTP step matching the exact HTML/CSS specification:
/// - Back button: "← Change number" (14px, 700, var(--ink), margin-bottom 12)
/// - Headline: "Enter the code" (28px, 800, -0.035em)
/// - Subtitle: "Sent to +91 XXXXX XXXXX" (14.5px, muted)
/// - 6 OTP boxes: height 58, radius 14, background var(--field), font 22px 700
/// - Focus: border var(--ink), background var(--bg), 4px 9% glow
/// - Primary button: height 54, radius 16, background var(--btn), disabled var(--field2)
/// - Resend text: "Resend code in 0:30" / "Didn't get it? Resend OTP" (bold underline)
class OtpStep extends StatefulWidget {
  final String phone;
  final AuthRepository authRepository;
  final VoidCallback onChangeNumber;
  final VoidCallback onVerified;

  const OtpStep({
    super.key,
    required this.phone,
    required this.authRepository,
    required this.onChangeNumber,
    required this.onVerified,
  });

  @override
  State<OtpStep> createState() => _OtpStepState();
}

class _OtpStepState extends State<OtpStep> with SingleTickerProviderStateMixin {
  static const int _otpLength = 6;
  static const int _resendCountdownDuration = 30;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late final AnimationController _shakeController;

  Timer? _timer;
  int _secondsRemaining = _resendCountdownDuration;
  bool _isLoading = false;
  bool _isPressed = false;
  bool _hasError = false;
  int? _focusedIndex;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_otpLength, (_) => TextEditingController());
    _focusNodes = List.generate(_otpLength, (index) {
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus && mounted) {
          setState(() {
            _focusedIndex = index;
          });
        } else if (!node.hasFocus && _focusedIndex == index && mounted) {
          setState(() {
            _focusedIndex = null;
          });
        }
      });
      return node;
    });

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Autofocus first box after ~50ms
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _focusNodes[0].requestFocus();
      }
    });

    _startResendTimer();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() {
      _secondsRemaining = _resendCountdownDuration;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shakeController.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    for (final ctrl in _controllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String get _currentOtp =>
      _controllers.map((controller) => controller.text).join();

  bool get _isOtpComplete =>
      _controllers.every((controller) => controller.text.isNotEmpty);

  String _formatPhoneNumber(String raw) {
    if (raw.length == 10) {
      return '+91 ${raw.substring(0, 5)} ${raw.substring(5)}';
    }
    return '+91 $raw';
  }

  void _onDigitChanged(int index, String value) {
    if (_hasError) {
      setState(() {
        _hasError = false;
      });
    }

    // Handle 6-digit paste
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < _otpLength; i++) {
        if (i < digits.length) {
          _controllers[i].text = digits[i];
        }
      }
      final focusTarget =
          digits.length < _otpLength ? digits.length : _otpLength - 1;
      _focusNodes[focusTarget].requestFocus();
      setState(() {});
      return;
    }

    if (value.isNotEmpty) {
      if (index < _otpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      }
    }
    setState(() {});
  }

  KeyEventResult _handleKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isEmpty && index > 0) {
        _focusNodes[index - 1].requestFocus();
        _controllers[index - 1].text = '';
        setState(() {});
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _verifyOtp() async {
    if (!_isOtpComplete || _isLoading) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final otpCode = _currentOtp;
    final success = await widget.authRepository.verifyOtp(widget.phone, otpCode);

    if (!mounted) return;

    if (success) {
      setState(() {
        _isLoading = false;
      });
      widget.onVerified();
    } else {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });

      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (!disableAnimations) {
        _shakeController.forward(from: 0.0);
      }
    }
  }

  void _onResendTapped() {
    for (final controller in _controllers) {
      controller.clear();
    }
    setState(() {
      _hasError = false;
    });
    _focusNodes[0].requestFocus();
    _startResendTimer();
    widget.authRepository.sendOtp(widget.phone);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nearhoodColors;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final isButtonEnabled = _isOtpComplete && !_isLoading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Back button: "← Change number" (font-size 14px, weight 700, margin-bottom 12px)
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: 'Change number',
              child: GestureDetector(
                onTap: () {
                  _timer?.cancel();
                  widget.onChangeNumber();
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '← Change number',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Headline: 28px, 800, -0.035em
          Text(
            'Enter the code',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.035 * 28,
              color: colors.ink,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),

          // Subtitle: "Sent to +91 XXXXX XXXXX" (14.5px, muted, 1.45)
          Text(
            'Sent to ${_formatPhoneNumber(widget.phone)}',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
              color: colors.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),

          // 6 OTP boxes in a row (gap 9px, height 58, radius 14)
          AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              double offset = 0.0;
              if (_shakeController.isAnimating && !disableAnimations) {
                offset = math.sin(_shakeController.value * math.pi * 6) * 8.0;
              }
              return Transform.translate(
                offset: Offset(offset, 0),
                child: child,
              );
            },
            child: Row(
              children: List.generate(_otpLength, (index) {
                final isFocused = _focusedIndex == index;
                final Color boxBorderColor;
                if (_hasError) {
                  boxBorderColor = colors.danger;
                } else if (isFocused) {
                  boxBorderColor = colors.ink;
                } else {
                  boxBorderColor = Colors.transparent;
                }

                final List<BoxShadow> shadows = [];
                if (isFocused && !_hasError) {
                  shadows.add(
                    BoxShadow(
                      color: colors.ink.withValues(alpha: 0.09),
                      spreadRadius: 4,
                      blurRadius: 0,
                    ),
                  );
                } else if (_hasError) {
                  shadows.add(
                    BoxShadow(
                      color: colors.danger.withValues(alpha: 0.12),
                      spreadRadius: 4,
                      blurRadius: 0,
                    ),
                  );
                }

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index < _otpLength - 1 ? 9.0 : 0.0,
                    ),
                    child: Semantics(
                      label: 'Digit ${index + 1} of 6',
                      child: Focus(
                        onKeyEvent: (node, event) =>
                            _handleKeyEvent(index, event),
                        child: AnimatedContainer(
                          duration: disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          height: 58,
                          decoration: BoxDecoration(
                            color: isFocused ? colors.bg : colors.field,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: boxBorderColor,
                              width: 1.5,
                            ),
                            boxShadow: shadows,
                          ),
                          alignment: Alignment.center,
                          child: TextField(
                            controller: _controllers[index],
                            focusNode: _focusNodes[index],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            autofillHints: index == 0
                                ? const [AutofillHints.oneTimeCode]
                                : null,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (val) => _onDigitChanged(index, val),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: colors.ink,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              counterText: '',
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // Hint / Error message area: min-height 20, margin 8px 0 12px
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 20),
              child: _hasError
                  ? Text(
                      'Incorrect code. Try again.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: colors.danger,
                        height: 1.3,
                      ),
                    )
                  : const SizedBox(height: 20),
            ),
          ),

          // Primary button: height 54, radius 16, background var(--btn)
          Semantics(
            button: true,
            enabled: isButtonEnabled,
            label: 'Verify and continue',
            child: GestureDetector(
              onTapDown: isButtonEnabled
                  ? (_) => setState(() => _isPressed = true)
                  : null,
              onTapUp: isButtonEnabled
                  ? (_) => setState(() => _isPressed = false)
                  : null,
              onTapCancel: () => setState(() => _isPressed = false),
              child: AnimatedScale(
                scale: _isPressed && !disableAnimations ? 0.985 : 1.0,
                duration: const Duration(milliseconds: 100),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: isButtonEnabled ? _verifyOtp : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.btn,
                      disabledBackgroundColor: colors.field2,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colors.btnink,
                              ),
                            ),
                          )
                        : Text(
                            'Verify and continue',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isButtonEnabled
                                  ? colors.btnink
                                  : colors.muted,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),

          // Resend countdown row: margin-top 14, 13.5px, var(--muted)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Center(
              child: _secondsRemaining > 0
                  ? Text(
                      'Resend code in 0:${_secondsRemaining.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        color: colors.muted,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Didn’t get it? ',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w400,
                            color: colors.muted,
                          ),
                        ),
                        Semantics(
                          button: true,
                          label: 'Resend OTP',
                          child: GestureDetector(
                            onTap: _onResendTapped,
                            child: Text(
                              'Resend OTP',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: colors.ink,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
