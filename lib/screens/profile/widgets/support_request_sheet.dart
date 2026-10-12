import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../../models/support_ticket_model.dart';
import '../../../services/auth_service.dart';
import '../../../services/support_ticket_service.dart';
import '../../../theme/app_colors.dart';

enum _SupportStep { faq, form, submitted }

enum _Priority { normal, urgent }

class _Faq {
  final String question;
  final String answer;
  const _Faq({required this.question, required this.answer});
}

const List<_Faq> _faqs = [
  _Faq(
    question: 'Why is my location not being detected?',
    answer:
        'Open Settings → Location → set to "Always On". Make sure GPS is enabled. Force-close the app and reopen. Nearhood only works inside Vadodara city limits.',
  ),
  _Faq(
    question: 'I did not receive the OTP.',
    answer:
        'Check your mobile number is correct. Wait 60 seconds before retrying. Ensure you have network signal and SMS is not blocked by your carrier.',
  ),
  _Faq(
    question: 'How do I report a scam or fake listing?',
    answer:
        'Tap the three-dot menu on the listing and select "Report". Our team reviews reports within 24 hours. For emergencies, use the Urgent priority ticket.',
  ),
  _Faq(
    question: 'How to delete my account and data?',
    answer:
        'Go to Settings → Delete My Account. All your posts, chats, media, and data will be permanently and instantly wiped.',
  ),
  _Faq(
    question: 'How do Bazar shop verifications work?',
    answer:
        'Shop verifications require a valid Vadodara shop address and business proof. Once submitted, our local field team verifies details within 48 business hours.',
  ),
];

const List<String> _categories = [
  'Location / GPS Issue',
  'Login / OTP Problem',
  'Report Scam or Fake User',
  'Bazar / Listing Problem',
  'Chat or Calling Bug',
  'Other / General Feedback',
];

class SupportRequestSheet extends StatefulWidget {
  final String userHandle;
  final String? initialPhone;
  final int initialTab;

  const SupportRequestSheet({
    super.key,
    required this.userHandle,
    this.initialPhone,
    this.initialTab = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required String userHandle,
    String? initialPhone,
    int initialTab = 0,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => SupportRequestSheet(
        userHandle: userHandle,
        initialPhone: initialPhone,
        initialTab: initialTab,
      ),
    );
  }

  @override
  State<SupportRequestSheet> createState() => _SupportRequestSheetState();
}

class _SupportRequestSheetState extends State<SupportRequestSheet>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0;
  _SupportStep _step = _SupportStep.faq;
  _Priority _priority = _Priority.normal;
  String _selectedCategory = 'Location / GPS Issue';
  bool _isSubmitting = false;
  String? _errorMessage;
  String _ticketId = '';
  SupportTicketModel? _lastCreatedTicket;
  SupportTicketModel? _selectedTrackingTicket;

  final _phoneController = TextEditingController();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();

  late final AnimationController _ticketAnim;
  late final Animation<double> _ticketScale;
  late final Animation<double> _ticketFade;

  int? _expandedFaqIndex;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;

    final cleanPhone = (widget.initialPhone ?? '')
        .replaceAll('+91', '')
        .replaceAll(RegExp(r'\D'), '')
        .trim();
    if (cleanPhone.isNotEmpty) {
      _phoneController.text = cleanPhone;
    }

    _ticketAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _ticketScale = CurvedAnimation(parent: _ticketAnim, curve: Curves.easeOutBack);
    _ticketFade = CurvedAnimation(parent: _ticketAnim, curve: Curves.easeIn);

    SupportTicketService.instance.loadTickets(widget.userHandle);
    SupportTicketService.instance.syncWithBackend(widget.userHandle);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _subjectController.dispose();
    _descriptionController.dispose();
    _ticketAnim.dispose();
    super.dispose();
  }

  String _generateTicketId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(999).toString().padLeft(3, '0');
    return 'NH-${ts.toString().substring(5)}$rand';
  }

  Future<void> _handleSubmit() async {
    final phone = _phoneController.text.trim();
    final description = _descriptionController.text.trim();

    if (phone.length < 10) {
      setState(() => _errorMessage = 'Enter a valid 10-digit mobile number.');
      return;
    }
    if (description.isEmpty) {
      setState(() => _errorMessage = 'Please describe your issue.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final ticketId = _generateTicketId();
    final subject = _subjectController.text.trim();
    final effectiveSubject = subject.isNotEmpty ? subject : _selectedCategory;

    final newTicket = SupportTicketModel(
      ticketId: ticketId,
      userHandle: widget.userHandle,
      phone: '+91 $phone',
      category: _selectedCategory,
      priority: _priority.name,
      subject: effectiveSubject,
      description: description,
      status: 'under_review',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      estimatedHours: _priority == _Priority.urgent ? 2 : 24,
    );

    await SupportTicketService.instance.saveTicket(newTicket);

    try {
      final token = await AuthService.instance.getAccessToken();
      final uri = Uri.parse('${AuthService.baseUrl}/feedback');

      final combinedText =
          'Phone: +91 $phone\n'
          'Handle: ${widget.userHandle}\n'
          'Category: $_selectedCategory\n'
          'Priority: ${_priority.name.toUpperCase()}\n'
          'Subject: $effectiveSubject\n'
          'Ticket: $ticketId\n\n'
          '$description';

      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'category': _selectedCategory,
          'priority': _priority.name,
          'subject': effectiveSubject,
          'feedback_text': combinedText,
          'phone': '+91$phone',
          'ticket_id': ticketId,
          'app_version': '1.0.0',
        }),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _ticketId = ticketId;
        _lastCreatedTicket = newTicket;
        _step = _SupportStep.submitted;
      });
      _ticketAnim.forward();
    }
  }

  void _onTrackSubmittedTicket() {
    setState(() {
      _selectedTab = 1;
      _selectedTrackingTicket = _lastCreatedTicket;
      _step = _SupportStep.faq;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.92;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(
            color: AppColors.divider,
            width: 1.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDragHandle(),
          _buildTopTabBar(),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _selectedTab == 0 ? _buildTabFaqAndRaise() : _buildTabMyTickets(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildTopTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.chipBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_selectedTab != 0) {
                    setState(() {
                      _selectedTab = 0;
                    });
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _selectedTab == 0
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.quiz_outlined,
                        size: 16,
                        color: _selectedTab == 0
                            ? Colors.white
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Help & FAQs',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _selectedTab == 0
                              ? Colors.white
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_selectedTab != 1) {
                    setState(() {
                      _selectedTab = 1;
                    });
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _selectedTab == 1
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: ValueListenableBuilder<List<SupportTicketModel>>(
                    valueListenable: SupportTicketService.instance.ticketsNotifier,
                    builder: (ctx, tickets, _) {
                      final activeCount = tickets.where((t) => !t.isResolved).length;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.confirmation_number_outlined,
                            size: 16,
                            color: _selectedTab == 1
                                ? Colors.white
                                : AppColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'My Tickets',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _selectedTab == 1
                                  ? Colors.white
                                  : AppColors.textMuted,
                            ),
                          ),
                          if (activeCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _selectedTab == 1
                                    ? Colors.white
                                    : AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$activeCount',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: _selectedTab == 1
                                      ? AppColors.primary
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabFaqAndRaise() {
    if (_step == _SupportStep.submitted) {
      return _SubmittedView(
        key: const ValueKey('submitted'),
        ticketId: _ticketId,
        priority: _priority,
        phone: _phoneController.text.trim(),
        scaleAnim: _ticketScale,
        fadeAnim: _ticketFade,
        onClose: () => Navigator.pop(context),
        onTrackTicket: _onTrackSubmittedTicket,
      );
    }

    if (_step == _SupportStep.form) {
      return _FormView(
        key: const ValueKey('form'),
        categories: _categories,
        selectedCategory: _selectedCategory,
        priority: _priority,
        phoneController: _phoneController,
        subjectController: _subjectController,
        descriptionController: _descriptionController,
        isSubmitting: _isSubmitting,
        errorMessage: _errorMessage,
        onCategoryChanged: (v) => setState(() => _selectedCategory = v),
        onPriorityChanged: (v) => setState(() => _priority = v),
        onSubmit: _handleSubmit,
        onBack: () => setState(() => _step = _SupportStep.faq),
      );
    }

    return _FaqView(
      key: const ValueKey('faq'),
      faqs: _faqs,
      expandedIndex: _expandedFaqIndex,
      onToggle: (i) => setState(() {
        _expandedFaqIndex = _expandedFaqIndex == i ? null : i;
      }),
      onRaiseTicket: () => setState(() => _step = _SupportStep.form),
      onClose: () => Navigator.pop(context),
    );
  }

  Widget _buildTabMyTickets() {
    if (_selectedTrackingTicket != null) {
      return _TicketDetailTrackingView(
        key: ValueKey('tracking_${_selectedTrackingTicket!.ticketId}'),
        ticket: _selectedTrackingTicket!,
        onBack: () => setState(() => _selectedTrackingTicket = null),
      );
    }

    return _MyTicketsListView(
      key: const ValueKey('tickets_list'),
      userHandle: widget.userHandle,
      onSelectTicket: (ticket) => setState(() {
        _selectedTrackingTicket = ticket;
      }),
      onRaiseTicket: () => setState(() {
        _selectedTab = 0;
        _step = _SupportStep.form;
      }),
    );
  }
}

class _FaqView extends StatelessWidget {
  const _FaqView({
    super.key,
    required this.faqs,
    required this.expandedIndex,
    required this.onToggle,
    required this.onRaiseTicket,
    required this.onClose,
  });

  final List<_Faq> faqs;
  final int? expandedIndex;
  final void Function(int) onToggle;
  final VoidCallback onRaiseTicket;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Help & Support',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const Text(
                          'Online · Responds in ~2 hrs',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22, color: AppColors.textMuted),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Common Questions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(faqs.length, (i) {
            final faq = faqs[i];
            final isOpen = expandedIndex == i;
            return _FaqTile(
              faq: faq,
              isOpen: isOpen,
              onTap: () => onToggle(i),
            );
          }),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.chipBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.divider,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Still need help?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Raise a support ticket and our Vadodara team will get back to you.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onRaiseTicket,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Raise a Support Ticket',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.faq,
    required this.isOpen,
    required this.onTap,
  });

  final _Faq faq;
  final bool isOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isOpen ? AppColors.surface : AppColors.chipBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isOpen
                ? AppColors.primary
                : AppColors.divider,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: isOpen ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    faq.question,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            if (isOpen) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  faq.answer,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  const _FormView({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.priority,
    required this.phoneController,
    required this.subjectController,
    required this.descriptionController,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onCategoryChanged,
    required this.onPriorityChanged,
    required this.onSubmit,
    required this.onBack,
  });

  final List<String> categories;
  final String selectedCategory;
  final _Priority priority;
  final TextEditingController phoneController;
  final TextEditingController subjectController;
  final TextEditingController descriptionController;
  final bool isSubmitting;
  final String? errorMessage;
  final void Function(String) onCategoryChanged;
  final void Function(_Priority) onPriorityChanged;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22, color: AppColors.textPrimary),
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Raise Support Ticket',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Vadodara ops team assigns tickets in ~15 mins',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'ISSUE CATEGORY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories.map((cat) {
              final isSel = cat == selectedCategory;
              return _CategoryChip(
                label: cat,
                isSelected: isSel,
                onTap: () => onCategoryChanged(cat),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          const Text(
            'PRIORITY LEVEL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PriorityTile(
                  priority: _Priority.normal,
                  isSelected: priority == _Priority.normal,
                  label: 'Normal',
                  sub: 'Responds within ~24h',
                  icon: Icons.schedule_rounded,
                  color: AppColors.primary,
                  onTap: () => onPriorityChanged(_Priority.normal),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PriorityTile(
                  priority: _Priority.urgent,
                  isSelected: priority == _Priority.urgent,
                  label: 'Urgent',
                  sub: 'Responds within ~2h',
                  icon: Icons.bolt_rounded,
                  color: const Color(0xFFD97706),
                  onTap: () => onPriorityChanged(_Priority.urgent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'CONTACT MOBILE NUMBER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              prefixText: '+91 ',
              prefixStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
              hintText: 'Enter 10-digit number',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.chipBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'SUBJECT (OPTIONAL)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: subjectController,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Brief summary of the issue',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.chipBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'DESCRIPTION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: descriptionController,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Tell us what happened so we can assist you quickly...',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.chipBg,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.errorSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFCA5A5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          _SubmitButton(isLoading: isSubmitting, onTap: onSubmit),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primarySoft
              : AppColors.chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.primaryText : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _PriorityTile extends StatelessWidget {
  const _PriorityTile({
    required this.priority,
    required this.isSelected,
    required this.label,
    required this.sub,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final _Priority priority;
  final bool isSelected;
  final String label;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : AppColors.chipBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: isSelected ? color : AppColors.textMuted),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? color : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              sub,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? color : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitButton extends StatefulWidget {
  const _SubmitButton({
    required this.isLoading,
    required this.onTap,
  });

  final bool isLoading;
  final VoidCallback onTap;

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.isLoading) widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'Submit Support Request',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SubmittedView extends StatelessWidget {
  const _SubmittedView({
    super.key,
    required this.ticketId,
    required this.priority,
    required this.phone,
    required this.scaleAnim,
    required this.fadeAnim,
    required this.onClose,
    required this.onTrackTicket,
  });

  final String ticketId;
  final _Priority priority;
  final String phone;
  final Animation<double> scaleAnim;
  final Animation<double> fadeAnim;
  final VoidCallback onClose;
  final VoidCallback onTrackTicket;

  String get _eta => priority == _Priority.urgent ? '~2 hours' : '~24 hours';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: FadeTransition(
        opacity: fadeAnim,
        child: ScaleTransition(
          scale: scaleAnim,
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Ticket Raised Successfully!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Our team will contact you on +91 $phone within $_eta.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              _TicketIdCard(ticketId: ticketId, priority: priority),
              const SizedBox(height: 16),
              const _StatusTimeline(currentStepIndex: 1),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onTrackTicket,
                  icon: const Icon(Icons.track_changes_rounded, size: 18),
                  label: const Text(
                    'Track Ticket Status',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: onClose,
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
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

class _TicketIdCard extends StatefulWidget {
  const _TicketIdCard({
    required this.ticketId,
    required this.priority,
  });

  final String ticketId;
  final _Priority priority;

  @override
  State<_TicketIdCard> createState() => _TicketIdCardState();
}

class _TicketIdCardState extends State<_TicketIdCard> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.ticketId));
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = widget.priority == _Priority.urgent;
    final badgeColor = isUrgent ? const Color(0xFFD97706) : AppColors.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.chipBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'TICKET ID',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUrgent ? Icons.bolt_rounded : Icons.schedule_rounded,
                      size: 11,
                      color: badgeColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isUrgent ? 'URGENT' : 'NORMAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.ticketId,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              GestureDetector(
                onTap: _copy,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _copied
                        ? AppColors.primarySoft
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _copied
                          ? AppColors.primary
                          : AppColors.divider,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 13,
                        color: _copied ? AppColors.primary : AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _copied ? 'Copied' : 'Copy',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _copied ? AppColors.primary : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFFD97706),
                    shape: BoxShape.circle,
                  ),
                ),
                const Text(
                  'Under Review',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({
    this.currentStepIndex = 1,
  });

  final int currentStepIndex;

  @override
  Widget build(BuildContext context) {
    final stepLabels = [
      'Ticket Received',
      'Under Review',
      'Agent Assigned',
      'Resolved',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.chipBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Timeline Progress',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(stepLabels.length, (i) {
            final isDone = i <= currentStepIndex;
            final isCurrent = i == currentStepIndex;
            final isLast = i == stepLabels.length - 1;

            Color stepColor;
            if (isCurrent && i < stepLabels.length - 1) {
              stepColor = const Color(0xFFD97706);
            } else if (isDone) {
              stepColor = AppColors.primary;
            } else {
              stepColor = AppColors.textMuted;
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone ? stepColor : AppColors.surface,
                        border: Border.all(
                          color: isDone ? stepColor : AppColors.divider,
                          width: 1.5,
                        ),
                      ),
                      child: isDone
                          ? const Icon(
                              Icons.check_rounded,
                              size: 13,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    if (!isLast)
                      Container(
                        width: 1.5,
                        height: 22,
                        color: isDone
                            ? stepColor.withValues(alpha: 0.4)
                            : AppColors.divider,
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                  child: Row(
                    children: [
                      Text(
                        stepLabels[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isDone ? FontWeight.w700 : FontWeight.w500,
                          color: isDone ? AppColors.textPrimary : AppColors.textMuted,
                        ),
                      ),
                      if (isCurrent && i < stepLabels.length - 1) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _MyTicketsListView extends StatefulWidget {
  const _MyTicketsListView({
    super.key,
    required this.userHandle,
    required this.onSelectTicket,
    required this.onRaiseTicket,
  });

  final String userHandle;
  final void Function(SupportTicketModel) onSelectTicket;
  final VoidCallback onRaiseTicket;

  @override
  State<_MyTicketsListView> createState() => _MyTicketsListViewState();
}

class _MyTicketsListViewState extends State<_MyTicketsListView> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SupportTicketModel>>(
      valueListenable: SupportTicketService.instance.ticketsNotifier,
      builder: (ctx, allTickets, _) {
        final filteredTickets = allTickets.where((t) {
          if (_filter == 'active') return !t.isResolved;
          if (_filter == 'resolved') return t.isResolved;
          return true;
        }).toList();

        if (allTickets.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Icon(
                      Icons.confirmation_number_outlined,
                      size: 34,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'No Support Tickets Yet',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Whenever you raise a ticket, you can track its review progress and status updates right here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: widget.onRaiseTicket,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        'Raise a Support Ticket',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final activeCount = allTickets.where((t) => !t.isResolved).length;
        final resolvedCount = allTickets.where((t) => t.isResolved).length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Row(
                children: [
                  _buildFilterChip('All (${allTickets.length})', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Active ($activeCount)', 'active'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Resolved ($resolvedCount)', 'resolved'),
                ],
              ),
            ),
            Expanded(
              child: filteredTickets.isEmpty
                  ? Center(
                      child: Text(
                        'No $_filter tickets found',
                        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: filteredTickets.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) {
                        final ticket = filteredTickets[i];
                        return _TicketCard(
                          ticket: ticket,
                          onTap: () => widget.onSelectTicket(ticket),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSel = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel
              ? AppColors.primarySoft
              : AppColors.chipBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSel
                ? AppColors.primary
                : AppColors.divider,
            width: isSel ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            color: isSel ? AppColors.primaryText : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.onTap,
  });

  final SupportTicketModel ticket;
  final VoidCallback onTap;

  Color get _statusColor {
    switch (ticket.status.toLowerCase()) {
      case 'resolved':
      case 'closed':
        return AppColors.primary;
      case 'in_progress':
        return AppColors.primaryText;
      default:
        return const Color(0xFFD97706);
    }
  }

  String _formatRelativeDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 2) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM y').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = ticket.isUrgent;
    final statusColor = _statusColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.divider,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  ticket.ticketId,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    fontFamily: 'monospace',
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                if (isUrgent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, size: 10, color: Color(0xFFD97706)),
                        SizedBox(width: 2),
                        Text(
                          'URGENT',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        ticket.statusDisplayName,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ticket.subject.isNotEmpty ? ticket.subject : ticket.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ticket.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  _formatRelativeDate(ticket.createdAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                const SizedBox(width: 10),
                const Text('•', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                const SizedBox(width: 10),
                Text(
                  ticket.category,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                const Spacer(),
                const Row(
                  children: [
                    Text(
                      'Track',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketDetailTrackingView extends StatelessWidget {
  const _TicketDetailTrackingView({
    super.key,
    required this.ticket,
    required this.onBack,
  });

  final SupportTicketModel ticket;
  final VoidCallback onBack;

  Color get _statusColor {
    switch (ticket.status.toLowerCase()) {
      case 'resolved':
      case 'closed':
        return AppColors.primary;
      case 'in_progress':
        return AppColors.primaryText;
      default:
        return const Color(0xFFD97706);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
    final isUrgent = ticket.isUrgent;
    final formattedDate =
        DateFormat('d MMMM yyyy, h:mm a').format(ticket.createdAt);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22, color: AppColors.textPrimary),
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Ticket #${ticket.ticketId}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    fontFamily: 'monospace',
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      ticket.statusDisplayName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _TicketIdCard(
            ticketId: ticket.ticketId,
            priority: isUrgent ? _Priority.urgent : _Priority.normal,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.chipBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 16, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text(
                      'ESTIMATED RESOLUTION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isUrgent
                      ? 'Target response within ~2 hours (High Priority)'
                      : 'Target response within ~24 hours (Standard Priority)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Our Vadodara customer experience team monitors tickets 7 days a week.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _StatusTimeline(currentStepIndex: ticket.statusStepIndex),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.chipBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TICKET SUMMARY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                _buildSummaryRow('Subject', ticket.subject),
                const SizedBox(height: 8),
                _buildSummaryRow('Category', ticket.category),
                const SizedBox(height: 8),
                _buildSummaryRow('Contact', ticket.phone),
                const SizedBox(height: 8),
                _buildSummaryRow('Submitted', formattedDate),
                const SizedBox(height: 12),
                const Text(
                  'Description',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    ticket.description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: ticket.ticketId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ticket ID copied to clipboard'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text(
                'Copy Ticket ID',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
