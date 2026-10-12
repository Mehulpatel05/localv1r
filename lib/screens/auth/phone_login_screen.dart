import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../services/post_repository.dart';
import '../../core/constants/app_static_assets.dart';
import '../../core/widgets/safe_image.dart';
import '../../services/auth_service.dart';
import '../safety/legal_and_rules_screen.dart';
import 'otp_verify_screen.dart';

class PhoneLoginScreen extends StatefulWidget {
  final PostRepository repository;

  const PhoneLoginScreen({super.key, required this.repository});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isValidPhone {
    final text = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    return text.length == 10 && RegExp(r'^[6-9]').hasMatch(text);
  }

  Future<void> _handleSendOtp() async {
    final rawPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (rawPhone.length != 10) {
      setState(() {
        _errorMessage = 'Please enter a valid 10-digit mobile number.';
      });
      return;
    }

    if (!RegExp(r'^[6-9]').hasMatch(rawPhone)) {
      setState(() {
        _errorMessage = 'Indian mobile numbers must start with 6, 7, 8, or 9.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final e164Phone = '+91$rawPhone';
    final result = await AuthService.instance.sendOtp(e164Phone);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      final requestId = result['requestId'] as String;
      final expiresIn = result['expiresIn'] as int? ?? 300;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerifyScreen(
            repository: widget.repository,
            phoneNumber: e164Phone,
            requestId: requestId,
            expiresInSeconds: expiresIn,
          ),
        ),
      );
    } else {
      setState(() {
        _errorMessage = result['error'] ?? 'Failed to send OTP. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SafeImage(
                  imageUrl: AppStaticAssets.logo,
                  width: 220,
                  height: 160,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 8),

                const Text(
                  'one app. every local need.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),

                const Text(
                  'Sign in to explore and connect with your city.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 36),

                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.errorSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.errorSoftText, fontSize: 13, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '🇮🇳 +91',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          focusNode: _focusNode,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: AppColors.textPrimary,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: const InputDecoration(
                            hintText: 'Enter Mobile Number',
                            hintStyle: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 15,
                              fontWeight: FontWeight.normal,
                              letterSpacing: 0,
                            ),
                            border: InputBorder.none,
                          ),
                          onChanged: (_) {
                            if (_errorMessage != null) {
                              setState(() => _errorMessage = null);
                            }
                          },
                          onSubmitted: (_) {
                            if (!_isLoading && _isValidPhone) {
                              _handleSendOtp();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      disabledBackgroundColor: AppColors.primarySoft,
                    ),
                    onPressed: _isLoading ? null : _handleSendOtp,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Send OTP',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                Text.rich(
                  TextSpan(
                    text: 'By continuing, you agree to Nearhood\'s ',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: 'Terms of Service',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
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
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
