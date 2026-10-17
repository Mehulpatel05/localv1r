import 'package:flutter/material.dart';
import '../../models/rewards_model.dart';
import '../../services/rewards_service.dart';
import 'badges_screen.dart';
import 'leaderboard_screen.dart';
import 'invite_earn_screen.dart';
import 'boost_listing_screen.dart';
import 'shop_perks_screen.dart';
import 'points_history_screen.dart';
import 'widgets/scratch_card_sheet.dart';

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
  ScratchCardItem? _todayScratchCard;
  bool _dailyClaimedToday = false;
  bool _isLoadingScratchCard = false;
  bool _isLoading = true;
  String? _errorMessage;

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

    final results = await Future.wait([
      RewardsService.instance.fetchSummary(forceRefresh: true),
      RewardsService.instance.fetchScratchCards(),
    ]);

    if (!mounted) return;

    final summaryRes = results[0] as RewardsSummary?;
    final scratchRes = results[1] as Map<String, dynamic>;

    if (summaryRes != null) {
      final cardsList = (scratchRes['cards'] as List<ScratchCardItem>?) ?? [];
      final todayCard = cardsList.isNotEmpty ? cardsList.first : null;

      setState(() {
        _summary = summaryRes;
        _todayScratchCard = todayCard;
        _dailyClaimedToday = scratchRes['dailyClaimedToday'] == true;
        _isLoading = false;
      });

      if (summaryRes.streakAwarded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showStreakCelebrationSheet();
        });
      }
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load rewards. Please try again.';
      });
    }
  }

  Future<void> _openScratchCard() async {
    if (_todayScratchCard != null) {
      ScratchCardSheet.show(
        context,
        card: _todayScratchCard!,
        onScratched: _loadData,
      );
      return;
    }

    if (_dailyClaimedToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Daily scratch card already claimed today! Come back tomorrow.'),
          backgroundColor: Color(0xFF0F4C54),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoadingScratchCard = true;
    });

    final card = await RewardsService.instance.claimDailyScratchCard();
    if (!mounted) return;
    setState(() {
      _isLoadingScratchCard = false;
      if (card != null) {
        _todayScratchCard = card;
      }
    });

    if (card != null) {
      ScratchCardSheet.show(
        context,
        card: card,
        onScratched: _loadData,
      );
    }
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
                  backgroundColor: const Color(0xFF0E8A3E),
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
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0E8A3E)),
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
                  backgroundColor: const Color(0xFF0E8A3E),
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
      color: const Color(0xFF0E8A3E),
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
                  colors: [Color(0xFF074E28), Color(0xFF0E8A3E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0E8A3E).withValues(alpha: 0.25),
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
                      Row(
                        children: [
                          const Icon(Icons.local_fire_department_rounded, size: 20, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Text(
                            'Daily streak · ${summary.streakCount} of 7',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16243A),
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Day 7 gives +30 pts',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0E8A3E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(7, (index) {
                      final dayNum = index + 1;
                      final isCompleted = dayNum <= summary.streakCount;
                      return Container(
                        width: 38,
                        height: 46,
                        decoration: BoxDecoration(
                          color: isCompleted ? const Color(0xFFFEF3C7) : const Color(0xFFF7FBF9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCompleted ? const Color(0xFFF59E0B) : const Color(0xFFD5ECDD),
                            width: isCompleted ? 1.5 : 1.0,
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
                                color: isCompleted ? const Color(0xFFB45309) : const Color(0xFF5C6B7D),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Icon(
                              isCompleted ? Icons.check_circle_rounded : Icons.star_border_rounded,
                              size: 16,
                              color: isCompleted ? const Color(0xFFF59E0B) : const Color(0xFFB9DEC6),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            _buildDailyScratchBanner(),

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
                  iconColor: const Color(0xFF0E8A3E),
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
                  icon: Icons.bolt_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  iconBg: const Color(0xFFFEF3C7),
                  title: 'Boost listing',
                  subtitle: '300 pts · 24h feature',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BoostListingScreen(currentUserHandle: widget.currentUserHandle),
                    ),
                  ).then((_) => _loadData()),
                ),
                _buildQuickCard(
                  icon: Icons.local_offer_outlined,
                  iconColor: const Color(0xFF00897B),
                  iconBg: const Color(0xFFE0F2F1),
                  title: 'Shop perks',
                  subtitle: 'Unlock coupons',
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
                                : const Color(0xFF0E8A3E),
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
                                : const Color(0xFF0E8A3E),
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
                            : const Color(0xFF0E8A3E),
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
            child: const Text('Understood', style: TextStyle(color: Color(0xFF0E8A3E), fontWeight: FontWeight.bold)),
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
                color: isLimitReached ? const Color(0xFF9CA3AF) : const Color(0xFF0E8A3E),
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

  Widget _buildDailyScratchBanner() {
    final hasUnscratched = _todayScratchCard != null && !_todayScratchCard!.isScratched;
    final isClaimed = _dailyClaimedToday || (_todayScratchCard != null && _todayScratchCard!.isScratched);

    return InkWell(
      onTap: _isLoadingScratchCard ? null : _openScratchCard,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isClaimed
                ? [const Color(0xFF072E33), const Color(0xFF0F4C54)]
                : [const Color(0xFF134E5E), const Color(0xFF0F766E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isClaimed ? const Color(0xFF134E5E) : const Color(0xFF2DD4BF),
            width: isClaimed ? 1.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2DD4BF).withValues(alpha: isClaimed ? 0.05 : 0.2),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: isClaimed
                      ? [const Color(0xFF94A3B8), const Color(0xFF475569)]
                      : [const Color(0xFFFDE68A), const Color(0xFFD97706)],
                ),
                shape: BoxShape.circle,
                boxShadow: isClaimed
                    ? []
                    : [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
              ),
              child: Icon(
                isClaimed ? Icons.check_circle_rounded : Icons.card_giftcard_rounded,
                color: isClaimed ? Colors.white : const Color(0xFF78350F),
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isClaimed ? 'Daily Scratch Card' : 'Daily Mystery Scratch Card',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      if (!isClaimed) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'FREE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF031214),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isClaimed
                        ? 'Claimed today (+${_todayScratchCard?.pointsAmount ?? 15} pts)! Next card unlocks tomorrow.'
                        : 'Scratch to reveal 10 to 50 surprise bonus points!',
                    style: TextStyle(
                      fontSize: 12,
                      color: isClaimed ? const Color(0xFF94A3B8) : const Color(0xFFCCFBF1),
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isClaimed
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFF2DD4BF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isClaimed ? 'Viewed' : (hasUnscratched ? 'Scratch' : 'Claim'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: isClaimed ? const Color(0xFF94A3B8) : const Color(0xFF031214),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
