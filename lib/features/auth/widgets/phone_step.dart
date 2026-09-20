import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/auth_repository.dart';
import '../../../core/theme.dart';

/// Phone step matching the exact HTML/CSS specification:
/// - Headline: "One app.<br>Every local need." (32px, 800, line-height 1.1, -0.035em)
/// - Subtitle: "Sign in to find trusted services and people around you." (14.5px, muted, 1.45)
/// - Input field: height 58, radius 16, background var(--field), 1.5px border
/// - Focus-within: border-color var(--ink), background var(--bg), 4px 9% glow
/// - Valid check tick: 22x22 circle, background var(--btn), color var(--btnink)
/// - Primary button: height 54, radius 16, background var(--btn), disabled var(--field2)
/// - Legal text: underline bold var(--ink) links
class PhoneStep extends StatefulWidget {
  final AuthRepository authRepository;
  final ValueChanged<String> onPhoneSubmitted;

  const PhoneStep({
    super.key,
    required this.authRepository,
    required this.onPhoneSubmitted,
  });

  @override
  State<PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends State<PhoneStep> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isFocused = false;
  bool _isPressed = false;
  bool _isLoading = false;
  String _phoneText = '';

  static final RegExp _validPattern = RegExp(r'^[6-9]\d{9}$');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _isValid => _validPattern.hasMatch(_phoneText);
  bool get _isInvalidTenDigits => _phoneText.length == 10 && !_isValid;

  Future<void> _submitPhone() async {
    if (!_isValid || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.authRepository.sendOtp(_phoneText);
      if (mounted) {
        widget.onPhoneSubmitted(_phoneText);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send OTP: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nearhoodColors;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // Field border and background logic from CSS
    final Color borderColor;
    if (_isInvalidTenDigits) {
      borderColor = colors.danger;
    } else if (_isFocused) {
      borderColor = colors.ink;
    } else {
      borderColor = Colors.transparent;
    }

    final List<BoxShadow> boxShadows = [];
    if (_isFocused && !_isInvalidTenDigits) {
      boxShadows.add(
        BoxShadow(
          color: colors.ink.withValues(alpha: 0.09),
          spreadRadius: 4,
          blurRadius: 0,
        ),
      );
    } else if (_isInvalidTenDigits) {
      boxShadows.add(
        BoxShadow(
          color: colors.danger.withValues(alpha: 0.12),
          spreadRadius: 4,
          blurRadius: 0,
        ),
      );
    }

    final isButtonEnabled = _isValid && !_isLoading;

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
          // Headline: 32px, 800, line-height 1.1, -0.035em
          Text(
            'One app.\nEvery local need.',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.035 * 32,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 8),

          // Subtitle: 14.5px, line-height 1.45, var(--muted)
          Text(
            'Sign in to find trusted services and people around you.',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
              height: 1.45,
              color: colors.muted,
            ),
          ),
          const SizedBox(height: 22),

          // Field Container: height 58, radius 16, background var(--field)
          AnimatedContainer(
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            height: 58,
            decoration: BoxDecoration(
              color: _isFocused ? colors.bg : colors.field,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: boxShadows,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Country Code segment: 🇮🇳 +91, padding 0 14px 0 16px, 1.5px divider
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '🇮🇳',
                        style: TextStyle(fontSize: 19),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '+91',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.ink,
                        ),
                      ),
                    ],
                  ),
                ),

                // 1.5px right divider in var(--line)
                Container(
                  width: 1.5,
                  height: 28,
                  color: colors.line,
                ),

                // Mobile number input
                Expanded(
                  child: Semantics(
                    label: 'Mobile number',
                    textField: true,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _phoneText = val;
                        });
                      },
                      onSubmitted: (_) {
                        if (_isValid) {
                          _submitPhone();
                        }
                      },
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.04 * 18,
                        color: colors.ink,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                        isDense: true,
                        hintText: '10-digit mobile number',
                        hintStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: colors.muted.withValues(alpha: 0.8),
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),

                // Far right: 22px circle with checkmark
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: AnimatedScale(
                    scale: _isValid ? 1.0 : (disableAnimations ? 0.0 : 0.6),
                    duration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: _isValid ? 1.0 : 0.0,
                      duration: disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      child: Container(
                        key: const Key('phone_valid_tick'),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: colors.btn,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: CustomPaint(
                          size: const Size(12, 12),
                          painter: _CheckmarkPainter(colors.btnink),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Hint area: min-height 20, margin 8px 0 12px, 12.5px
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 20),
              child: Text(
                _isInvalidTenDigits
                    ? 'Enter a valid Indian mobile number starting with 6–9.'
                    : "We'll send a 6-digit code by SMS.",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: _isInvalidTenDigits ? colors.danger : colors.muted,
                  height: 1.3,
                ),
              ),
            ),
          ),

          // Primary button: height 54, radius 16, background var(--btn)
          Semantics(
            button: true,
            enabled: isButtonEnabled,
            label: 'Send OTP',
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
                    onPressed: isButtonEnabled ? _submitPhone : null,
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
                            'Send OTP',
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

          // Legal text: margin-top 14, 12px, line-height 1.5, var(--muted)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text.rich(
              TextSpan(
                text: 'By continuing, you agree to Nearhood’s ',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.muted,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: 'Terms of Service',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        // TODO: Navigate to Terms of Service
                      },
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        // TODO: Navigate to Privacy Policy
                      },
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  final Color color;
  const _CheckmarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // SVG viewBox: 0 0 24 24, points="20 6 9 17 4 12"
    path.moveTo(size.width * (4 / 24), size.height * (12 / 24));
    path.lineTo(size.width * (9 / 24), size.height * (17 / 24));
    path.lineTo(size.width * (20 / 24), size.height * (6 / 24));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CheckmarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
