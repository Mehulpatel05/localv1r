import 'package:flutter/material.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/rewards_model.dart';
import '../../services/rewards_service.dart';
import '../../core/services/name_cache_service.dart';

class LeaderboardScreen extends StatefulWidget {
  final String currentUserHandle;
  final String? areaId;

  const LeaderboardScreen({
    super.key,
    required this.currentUserHandle,
    this.areaId,
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardItem> _items = [];
  int _currentUserRank = -1;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    final res = await RewardsService.instance.fetchLeaderboard(
      areaId: widget.areaId ?? 'GJ-VAD',
    );
    if (mounted) {
      setState(() {
        _items = (res['leaderboard'] as List<dynamic>?)?.whereType<LeaderboardItem>().toList() ?? [];
        _currentUserRank = res['currentUserRank'] as int? ?? -1;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim().toLowerCase();
    final isInTop10 = _items.any((item) => item.handle.toLowerCase() == cleanHandle);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF16243A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          children: [
            Text(
              'Top Neighbours',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF16243A),
              ),
            ),
            Text(
              'This week · Vadodara',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFF5C6B7D),
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0E8A3E)))
          : _items.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        itemCount: _items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _buildLeaderRow(item, item.handle.toLowerCase() == cleanHandle);
                        },
                      ),
                    ),
                    if (!isInTop10 && _currentUserRank > 0)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: const Border(top: BorderSide(color: Color(0xFFD5ECDD), width: 1)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, -3),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          top: false,
                          child: _buildLeaderRow(
                            LeaderboardItem(
                              rank: _currentUserRank,
                              handle: widget.currentUserHandle,
                              displayName: 'You',
                              avatarUrl: '',
                              points: RewardsService.instance.summary?.weeklyPoints ?? 0,
                            ),
                            true,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      color: const Color(0xFFF7FBF9),
                      child: const Center(
                        child: Text(
                          'Top 10 refresh every Monday · 00:00 IST',
                          style: TextStyle(fontSize: 11, color: Color(0xFF5C6B7D)),
                        ),
                      ),
                    ),
                  ],
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
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events_outlined, size: 30, color: Color(0xFFD97706)),
            ),
            const SizedBox(height: 14),
            const Text(
              'No activity yet this week',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF16243A)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Post something or reply to lead the neighbourhood board!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Color(0xFF5C6B7D)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderRow(LeaderboardItem item, bool isCurrentUser) {
    final isTop3 = item.rank <= 3;
    Color rankColor = const Color(0xFF5C6B7D);
    Color rankBg = const Color(0xFFF1F5F9);
    if (item.rank == 1) {
      rankColor = const Color(0xFFB45309);
      rankBg = const Color(0xFFFEF3C7);
    } else if (item.rank == 2) {
      rankColor = const Color(0xFF475569);
      rankBg = const Color(0xFFE2E8F0);
    } else if (item.rank == 3) {
      rankColor = const Color(0xFF9A3412);
      rankBg = const Color(0xFFFFEDD5);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isCurrentUser ? const Color(0xFFE8F6EF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser ? const Color(0xFF0E8A3E) : const Color(0xFFD5ECDD),
          width: isCurrentUser ? 1.5 : 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rankBg,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '${item.rank}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          UserAvatar(
            handle: item.handle,
            photoUrl: item.avatarUrl.isNotEmpty ? item.avatarUrl : null,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        getDisplayName(item.handle, fallback: item.displayName),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16243A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.topBadge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.topBadge == 'local_hero' ? 'HERO' : 'HELPER',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isTop3 ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${item.points} pts',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isTop3 ? const Color(0xFFB45309) : const Color(0xFF16243A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
