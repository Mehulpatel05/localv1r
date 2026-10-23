import 'package:flutter/material.dart';
import '../../models/rewards_model.dart';
import '../../services/rewards_service.dart';

class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  List<UserBadgeItem> _badges = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
    final list = await RewardsService.instance.fetchBadges();
    if (mounted) {
      setState(() {
        _badges = list;
        _isLoading = false;
      });
    }
  }

  void _showBadgeSheet(UserBadgeItem badge) {
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
                color: const Color(0xFFEADBE7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: badge.earned ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: badge.earned ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                  width: 2,
                ),
              ),
              child: Icon(
                _getBadgeIcon(badge.key),
                size: 32,
                color: badge.earned ? const Color(0xFFD97706) : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              badge.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF16243A),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badge.earned ? const Color(0xFFE8F6EF) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badge.earned ? 'UNLOCKED' : 'LOCKED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: badge.earned ? const Color(0xFF3A0F34) : const Color(0xFF64748B),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF5C6B7D),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            if (!badge.earned) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (badge.current / badge.required).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3A0F34)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${badge.current} of ${badge.required} completed',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5C6B7D),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A0F34),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getBadgeIcon(String key) {
    switch (key) {
      case 'helper':
        return Icons.volunteer_activism_rounded;
      case 'local_hero':
        return Icons.shield_rounded;
      case 'top_seller':
        return Icons.verified_rounded;
      case 'founding_neighbour':
        return Icons.location_city_rounded;
      default:
        return Icons.emoji_events_rounded;
    }
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
          'Badges',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF16243A),
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3A0F34)))
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _badges.length,
                    itemBuilder: (context, index) {
                      final badge = _badges[index];
                      return GestureDetector(
                        onTap: () => _showBadgeSheet(badge),
                        child: Opacity(
                          opacity: badge.earned ? 1.0 : 0.55,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: badge.earned ? const Color(0xFFF59E0B) : const Color(0xFFEADBE7),
                                width: badge.earned ? 1.5 : 0.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: badge.earned
                                      ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                                      : Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: badge.earned ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _getBadgeIcon(badge.key),
                                    size: 26,
                                    color: badge.earned ? const Color(0xFFD97706) : const Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  badge.name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF16243A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  badge.earned ? 'Earned ✨' : '${badge.current}/${badge.required}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: badge.earned ? const Color(0xFF3A0F34) : const Color(0xFF5C6B7D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F6EF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFEADBE7), width: 0.8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF3A0F34)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Earned badges show on your profile and next to your name in community posts.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF16243A),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
