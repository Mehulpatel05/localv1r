import 'package:flutter/material.dart';
import '../../models/rewards_model.dart';
import '../../services/rewards_service.dart';
import 'badges_screen.dart';
import 'leaderboard_screen.dart';
import 'invite_earn_screen.dart';
import 'boost_listing_screen.dart';
import 'shop_perks_screen.dart';
import 'points_history_screen.dart';

class RewardsHubScreen extends StatefulWidget {
  final String currentUserHandle;

  const RewardsHubScreen({
    super.key,
    required this.currentUserHandle,
  });

  @override
  State<RewardsHubScreen> createState() => _RewardsHubScreenState();
}

class _RewardsHubScreenState extends State<RewardsHubScreen> {
  RewardsSummary? _summary;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isClaimingStreak = false;

  @override
  void initState() {
    super.initState();
    _summary = RewardsService.instance.summary;
    RewardsService.instance.addListener(_onRewardsUpdated);
    _loadData();
  }

  @override
  void dispose() {
    RewardsService.instance.removeListener(_onRewardsUpdated);
    super.dispose();
  }

  void _onRewardsUpdated() {
    if (mounted && RewardsService.instance.summary != null) {
      setState(() {
        _summary = RewardsService.instance.summary;
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await RewardsService.instance.fetchSummary(forceRefresh: true);
    if (!mounted) return;

    if (res != null) {
      setState(() {
        _summary = res;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load rewards. Please try again.';
      });
    }
  }

  Future<void> _claimDailyStreak() async {
    if (_isClaimingStreak) return;
    setState(() {
      _isClaimingStreak = true;
    });

    final res = await RewardsService.instance.claimDailyStreak();
    if (!mounted) return;

    setState(() {
      _isClaimingStreak = false;
      if (RewardsService.instance.summary != null) {
        _summary = RewardsService.instance.summary;
      }
    });

    if (res['success'] == true) {
      final pts = (res['pointsAwarded'] as num?)?.toInt() ?? 5;
      final streak = (res['streakCount'] as num?)?.toInt() ?? 1;
      _showStreakClaimSuccessSheet(streak, pts);
    } else {
      final msg = res['message'] ?? 'Could not claim daily reward';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF16243A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showStreakClaimSuccessSheet(int streakDay, int points) {
    if (streakDay == 7) {
      _showStreakCelebrationSheet();
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD5ECDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                size: 38,
                color: Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              streakDay == 7 ? '7-Day Grand Streak! 🎉' : 'Day $streakDay Claimed! 🔥',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF16243A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '+$points Reward Coins added to your wallet!\nCome back tomorrow for Day ${streakDay >= 7 ? 1 : streakDay + 1}.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF5C6B7D),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A0F34),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Awesome!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStreakCelebrationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD5ECDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                size: 38,
                color: Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '7-Day Streak Complete! 🎉',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF16243A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You unlocked the weekly loyalty bonus: +30 Points added to your balance!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF5C6B7D),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A0F34),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Awesome!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF16243A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Rewards',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF16243A),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, size: 22, color: Color(0xFF3A0F34)),
            tooltip: 'Rewards Policy',
            onPressed: _showRewardsRulesModal,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3A0F34)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFF5C6B7D)),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Color(0xFF5C6B7D)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A0F34),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final summary = _summary ?? const RewardsSummary();
    final targetGoal = summary.nextGoalPoints > 0 ? summary.nextGoalPoints : 300;
    final progressRatio = (summary.balance / targetGoal).clamp(0.0, 1.0);

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF3A0F34),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF250921), Color(0xFF3A0F34)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3A0F34).withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your points',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 4),
                            Text(
                              '${summary.lifetimePoints} lifetime',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${summary.balance}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1.05,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context, rootNavigator: true).push(
                          PageRouteBuilder(
                            opaque: true,
                            transitionDuration: const Duration(milliseconds: 260),
                            reverseTransitionDuration: const Duration(milliseconds: 240),
                            pageBuilder: (_, animation, secondaryAnimation) => ShopPerksScreen(currentUserHandle: widget.currentUserHandle),
                            transitionsBuilder: (_, animation, _, child) {
                              final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                              return SlideTransition(
                                position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved),
                                child: child,
                              );
                            },
                          ),
                        ).then((_) => _loadData()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.redeem_rounded, size: 14, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Redeem',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progressRatio,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    summary.pointsToNextGoal > 0
                        ? '${summary.pointsToNextGoal} more to unlock a 24h Boost'
                        : 'Ready to boost your listing!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            _buildRedeemSection(summary),

            const SizedBox(height: 16),

            _buildStreakCard(summary),

            const SizedBox(height: 16),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.1,
              children: [
                _buildQuickCard(
                  icon: Icons.military_tech_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  iconBg: const Color(0xFFFEF3C7),
                  title: 'Badges',
                  subtitle: summary.highestHelpfulBadge ?? 'Earn badges',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BadgesScreen()),
                  ),
                ),
                _buildQuickCard(
                  icon: Icons.leaderboard_rounded,
                  iconColor: const Color(0xFF3A0F34),
                  iconBg: const Color(0xFFE8F6EF),
                  title: 'Top Neighbours',
                  subtitle: 'Weekly ranks',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LeaderboardScreen(currentUserHandle: widget.currentUserHandle),
                    ),
                  ),
                ),
                _buildQuickCard(
                  icon: Icons.card_giftcard_rounded,
                  iconColor: const Color(0xFFD81B60),
                  iconBg: const Color(0xFFFCE4EC),
                  title: 'Invite & earn',
                  subtitle: '+25 pts per friend',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InviteEarnScreen(currentUserHandle: widget.currentUserHandle),
                    ),
                  ),
                ),
                _buildQuickCard(
                  icon: Icons.history_rounded,
                  iconColor: const Color(0xFF16243A),
                  iconBg: const Color(0xFFE9ECEF),
                  title: 'History',
                  subtitle: 'Points ledger',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PointsHistoryScreen()),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: summary.isCapReached
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFFD5ECDD),
                  width: summary.isCapReached ? 1.5 : 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            summary.isCapReached
                                ? Icons.lock_clock_rounded
                                : Icons.speed_rounded,
                            size: 20,
                            color: summary.isCapReached
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF3A0F34),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Daily cap: ${summary.dailyPointsToday} of ${summary.dailyCap} used',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16243A),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: summary.isCapReached
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFE8F6EF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          summary.isCapReached ? 'Cap reached' : '${(summary.dailyPointsToday / (summary.dailyCap > 0 ? summary.dailyCap : 50) * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: summary.isCapReached
                                ? const Color(0xFFB45309)
                                : const Color(0xFF3A0F34),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (summary.dailyPointsToday / (summary.dailyCap > 0 ? summary.dailyCap : 50)).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: const Color(0xFFF3F4F6),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        summary.isCapReached
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF3A0F34),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    summary.isCapReached
                        ? 'Daily 50 pts cap reached across all actions. Reset at midnight server time.'
                        : '${(summary.dailyCap - summary.dailyPointsToday).clamp(0, summary.dailyCap)} pts remaining today · Reset at midnight server time',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: summary.isCapReached
                          ? const Color(0xFFB45309)
                          : const Color(0xFF5C6B7D),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            _buildRulesSummaryCard(),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD5ECDD), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Earn points',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16243A),
                        ),
                      ),
                      Text(
                        'Server verified',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildEarnRow(
                    icon: Icons.edit_note_rounded,
                    title: 'Create a post',
                    subtitle: 'Min 20 chars, max 3/day (2m cooldown)',
                    points: '+5',
                    currentProgress: summary.dailyPostsCount,
                    maxProgress: summary.dailyPostsMax,
                    isLimitReached: summary.postsProgress.isLimitReached,
                    onTap: () {
                      if (summary.postsProgress.isLimitReached) {
                        _showLimitDialog(
                          'Daily Posts Limit Reached',
                          'You have reached the maximum of 3 rewarded posts today (15 points). Additional posts will be published normally without awarding extra points today.',
                        );
                      }
                    },
                  ),
                  const Divider(height: 16, color: Color(0xFFE9ECEF)),
                  _buildEarnRow(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Reply to a post',
                    subtitle: 'Min 20 chars, max 5/day',
                    points: '+3',
                    currentProgress: summary.dailyRepliesCount,
                    maxProgress: summary.dailyRepliesMax,
                    isLimitReached: summary.repliesProgress.isLimitReached,
                    onTap: () {
                      if (summary.repliesProgress.isLimitReached) {
                        _showLimitDialog(
                          'Daily Replies Limit Reached',
                          'You have reached the maximum of 5 rewarded replies today (15 points). Additional replies will be published normally without extra points today.',
                        );
                      }
                    },
                  ),
                  const Divider(height: 16, color: Color(0xFFE9ECEF)),
                  _buildEarnRow(
                    icon: Icons.favorite_border_rounded,
                    title: 'Like received on comment',
                    subtitle: 'From neighbours (max 5/day)',
                    points: '+5',
                    currentProgress: summary.dailyLikesCount,
                    maxProgress: summary.dailyLikesMax,
                    isLimitReached: summary.likesProgress.isLimitReached,
                    onTap: () {
                      if (summary.likesProgress.isLimitReached) {
                        _showLimitDialog(
                          'Daily Likes Limit Reached',
                          'You have received the maximum of 5 rewarded likes today (25 points). Additional likes received today will not award extra points.',
                        );
                      }
                    },
                  ),
                  const Divider(height: 16, color: Color(0xFFE9ECEF)),
                  _buildEarnRow(
                    icon: Icons.storefront_outlined,
                    title: 'List an item in Bazaar',
                    subtitle: 'With title, price & photo (credited after 24h live)',
                    points: '+10',
                    currentProgress: summary.dailyListingsCount,
                    maxProgress: summary.dailyListingsMax,
                    isLimitReached: summary.listingsProgress.isLimitReached,
                    onTap: () {
                      if (summary.listingsProgress.isLimitReached) {
                        _showLimitDialog(
                          'Daily Bazaar Limit Reached',
                          'You have reached the maximum of 3 rewarded Bazaar listings today (30 points). Listings deleted before 24h do not qualify.',
                        );
                      }
                    },
                  ),
                  const Divider(height: 16, color: Color(0xFFE9ECEF)),
                  _buildEarnRow(
                    icon: Icons.people_outline_rounded,
                    title: 'Friend joins & posts',
                    subtitle: 'Both receive +25 upon friend\'s first valid post (max 5/mo)',
                    points: '+25',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InviteEarnScreen(currentUserHandle: widget.currentUserHandle),
                      ),
                    ),
                  ),
                  const Divider(height: 16, color: Color(0xFFE9ECEF)),
                  _buildEarnRow(
                    icon: Icons.local_fire_department_outlined,
                    title: '7-day active streak',
                    subtitle: 'Daily check-in for +30 loyalty bonus',
                    points: '+30',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD5ECDD), width: 0.8),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16243A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF5C6B7D),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRedeemSection(RewardsSummary summary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD5ECDD), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00897B), Color(0xFF00695C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.redeem_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Redeem Coins',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16243A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${summary.balance} coins available',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildRedeemOptionCard(
                  title: 'Bazar & Badges',
                  badgeText: 'Perks',
                  badgeColor: const Color(0xFF00897B),
                  badgeBg: const Color(0xFFE0F2F1),
                  description: 'Spotlights, verified badges & boosts',
                  costText: 'From 100 coins',
                  icon: Icons.verified_rounded,
                  iconColor: const Color(0xFF00897B),
                  iconBg: const Color(0xFFE0F2F1),
                  buttonText: 'Explore Perks',
                  buttonBg: const Color(0xFF00897B),
                  onTap: () => Navigator.of(context, rootNavigator: true).push(
                    PageRouteBuilder(
                      opaque: true,
                      transitionDuration: const Duration(milliseconds: 260),
                      reverseTransitionDuration: const Duration(milliseconds: 240),
                      pageBuilder: (_, animation, secondaryAnimation) => ShopPerksScreen(currentUserHandle: widget.currentUserHandle),
                      transitionsBuilder: (_, animation, _, child) {
                        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                        return SlideTransition(
                          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved),
                          child: child,
                        );
                      },
                    ),
                  ).then((_) => _loadData()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildRedeemOptionCard(
                  title: 'Listing Boost',
                  badgeText: 'Top Rank',
                  badgeColor: const Color(0xFFB45309),
                  badgeBg: const Color(0xFFFEF3C7),
                  description: 'Feature Bazaar item at the top for 24 hours',
                  costText: '300 coins',
                  icon: Icons.bolt_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  iconBg: const Color(0xFFFEF3C7),
                  buttonText: 'Boost Item',
                  buttonBg: const Color(0xFFF59E0B),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BoostListingScreen(currentUserHandle: widget.currentUserHandle),
                    ),
                  ).then((_) => _loadData()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRedeemOptionCard({
    required String title,
    required String badgeText,
    required Color badgeColor,
    required Color badgeBg,
    required String description,
    required String costText,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String buttonText,
    required Color buttonBg,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD5ECDD), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF16243A),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF5C6B7D),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            costText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: buttonBg,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonBg,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: onTap,
              child: Text(
                buttonText,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakCard(RewardsSummary summary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD5ECDD), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.local_fire_department_rounded,
                      size: 18,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily Check-in Streak',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16243A),
                        ),
                      ),
                      Text(
                        summary.streakCount > 0
                            ? '${summary.streakCount} of 7 days completed'
                            : 'Check in daily to earn coins',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF5C6B7D),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: summary.isStreakClaimedToday
                      ? const Color(0xFFE8F6EF)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  summary.isStreakClaimedToday
                      ? 'Claimed Today ✓'
                      : '+${summary.todayStreakPoints} pts today',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: summary.isStreakClaimedToday
                        ? const Color(0xFF3A0F34)
                        : const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final dayNum = index + 1;
              final isClaimed = dayNum <= summary.streakCount;
              final isNextToClaim = !summary.isStreakClaimedToday && dayNum == summary.nextStreakDay;
              final pts = index < summary.streakRewards.length ? summary.streakRewards[index] : 5;

              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: index == 6 ? 0 : 5),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isClaimed
                        ? const Color(0xFFFEF3C7)
                        : isNextToClaim
                            ? const Color(0xFFE8F6EF)
                            : const Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isClaimed
                          ? const Color(0xFFF59E0B)
                          : isNextToClaim
                              ? const Color(0xFF3A0F34)
                              : const Color(0xFFE2E8F0),
                      width: (isClaimed || isNextToClaim) ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'D$dayNum',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isClaimed
                              ? const Color(0xFFB45309)
                              : isNextToClaim
                                  ? const Color(0xFF3A0F34)
                                  : const Color(0xFF5C6B7D),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Icon(
                        isClaimed
                            ? Icons.check_circle_rounded
                            : isNextToClaim
                                ? Icons.monetization_on_rounded
                                : (dayNum == 7 ? Icons.emoji_events_rounded : Icons.star_border_rounded),
                        size: 16,
                        color: isClaimed
                            ? const Color(0xFFF59E0B)
                            : isNextToClaim
                                ? const Color(0xFF3A0F34)
                                : const Color(0xFFB0BEC5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '+$pts',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: isClaimed
                              ? const Color(0xFFB45309)
                              : isNextToClaim
                                  ? const Color(0xFF3A0F34)
                                  : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),
          if (!summary.isStreakClaimedToday)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A0F34),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isClaimingStreak ? null : _claimDailyStreak,
                child: _isClaimingStreak
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bolt_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Claim Day ${summary.nextStreakDay} (+${summary.todayStreakPoints} Coins)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F6EF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB9DEC6), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF3A0F34)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Day ${summary.streakCount} claimed! Return tomorrow for Day ${summary.nextStreakDay}.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3A0F34),
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

  void _showLimitDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 24),
            const SizedBox(width: 8),
            Flexible(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood', style: TextStyle(color: Color(0xFF3A0F34), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEarnRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String points,
    int? currentProgress,
    int? maxProgress,
    bool isLimitReached = false,
    VoidCallback? onTap,
  }) {
    final hasProgress = currentProgress != null && maxProgress != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isLimitReached ? const Color(0xFFF3F4F6) : const Color(0xFFE8F6EF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isLimitReached ? const Color(0xFF9CA3AF) : const Color(0xFF3A0F34),
              ),
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
                          title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isLimitReached ? const Color(0xFF6B7280) : const Color(0xFF16243A),
                          ),
                        ),
                      ),
                      if (hasProgress) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isLimitReached ? const Color(0xFFFEE2E2) : const Color(0xFFE0E7FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$currentProgress/$maxProgress',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isLimitReached ? const Color(0xFFDC2626) : const Color(0xFF3730A3),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF5C6B7D),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: isLimitReached ? const Color(0xFFF3F4F6) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isLimitReached ? const Color(0xFFE5E7EB) : const Color(0xFFFCD34D),
                  width: 0.8,
                ),
              ),
              child: Text(
                isLimitReached ? 'Done' : points,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isLimitReached ? const Color(0xFF9CA3AF) : const Color(0xFFB45309),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRulesSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB9DEC6), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A0F34),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Rewards Rules & Fair Play',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16243A),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _showRewardsRulesModal,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF3A0F34), width: 1),
                  ),
                  child: const Text(
                    'Full Rules →',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3A0F34),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRuleBullet(
            icon: Icons.calendar_today_rounded,
            title: 'Daily Streak Bonus (D1 - D7)',
            desc: 'Earn +5 to +30 coins every day. 7 days in a row unlocks +30 loyalty coins.',
          ),
          const SizedBox(height: 8),
          _buildRuleBullet(
            icon: Icons.speed_rounded,
            title: 'Daily 50 Pts Activity Cap',
            desc: 'Max 50 points/day across posts, replies & likes to ensure authentic community.',
          ),
          const SizedBox(height: 8),
          _buildRuleBullet(
            icon: Icons.rocket_launch_rounded,
            title: 'Bazar Boosts & Community Perks',
            desc: 'Use coins to boost listings, spotlight urgent deals, or unlock verified badges.',
          ),
        ],
      ),
    );
  }

  Widget _buildRuleBullet({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F6EF),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 13, color: const Color(0xFF3A0F34)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16243A),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF5C6B7D),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showRewardsRulesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A0F34),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.stars_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nearhood Rewards Policy',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF16243A),
                              ),
                            ),
                            Text(
                              'Rules, limits, and redemption guide',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF5C6B7D),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF5C6B7D)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildRuleSectionHeader('1. Daily Check-in Streak (रोजाना हाजिरी)'),
                    _buildRuleText(
                      '• Check in every day to collect free reward coins.\n'
                      '• Day 1: +5, Day 2: +10, Day 3: +15, Day 4: +10, Day 5: +15, Day 6: +20, Day 7: +30 Mega Bonus.\n'
                      '• Each day must be claimed once between 12:00 AM and 11:59 PM.\n'
                      '• If you miss a day, the streak resets to Day 1 so everyone gets equal chances.',
                    ),
                    const SizedBox(height: 16),
                    _buildRuleSectionHeader('2. Daily Activity Cap (50 Points/Day)'),
                    _buildRuleText(
                      '• To keep the colony feed clean and spam-free, a maximum of 50 activity points can be earned per day.\n'
                      '• This cap applies across posts, replies, likes, and listings.\n'
                      '• Daily Check-in Streak bonuses do NOT count toward this 50-point limit.',
                    ),
                    const SizedBox(height: 16),
                    _buildRuleSectionHeader('3. Earning Points in Your Colony'),
                    _buildRuleText(
                      '• Colony Posts (+5 pts): Share updates, questions, or alerts (min 20 chars, max 3/day).\n'
                      '• Helpful Replies (+3 pts): Help neighbors with answers (min 20 chars, max 5/day).\n'
                      '• Likes Received (+5 pts): When neighbours appreciate your advice (max 5/day).\n'
                      '• Bazaar Listings (+10 pts): List genuine items with photos (credited after 24h live, max 3/day).\n'
                      '• Invite Neighbours (+25 pts): When an invited neighbor posts their first colony update (max 5/month).',
                    ),
                    const SizedBox(height: 16),
                    _buildRuleSectionHeader('4. Redeeming Your Coins'),
                    _buildRuleText(
                      '• 24h Bazar Boost: Pin your marketplace listing at the top of your colony for 24 hours (300 coins).\n'
                      '• Urgent Deal Badge: Highlight item with an eye-catching urgent tag for 3 days (150 coins).\n'
                      '• Post Spotlight: Feature your community post or notice in the neighborhood feed (200 coins).\n'
                      '• Verified Neighbour: Unlock an exclusive verified star badge on your profile (500 coins).\n'
                      '• All unlocked perks and voucher codes are securely saved in your perk wallet.',
                    ),
                    const SizedBox(height: 16),
                    _buildRuleSectionHeader('5. Fair Play & Trust Policy'),
                    _buildRuleText(
                      '• Nearhood is a trusted local neighborhood community.\n'
                      '• Spamming, bot activity, fake accounts, or artificial upvotes will result in immediate points cancellation and account restriction.',
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3A0F34),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          'I Understand',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRuleSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF3A0F34),
        ),
      ),
    );
  }

  Widget _buildRuleText(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          color: Color(0xFF334155),
          height: 1.45,
        ),
      ),
    );
  }
}
