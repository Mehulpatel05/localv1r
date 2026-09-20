import 'package:flutter/material.dart';
import '../../core/auth_repository.dart';
import '../../core/theme.dart';
import 'widgets/hero_section.dart';
import 'widgets/otp_step.dart';
import 'widgets/phone_step.dart';

enum AuthStep { phone, otp }

/// Production-quality Login Flow matching the exact Nearhood Black & White design.
class LoginFlowPage extends StatefulWidget {
  final AuthRepository authRepository;
  final VoidCallback? onLoggedIn;

  const LoginFlowPage({
    super.key,
    required this.authRepository,
    this.onLoggedIn,
  });

  @override
  State<LoginFlowPage> createState() => _LoginFlowPageState();
}

class _LoginFlowPageState extends State<LoginFlowPage> {
  AuthStep _currentStep = AuthStep.phone;
  String _phone = '';

  void _onPhoneSubmitted(String phone) {
    setState(() {
      _phone = phone;
      _currentStep = AuthStep.otp;
    });
  }

  void _onChangeNumber() {
    setState(() {
      _currentStep = AuthStep.phone;
    });
  }

  void _onOtpVerified() {
    if (widget.onLoggedIn != null) {
      widget.onLoggedIn!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nearhoodColors;
    final isOtp = _currentStep == AuthStep.otp;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: colors.bg,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // Top Section (300px for Login, 210px for OTP)
            AnimatedContainer(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.ease,
              child: TopSection(
                key: ValueKey(isOtp),
                isOtp: isOtp,
              ),
            ),

            // Form Area (Scrollable to prevent keyboard overflow)
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: AnimatedSwitcher(
                  duration: disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.ease,
                  switchOutCurve: const Threshold(0),
                  transitionBuilder: (child, animation) {
                    if (disableAnimations) return child;

                    final isIncoming = child.key == ValueKey(_currentStep);
                    if (!isIncoming) {
                      return const SizedBox.shrink();
                    }

                    // Matching CSS @keyframes in { from { opacity: 0; transform: translateX(8px); } to { opacity: 1; transform: none; } }
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, childWidget) {
                        final progress = Curves.ease.transform(animation.value);
                        final dx = (1.0 - progress) * 8.0;
                        return Opacity(
                          opacity: animation.value.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(dx, 0),
                            child: childWidget,
                          ),
                        );
                      },
                      child: child,
                    );
                  },
                  child: isOtp
                      ? OtpStep(
                          key: const ValueKey(AuthStep.otp),
                          phone: _phone,
                          authRepository: widget.authRepository,
                          onChangeNumber: _onChangeNumber,
                          onVerified: _onOtpVerified,
                        )
                      : PhoneStep(
                          key: const ValueKey(AuthStep.phone),
                          authRepository: widget.authRepository,
                          onPhoneSubmitted: _onPhoneSubmitted,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
