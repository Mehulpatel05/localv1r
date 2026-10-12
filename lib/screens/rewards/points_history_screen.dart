import 'package:flutter/material.dart';
import '../../models/rewards_model.dart';
import '../../services/rewards_service.dart';

class PointsHistoryScreen extends StatefulWidget {
  const PointsHistoryScreen({super.key});

  @override
  State<PointsHistoryScreen> createState() => _PointsHistoryScreenState();
}

class _PointsHistoryScreenState extends State<PointsHistoryScreen> {
  String _selectedFilter = 'all';
  List<PointsLedgerEntry> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final items = await RewardsService.instance.fetchHistory(filter: _selectedFilter);
    if (mounted) {
      setState(() {
        _history = items;
        _isLoading = false;
      });
    }
  }

  void _onFilterChanged(String filter) {
    if (_selectedFilter == filter) return;
    setState(() => _selectedFilter = filter);
    _loadHistory();
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF16243A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Points History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF16243A),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Earned', 'earned'),
                const SizedBox(width: 8),
                _buildFilterChip('Spent', 'spent'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0E8A3E)))
                : _history.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _history.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _history[index];
                          final isPositive = item.delta > 0;
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFD5ECDD), width: 0.8),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isPositive ? const Color(0xFFE8F6EF) : const Color(0xFFFEF3C7),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPositive ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                                    size: 22,
                                    color: isPositive ? const Color(0xFF0E8A3E) : const Color(0xFFD97706),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.reason,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF16243A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatDate(item.createdAt),
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF5C6B7D),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  isPositive ? '+${item.delta} pts' : '${item.delta} pts',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isPositive ? const Color(0xFF0E8A3E) : const Color(0xFFD97706),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => _onFilterChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0E8A3E) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : const Color(0xFF5C6B7D),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_toggle_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            const Text(
              'No points history found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF16243A)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Earn points by creating posts, replying, or listing items in Bazaar!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF5C6B7D)),
            ),
          ],
        ),
      ),
    );
  }
}
