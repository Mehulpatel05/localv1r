import 'package:flutter/material.dart';
import '../../models/community_model.dart';
import '../../services/community_repository.dart';

class JoinRequestsScreen extends StatefulWidget {
  final CommunityModel community;
  final CommunityRepository repository;

  const JoinRequestsScreen({
    super.key,
    required this.community,
    required this.repository,
  });

  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends State<JoinRequestsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _requests = [];
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    final reqs = await widget.repository.getJoinRequests(widget.community.id);
    if (mounted) {
      setState(() {
        _requests = reqs;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleResponse(String requestId, bool approve) async {
    setState(() {
      _processingIds.add(requestId);
    });
    try {
      await widget.repository.respondJoinRequest(widget.community.id, requestId, approve);
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r['id'] == requestId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'Request approved.' : 'Request declined.'),
            backgroundColor: approve ? const Color(0xFF16A34A) : Colors.black87,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingIds.remove(requestId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Join Requests', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.how_to_reg_outlined, size: 56, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 12),
                      const Text(
                        'No pending join requests',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'When users ask to join, they will appear here.',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _requests.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final req = _requests[index];
                    final reqId = req['id']?.toString() ?? '';
                    final userHandle = req['userHandle']?.toString() ?? 'User';
                    final isProcessing = _processingIds.contains(reqId);

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFF3B82F6),
                            child: Text(
                              userHandle.isNotEmpty ? userHandle[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '@$userHandle',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Requested ${req['createdAt'] ?? 'recently'}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          if (isProcessing)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.red),
                                  tooltip: 'Decline',
                                  onPressed: () => _handleResponse(reqId, false),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.check_rounded, color: Color(0xFF16A34A)),
                                  tooltip: 'Approve',
                                  onPressed: () => _handleResponse(reqId, true),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
