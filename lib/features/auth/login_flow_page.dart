import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/auth_repository.dart';
import '../../core/splash_controller.dart';
import '../../services/auth_service.dart';
import '../../services/call_listener_service.dart';
import '../../services/notification_service.dart';
import '../../services/post_repository.dart';
import '../../services/presence_service.dart';
import '../../screens/auth/create_handle_screen.dart';
import '../../screens/main/main_screen.dart';
import 'widgets/hero_section.dart';
import 'widgets/otp_step.dart';
import 'widgets/phone_step.dart';

enum AuthStep { phone, otp }

class LoginFlowPage extends StatefulWidget {
  final AuthRepository authRepository;
  final PostRepository? postRepository;
  final FutureOr<void> Function()? onLoggedIn;

  const LoginFlowPage({
    super.key,
    required this.authRepository,
    this.postRepository,
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

  Future<void> _onOtpVerified() async {
    final repo = widget.postRepository ?? PostRepository.instance;
    final loc = repo.locationService;
    try {
      final prefs = await SharedPreferences.getInstance();
      final handle = (await AuthService.instance.getUserHandle()) ?? prefs.getString('user_handle') ?? '';
      final userId = (await AuthService.instance.getUserId()) ?? prefs.getString('user_id') ?? '';
      final phone = (await AuthService.instance.getPhoneNumber()) ?? prefs.getString('phone_number') ?? '';

      final isNewUser = AuthService.isNewUserHandle(handle);
      debugPrint('[LoginFlowPage] _onOtpVerified: handle="$handle", userId=$userId, isNewUser=$isNewUser');

      if (isNewUser) {
        if (mounted) {
          debugPrint('[LoginFlowPage] Pushing CreateHandleScreen with Navigator.of(context)...');
          await Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => CreateHandleScreen(
                repository: repo,
                userId: userId,
                phoneNumber: phone,
              ),
            ),
            (route) => false,
          );
        }
      } else {
        repo.currentUserHandle = handle;
        NotificationService().initialize();
        NotificationService().startListening(handle);
        PresenceService.instance.init(handle);
        CallListenerService.instance.startListening(handle);

        SplashController.instance.warmFetchOnLogin(
          uid: userId,
          handle: handle,
          cityId: loc.cityId.isNotEmpty ? loc.cityId : 'GJ-VAD',
          postRepo: repo,
        );

        if (widget.onLoggedIn != null) {
          await widget.onLoggedIn!();
        } else if (mounted) {
          await Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => MainScreen(
                repository: repo,
                currentUserHandle: handle,
              ),
            ),
            (route) => false,
          );
        }
      }
    } catch (e, stack) {
      debugPrint('[LoginFlowPage] Error in _onOtpVerified: $e\n$stack');
      if (widget.onLoggedIn != null) {
        await widget.onLoggedIn!();
      } else if (mounted) {
        final handle = (await AuthService.instance.getUserHandle()) ?? '';
        if (handle.isNotEmpty && mounted) {
          repo.currentUserHandle = handle;
          await Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => MainScreen(
                repository: repo,
                currentUserHandle: handle,
              ),
            ),
            (route) => false,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOtp = _currentStep == AuthStep.otp;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return PopScope(
      canPop: _currentStep == AuthStep.phone && Navigator.canPop(context),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentStep == AuthStep.otp) {
          setState(() {
            _currentStep = AuthStep.phone;
          });
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
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
      ),
    );
  }
}
