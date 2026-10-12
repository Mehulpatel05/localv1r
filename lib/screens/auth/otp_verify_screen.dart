import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_auth/smart_auth.dart';
import '../../theme/app_colors.dart';
import '../../services/post_repository.dart';
import '../../services/presence_service.dart';
import '../../services/notification_service.dart';
import '../../services/auth_service.dart';
import '../main/main_screen.dart';
import '../onboarding/permission_request_screen.dart';
import 'create_handle_screen.dart';

class OtpVerifyScreen extends StatefulWidget {
  final PostRepository repository;
  final String phoneNumber;
  final String requestId;
  final int expiresInSeconds;

  const OtpVerifyScreen({
    super.key,
    required this.repository,
    required this.phoneNumber,
    required this.requestId,
    this.expiresInSeconds = 300,
  });

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  late String _currentRequestId;
  final List<TextEditingController> _digitControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;

  int _resendCooldown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentRequestId = widget.requestId;
    _startCooldownTimer();
    _listenForSmsOtp();
  }

  void _listenForSmsOtp() {
    try {
      SmartAuth.instance.getSmsWithRetrieverApi(matcher: r'\d{6}').then((res) {
        if (!mounted) return;
        final raw = res.data?.code ??
            (res.data?.sms != null
                ? RegExp(r'\b\d{6}\b').firstMatch(res.data!.sms)?.group(0)
                : null);
        if (raw != null && raw.isNotEmpty) {
          _populateAndVerifyOtp(raw);
        }
      }).catchError((e) {
        debugPrint('[OtpVerifyScreen] Retriever API error: $e');
      });

      SmartAuth.instance.getSmsWithUserConsentApi(matcher: r'\d{6}').then((res) {
        if (!mounted) return;
        final raw = res.data?.code ??
            (res.data?.sms != null
                ? RegExp(r'\b\d{6}\b').firstMatch(res.data!.sms)?.group(0)
                : null);
        if (raw != null && raw.isNotEmpty) {
          _populateAndVerifyOtp(raw);
        }
      }).catchError((e) {
        debugPrint('[OtpVerifyScreen] UserConsent API error: $e');
      });
    } catch (e) {
      debugPrint('[OtpVerifyScreen] SmartAuth listen error: $e');
    }
  }

  void _populateAndVerifyOtp(String raw) {
    if (!mounted || _isVerifying) return;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 6) {
      for (int i = 0; i < 6; i++) {
        _digitControllers[i].text = digits[i];
      }
      setState(() {
        _errorMessage = null;
      });
      _handleVerify();
    }
  }

  void _startCooldownTimer() {
    _resendCooldown = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    SmartAuth.instance.removeUserConsentApiListener();
    _timer?.cancel();
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _enteredOtp => _digitControllers.map((c) => c.text).join();

  Future<void> _handleVerify() async {
    final otp = _enteredOtp;
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter the complete 6-digit code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final result = await AuthService.instance.verifyOtp(
      requestId: _currentRequestId,
      otp: otp,
      phoneNumber: widget.phoneNumber,
    );

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (result['success'] == true) {
      final handle = result['handle'] as String? ?? '';
      final isNewUser = result['isNewUser'] == true || handle.isEmpty || handle.startsWith('Anon#');
      final userId = result['userId'] as String? ?? '';

      if (isNewUser) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => CreateHandleScreen(
              repository: widget.repository,
              userId: userId,
              phoneNumber: widget.phoneNumber,
            ),
          ),
          (route) => false,
        );
      } else {
        widget.repository.currentUserHandle = handle;
        NotificationService().initialize();
        PresenceService.instance.init(handle);

        final prefs = await SharedPreferences.getInstance();
        final permsDone = prefs.getString('perms_done');

        if (!mounted) return;
        if (permsDone == 'true') {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => MainScreen(
                repository: widget.repository,
                currentUserHandle: handle,
              ),
            ),
            (route) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => PermissionRequestScreen(
                onComplete: (permContext) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setString('perms_done', 'true');
                  if (permContext.mounted) {
                    Navigator.of(permContext).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => MainScreen(
                          repository: widget.repository,
                          currentUserHandle: handle,
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
            (route) => false,
          );
        }
      }
    } else {
      setState(() {
        _errorMessage = result['error'] ?? 'Incorrect OTP code. Please try again.';
      });
    }
  }

  Future<void> _handleResend() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    final result = await AuthService.instance.sendOtp(widget.phoneNumber);

    if (!mounted) return;
    setState(() => _isResending = false);

    if (result['success'] == true) {
      _currentRequestId = result['requestId'] as String;
      for (final c in _digitControllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
      _startCooldownTimer();
      _listenForSmsOtp();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A new OTP has been sent.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() {
        _errorMessage = result['error'] ?? 'Failed to resend OTP. Please try again.';
      });
    }
  }

  void _onDigitChanged(int index, String value) {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }

    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6; i++) {
        if (i < digits.length) {
          _digitControllers[i].text = digits[i];
        }
      }
      final focusTarget = digits.length < 6 ? digits.length : 5;
      _focusNodes[focusTarget].requestFocus();
      setState(() {});
      if (digits.length == 6) {
        _handleVerify();
      }
      return;
    }

    if (value.length == 1) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        if (_enteredOtp.length == 6) {
          _handleVerify();
        }
      }
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.mark_email_read_outlined, color: AppColors.primary, size: 32),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Enter Verification Code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),

                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.4),
                    children: [
                      const TextSpan(text: 'We sent a 6-digit code to '),
                      TextSpan(
                        text: widget.phoneNumber,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

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
                  const SizedBox(height: 24),
                ],

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 48,
                      height: 56,
                      child: TextField(
                        controller: _digitControllers[index],
                        focusNode: _focusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: EdgeInsets.zero,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.divider, width: 1.2),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.primary, width: 2),
                          ),
                        ),
                        onChanged: (val) => _onDigitChanged(index, val),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),

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
                  ),
                  onPressed: _isVerifying ? null : _handleVerify,
                  child: _isVerifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Verify & Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Didn\'t receive code? ',
                    style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                  ),
                  _resendCooldown > 0
                      ? Text(
                          'Resend in ${_resendCooldown}s',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        )
                      : TextButton(
                          onPressed: _isResending ? null : _handleResend,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: _isResending
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'Resend OTP',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                        ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
