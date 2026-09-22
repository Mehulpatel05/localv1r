import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/user_profile.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

enum FeedbackCategory {
  bug('Report a Bug', Icons.bug_report_outlined),
  feature('Feature Idea', Icons.lightbulb_outline),
  general('General Feedback', Icons.chat_bubble_outline),
  support('Need Help', Icons.help_outline);

  const FeedbackCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Production-ready Feedback & Support page strictly adhering to Nearhood B&W design system.
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
    // Pre-fill contact with user's phone or email if available
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
      final user = FirebaseAuth.instance.currentUser;
      final storedUid = await AuthService.instance.getUserId();
      final effectiveUid = user?.uid ?? storedUid ?? '';

      await FirebaseFirestore.instance.collection('feedback').add({
        'handle': widget.profile.handle,
        'userId': effectiveUid,
        'category': _selectedCategory.name,
        'categoryLabel': _selectedCategory.label,
        'subject': _subjectController.text.trim(),
        'message': message,
        'contact': _contactController.text.trim(),
        'phone': widget.profile.phone,
        'email': widget.profile.email,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
        'platform': 'flutter_mobile',
      });

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
    final c = context.nearhoodColors;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: TextStyle(color: c.btnink, fontWeight: FontWeight.w600, fontSize: 13.5),
            textAlign: TextAlign.center,
          ),
          backgroundColor: c.danger,
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
        text: 'Nearhood Support Query from @${widget.profile.handle}:\n'
            'Category: ${_selectedCategory.label}\n'
            'Message: ${_messageController.text.trim().isNotEmpty ? _messageController.text.trim() : "[Your question/feedback here]"}',
        subject: 'Nearhood Support - @${widget.profile.handle}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nearhoodColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: _isSubmitted ? _buildSuccessView(c) : _buildFormView(c),
      ),
    );
  }

  Widget _buildSuccessView(NearhoodColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.field,
                shape: BoxShape.circle,
                border: Border.all(color: c.line, width: 1.5),
              ),
              child: Icon(
                Icons.check_rounded,
                size: 38,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Thank You!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.03 * 22,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your feedback has been received. We review every submission carefully to make Nearhood better for everyone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                color: c.muted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 54,
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.btn,
                  foregroundColor: c.btnink,
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

  Widget _buildFormView(NearhoodColors c) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Column(
      children: [
        // Top Bar
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
                    decoration: BoxDecoration(
                      color: c.field,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      size: 19,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Feedback & Support',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.03 * 22,
                  color: c.ink,
                ),
              ),
            ],
          ),
        ),

        // Scrollable Body
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
            children: [
              // User info badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: c.field,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_circle_outlined, size: 20, color: c.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Submitting as @${widget.profile.handle}',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Category Label
              Text(
                'Category',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),

              const SizedBox(height: 10),

              // Category Selector (Wrap of chips)
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
                        color: isSelected ? c.btn : c.bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? c.btn : c.line,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            cat.icon,
                            size: 17,
                            color: isSelected ? c.btnink : c.ink,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            cat.label,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              color: isSelected ? c.btnink : c.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 22),

              // Subject Field
              Text(
                'Subject (Optional)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _subjectController,
                style: TextStyle(fontSize: 15, color: c.ink, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'e.g. Map issue in Alkapuri',
                  hintStyle: TextStyle(fontSize: 14.5, color: c.muted),
                  filled: true,
                  fillColor: c.field,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.ink, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Message Field
              Text(
                'Description / Message',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _messageController,
                maxLines: 5,
                maxLength: 600,
                style: TextStyle(fontSize: 15, color: c.ink, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'Tell us in detail what happened or your idea...',
                  hintStyle: TextStyle(fontSize: 14.5, color: c.muted),
                  filled: true,
                  fillColor: c.field,
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.ink, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Contact Field
              Text(
                'Contact Phone / Email',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contactController,
                style: TextStyle(fontSize: 15, color: c.ink, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'For follow-up updates',
                  hintStyle: TextStyle(fontSize: 14.5, color: c.muted),
                  filled: true,
                  fillColor: c.field,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.ink, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Submit Button
              _SubmitButton(
                onTap: _isSubmitting ? () {} : _submitFeedback,
                isLoading: _isSubmitting,
              ),

              const SizedBox(height: 32),

              // Quick Help Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Direct Support',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Need instant help or want to share logs with the development team?',
                      style: TextStyle(
                        fontSize: 13,
                        color: c.muted,
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
                          color: c.field,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.mail_outline, size: 19, color: c.ink),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Share directly via App / Email',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.ink,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 18, color: c.muted),
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
    final c = context.nearhoodColors;
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
              color: c.btn,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: widget.isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: c.btnink,
                    ),
                  )
                : Text(
                    'Submit Feedback',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.btnink,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
