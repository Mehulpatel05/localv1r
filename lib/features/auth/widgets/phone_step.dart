import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/auth_repository.dart';
import '../../../screens/safety/legal_and_rules_screen.dart';
import '../../../theme/app_colors.dart';

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
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final Color borderColor;
    if (_isInvalidTenDigits) {
      borderColor = AppColors.error;
    } else if (_isFocused) {
      borderColor = const Color(0xFF0E8A3E);
    } else {
      borderColor = const Color(0xFFE2E8F0);
    }

    final List<BoxShadow> boxShadows = [];
    if (_isFocused && !_isInvalidTenDigits) {
      boxShadows.add(
        BoxShadow(
          color: const Color(0xFF0E8A3E).withValues(alpha: 0.12),
          spreadRadius: 4,
          blurRadius: 0,
        ),
      );
    } else if (_isInvalidTenDigits) {
      boxShadows.add(
        BoxShadow(
          color: AppColors.error.withValues(alpha: 0.12),
          spreadRadius: 4,
          blurRadius: 0,
        ),
      );
    }

    final isButtonEnabled = _isValid && !_isLoading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        28,
        24,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter your\nphone number',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: Color(0xFF0F172A),
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "We'll send a 6-digit code by SMS.",
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
              color: Color(0xFF64748B),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Mobile number',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: _isFocused ? 1.8 : 1.2),
              boxShadow: boxShadows,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 14, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '🇮🇳',
                        style: TextStyle(fontSize: 19),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '+91',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1.2,
                  height: 28,
                  color: const Color(0xFFE2E8F0),
                ),
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
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: Color(0xFF0F172A),
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14),
                        isDense: true,
                        hintText: '10-digit mobile number',
                        hintStyle: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
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
                        decoration: const BoxDecoration(
                          color: Color(0xFF0E8A3E),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const CustomPaint(
                          size: Size(12, 12),
                          painter: _CheckmarkPainter(Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 20),
              child: Text(
                _isInvalidTenDigits
                    ? 'Enter a valid Indian mobile number starting with 6–9.'
                    : "We'll send a 6-digit code by SMS.",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _isInvalidTenDigits ? AppColors.error : const Color(0xFF64748B),
                  height: 1.25,
                ),
              ),
            ),
          ),
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
                            'Send OTP',
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
          const SizedBox(height: 18),
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
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text.rich(
              TextSpan(
                text: 'By continuing, you agree to Nearhood’s ',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: 'Terms of Service',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0E8A3E),
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        LegalAndRulesScreen.open(context, initialTab: 1);
                      },
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0E8A3E),
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        LegalAndRulesScreen.open(context, initialTab: 2);
                      },
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          _buildCommunityTrustCard(),
        ],
      ),
    );
  }

  Widget _buildCommunityTrustCard() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.location_city_rounded,
                size: 18,
                color: Color(0xFF0E8A3E),
              ),
              SizedBox(width: 8),
              Text(
                'Vadodara\'s Neighborhood Network',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildTrustBullet(
            Icons.lock_outline_rounded,
            '100% Private: Your mobile number is never displayed to other users.',
          ),
          const SizedBox(height: 8),
          _buildTrustBullet(
            Icons.people_outline_rounded,
            'Real Neighbors: Connect with verified residents in your own area.',
          ),
          const SizedBox(height: 8),
          _buildTrustBullet(
            Icons.campaign_outlined,
            'Local Alerts: Instant neighborhood news, urgent updates & local recommendations.',
          ),
        ],
      ),
    );
  }

  Widget _buildTrustBullet(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
              height: 1.35,
            ),
          ),
        ),
      ],
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
    path.moveTo(size.width * (4 / 24), size.height * (12 / 24));
    path.lineTo(size.width * (9 / 24), size.height * (17 / 24));
    path.lineTo(size.width * (20 / 24), size.height * (6 / 24));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CheckmarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
