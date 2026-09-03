import 'package:flutter/material.dart';
import '../../services/post_repository.dart';

class GrievanceCenterScreen extends StatefulWidget {
  final PostRepository repository;

  const GrievanceCenterScreen({super.key, required this.repository});

  @override
  State<GrievanceCenterScreen> createState() => _GrievanceCenterScreenState();
}

class _GrievanceCenterScreenState extends State<GrievanceCenterScreen> {
  final _emailController = TextEditingController();
  final _postLinkController = TextEditingController();
  final _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_onRepositoryUpdated);
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onRepositoryUpdated);
    _emailController.dispose();
    _postLinkController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _onRepositoryUpdated() {
    if (mounted) setState(() {});
  }

  void _submitGrievance() {
    if (_formKey.currentState!.validate()) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF151D30),
          title: const Text('Grievance Filed Successfully', style: TextStyle(color: Colors.white)),
          content: Text(
            'Under Section 79 of IT Rules 2021, your ticket has been registered. Our Grievance Officer in Vadodara will process this request within the 24-hour statutory timeline.\n\nTicket Reference ID: VL-GR-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _emailController.clear();
                _postLinkController.clear();
                _reasonController.clear();
              },
              child: const Text('OK', style: TextStyle(color: Color(0xFF3B82F6))),
            )
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportedPosts = widget.repository.reportedPosts;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D30),
        elevation: 0,
        title: const Text(
          'Compliance & Grievance',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Safe Harbour Notice Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.gavel, color: Colors.amberAccent, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Indian Intermediary Safe Harbour',
                              style: TextStyle(color: Colors.amberAccent.shade100, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'This application operates under Section 79 of the Information Technology Act, 2000. We comply with Intermediary Guidelines (IT Rules 2021) and the Digital Personal Data Protection (DPDP) Act 2023. \n\nWe provide a mechanism to report and take down illegal content, defamation, intellectual property theft, or privacy violations within statutory timelines.',
                          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Grievance contact details
                  const Text(
                    'DESIGNATED GRIEVANCE OFFICER DETAILS',
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151D30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF243049)),
                    ),
                    child: const Column(
                      children: [
                        _GrievanceInfoRow(icon: Icons.person_outline, title: 'Officer Name', value: 'R. K. Patel (Compliance Lead)'),
                        Divider(color: Color(0xFF243049)),
                        _GrievanceInfoRow(icon: Icons.email_outlined, title: 'Email Address', value: 'grievance@vadodaralocal.in'),
                        Divider(color: Color(0xFF243049)),
                        _GrievanceInfoRow(icon: Icons.business_outlined, title: 'Office Location', value: 'Alkapuri, Vadodara, Gujarat, India'),
                        Divider(color: Color(0xFF243049)),
                        _GrievanceInfoRow(icon: Icons.timer_outlined, title: 'Legal Takedown SLA', value: 'Within 24 Hours'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Interactive Content Removal Request Form
                  const Text(
                    'FILE A TAKEDOWN / COMPLAINT TICKET',
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Identify the post or comment violating rules and submit below. We will investigate and remove compliant content immediately.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 14),

                  // Email input
                  TextFormField(
                    controller: _emailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Your Contact Email (Will be kept private)',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF151D30),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF243049)),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty || !val.contains('@')) {
                        return 'Please enter a valid contact email for compliance response.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Target content description
                  TextFormField(
                    controller: _postLinkController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Identifier / Handle of Post / Target Area',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF151D30),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF243049)),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please describe which post/content should be evaluated.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Detailed reason
                  TextFormField(
                    controller: _reasonController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Detailed Reason for Removal Request',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF151D30),
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF243049)),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please describe the violation (harassment, doxxing, misinformation).';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.send),
                      label: const Text('File Formal Grievance', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _submitGrievance,
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),

            // SIMULATED MODERATOR REVIEW QUEUE
            const Divider(color: Color(0xFF243049)),
            const SizedBox(height: 16),
            const Text(
              '⚖️ COMMUNITY MODERATOR QUEUE (MVP DEMO)',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
            ),
            const SizedBox(height: 10),
            const Text(
              'As a trusted resident moderator, you can review flagged content below and take action to either Restore or Permanently Ban the post.',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),

            if (reportedPosts.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1F293D)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All clean! There are no flagged posts currently pending moderation review.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: reportedPosts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final post = reportedPosts[index];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              post.authorHandle,
                              style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(width: 6),
                            const Text('•', style: TextStyle(color: Colors.white24)),
                            const SizedBox(width: 6),
                            Text(
                              'Vadodara',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          post.content,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Button to Restore
                            TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
                              icon: const Icon(Icons.restore, size: 16),
                              label: const Text('Restore Post', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                widget.repository.restorePost(post.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFF10B981),
                                    content: Text('Post restored back to community feed.'),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            // Button to delete permanently
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7F1D1D),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              icon: const Icon(Icons.delete_forever, size: 16),
                              label: const Text('Ban & Delete', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                widget.repository.deletePostPermanently(post.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFFEF4444),
                                    content: Text('Post deleted and creator handle flagged.'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _GrievanceInfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _GrievanceInfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF60A5FA), size: 18),
          const SizedBox(width: 10),
          Text(
            '$title:',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
