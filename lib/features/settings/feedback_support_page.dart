import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/name_cache_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';

enum FeedbackCategory {
  bug('Report a Bug', Icons.bug_report_outlined),
  feature('Feature Idea', Icons.lightbulb_outline),
  general('General Feedback', Icons.chat_bubble_outline),
  support('Need Help', Icons.help_outline);

  const FeedbackCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

class FeedbackSupportPage extends StatefulWidget {
  const FeedbackSupportPage({
    super.key,
    required this.profile,
  });

  final UserProfile profile;

  @override
  State<FeedbackSupportPage> createState() => _FeedbackSupportPageState();
}

class _FeedbackSupportPageState extends State<FeedbackSupportPage> {
  FeedbackCategory _selectedCategory = FeedbackCategory.feature;
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();

  bool _isSubmitting = false;
  bool _isSubmitted = false;

  @override
  void initState() {
    super.initState();
    _contactController.text = widget.profile.phone ?? widget.profile.email ?? '';
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      _showErrorSnackBar('Please enter your message or description');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final token = await AuthService.instance.getAccessToken();
      final uri = Uri.parse('${AuthService.baseUrl}/feedback');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'category': _selectedCategory.label,
          'subject': _subjectController.text.trim(),
          'feedback_text': message,
          'contact': _contactController.text.trim(),
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Server returned ${response.statusCode}');
      }

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isSubmitted = true;
        });
      }
    } catch (e) {
      debugPrint('Error submitting feedback: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showErrorSnackBar('Could not submit feedback. Please try again.');
      }
    }
  }

  void _showErrorSnackBar(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
            textAlign: TextAlign.center,
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: const StadiumBorder(),
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
          duration: const Duration(milliseconds: 2500),
        ),
      );
  }

  void _shareViaEmail() {
    SharePlus.instance.share(
      ShareParams(
        text: 'Nearhood Support Query from ${getDisplayName(widget.profile)}:\n'
            'Category: ${_selectedCategory.label}\n'
            'Message: ${_messageController.text.trim().isNotEmpty ? _messageController.text.trim() : "[Your question/feedback here]"}',
        subject: 'Nearhood Support - ${getDisplayName(widget.profile)}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isSubmitted ? _buildSuccessView() : _buildFormView(),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 38,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Thank You!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.03 * 22,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your feedback has been received. We review every submission carefully to make Nearhood better for everyone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                color: AppColors.textMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 54,
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormView() {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Row(
            children: [
              Semantics(
                label: 'Back',
                button: true,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.chipBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      size: 19,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Feedback & Support',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.03 * 22,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_circle_outlined, size: 20, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Submitting as ${getDisplayName(widget.profile)}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Category',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),

              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: FeedbackCategory.values.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.divider,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            cat.icon,
                            size: 17,
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            cat.label,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              color: isSelected ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 22),

              const Text(
                'Subject (Optional)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _subjectController,
                style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'e.g. Map issue in Alkapuri',
                  hintStyle: const TextStyle(fontSize: 14.5, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'Description / Message',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _messageController,
                maxLines: 5,
                maxLength: 600,
                style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'Tell us in detail what happened or your idea...',
                  hintStyle: const TextStyle(fontSize: 14.5, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Contact Phone / Email',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contactController,
                style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'For follow-up updates',
                  hintStyle: const TextStyle(fontSize: 14.5, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              _SubmitButton(
                onTap: _isSubmitting ? () {} : _submitFeedback,
                isLoading: _isSubmitting,
              ),

              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Direct Support',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Need instant help or want to share logs with the development team?',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: _shareViaEmail,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.mail_outline, size: 19, color: AppColors.textPrimary),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Share directly via App / Email',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubmitButton extends StatefulWidget {
  const _SubmitButton({required this.onTap, required this.isLoading});
  final VoidCallback onTap;
  final bool isLoading;

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Semantics(
      button: true,
      label: 'Submit Feedback',
      child: AnimatedScale(
        scale: (_pressed && !disableAnimations && !widget.isLoading) ? 0.985 : 1.0,
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 100),
        child: GestureDetector(
          onTapDown: widget.isLoading ? null : (_) => setState(() => _pressed = true),
          onTapUp: widget.isLoading
              ? null
              : (_) {
                  setState(() => _pressed = false);
                  widget.onTap();
                },
          onTapCancel: () => setState(() => _pressed = false),
          child: Container(
            height: 54,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Submit Feedback',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
