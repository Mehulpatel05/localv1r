import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_auth/smart_auth.dart';
import '../../../core/auth_repository.dart';
import '../../../theme/app_colors.dart';

class OtpStep extends StatefulWidget {
  final String phone;
  final AuthRepository authRepository;
  final VoidCallback onChangeNumber;
  final FutureOr<void> Function() onVerified;

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

class _OtpStepState extends State<OtpStep>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
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

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _focusNodes[0].requestFocus();
      }
    });

    _startResendTimer();
    _listenForSmsOtp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_isOtpComplete) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted && !_isOtpComplete) {
          final targetIndex = _controllers.indexWhere((c) => c.text.isEmpty);
          final idx = targetIndex == -1 ? _otpLength - 1 : targetIndex;
          _focusNodes[idx].requestFocus();
        }
      });
    }
  }

  void _listenForSmsOtp() async {
    try {
      final res = await SmartAuth.instance.getSmsWithUserConsentApi(matcher: r'\d{6}');
      final code = res.data?.code ??
          (res.data?.sms != null
              ? RegExp(r'\b\d{6}\b').firstMatch(res.data!.sms)?.group(0)
              : null);
      if (code != null && mounted) {
        final digits = code.replaceAll(RegExp(r'\D'), '');
        if (digits.length >= _otpLength) {
          for (int i = 0; i < _otpLength; i++) {
            _controllers[i].text = digits[i];
          }
          setState(() {
            _hasError = false;
          });
          _verifyOtp();
        }
      }
    } catch (e) {
      debugPrint('[OtpStep] SmartAuth listen error: $e');
    }
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
    WidgetsBinding.instance.removeObserver(this);
    SmartAuth.instance.removeUserConsentApiListener();
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
      if (digits.length == _otpLength) {
        _verifyOtp();
      }
      return;
    }

    if (value.isNotEmpty) {
      if (index < _otpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      }
    }
    setState(() {});
    if (_isOtpComplete) {
      _verifyOtp();
    }
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
    try {
      debugPrint('[OtpStep] Starting OTP verification for ${widget.phone}...');
      final success = await widget.authRepository.verifyOtp(widget.phone, otpCode);
      debugPrint('[OtpStep] verifyOtp returned success=$success');

      if (!mounted) return;

      if (success) {
        debugPrint('[OtpStep] Invoking onVerified() callback...');
        await widget.onVerified();
        debugPrint('[OtpStep] onVerified() completed.');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
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
    } catch (e, stack) {
      debugPrint('[OtpStep] FATAL error in _verifyOtp: $e\n$stack');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
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
    _listenForSmsOtp();
    widget.authRepository.sendOtp(widget.phone);
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final isButtonEnabled = _isOtpComplete && !_isLoading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        28,
        24,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      '← Change number',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0E8A3E),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Text(
              'Enter the code',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: Color(0xFF0F172A),
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sent to ${_formatPhoneNumber(widget.phone)}',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w400,
                color: Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
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
                    boxBorderColor = AppColors.error;
                  } else if (isFocused) {
                    boxBorderColor = const Color(0xFF0E8A3E);
                  } else {
                    boxBorderColor = const Color(0xFFE2E8F0);
                  }

                  final List<BoxShadow> shadows = [];
                  if (isFocused && !_hasError) {
                    shadows.add(
                      BoxShadow(
                        color: const Color(0xFF0E8A3E).withValues(alpha: 0.12),
                        spreadRadius: 4,
                        blurRadius: 0,
                      ),
                    );
                  } else if (_hasError) {
                    shadows.add(
                      BoxShadow(
                        color: AppColors.error.withValues(alpha: 0.12),
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
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: boxBorderColor,
                                width: isFocused ? 1.8 : 1.2,
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
                              autofillHints: const [AutofillHints.oneTimeCode],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (val) => _onDigitChanged(index, val),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
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
                          color: AppColors.error,
                          height: 1.3,
                        ),
                      )
                    : const SizedBox(height: 20),
              ),
            ),
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
                        backgroundColor: const Color(0xFF0E8A3E),
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Verify and continue',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isButtonEnabled
                                    ? Colors.white
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: _secondsRemaining > 0
                    ? Text(
                        'Resend code in 0:${_secondsRemaining.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF64748B),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Didn’t get it? ',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: 'Resend OTP',
                            child: GestureDetector(
                              onTap: _onResendTapped,
                              child: const Text(
                                'Resend OTP',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0E8A3E),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: Color(0xFF0E8A3E),
                ),
                SizedBox(width: 6),
                Text(
                  'Verified neighbours only',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0E8A3E),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
