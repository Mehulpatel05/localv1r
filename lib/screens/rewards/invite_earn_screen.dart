import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/rewards_model.dart';
import '../../services/rewards_service.dart';
import '../../core/services/name_cache_service.dart';

class InviteEarnScreen extends StatefulWidget {
  final String currentUserHandle;

  const InviteEarnScreen({
    super.key,
    required this.currentUserHandle,
  });

  @override
  State<InviteEarnScreen> createState() => _InviteEarnScreenState();
}

class _InviteEarnScreenState extends State<InviteEarnScreen> {
  ReferralInfo? _info;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReferrals();
  }

  Future<void> _loadReferrals() async {
    final res = await RewardsService.instance.fetchReferrals();
    if (mounted) {
      setState(() {
        _info = res;
        _isLoading = false;
      });
    }
  }

  void _copyCode() {
    final code = _info?.referralCode ?? '';
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Referral code copied to clipboard!'),
        backgroundColor: Color(0xFF3A0F34),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shareLink() {
    final code = _info?.referralCode ?? '';
    final url = _info?.shareUrl ?? 'https://nearhood.in/join?ref=$code';
    SharePlus.instance.share(
      ShareParams(
        text: 'Join me on Nearhood — the local community app for Vadodara! Use my code $code to earn +25 bonus points: $url',
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
          'Invite & Earn',
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
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF250921), Color(0xFF3A0F34)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.card_giftcard_rounded, size: 30, color: Colors.white),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'You both get +25 pts',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Invite your neighbours to join Nearhood. Both of you receive 25 points after they make their first post or listing!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            height: 1.4,
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
                      border: Border.all(color: const Color(0xFFEADBE7), width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your referral code',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF5C6B7D),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FBF9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFEADBE7), width: 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _info?.referralCode ?? 'NEAR-USER',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: Color(0xFF3A0F34),
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF3A0F34),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                ),
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: const Text('Copy', style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: _copyCode,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3A0F34),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.share_rounded, size: 18),
                            label: const Text('Share invite link', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            onPressed: _shareLink,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your invites',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16243A),
                        ),
                      ),
                      Text(
                        '${_info?.invites.length ?? 0} invited',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5C6B7D),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  if ((_info?.invites ?? []).isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEADBE7), width: 0.5),
                      ),
                      child: const Center(
                        child: Text(
                          'No neighbours invited yet. Share your code with neighbours to start earning points!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Color(0xFF5C6B7D), height: 1.4),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _info!.invites.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _info!.invites[index];
                        final isRewarded = item.status == 'rewarded';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFEADBE7), width: 0.8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isRewarded ? const Color(0xFFE8F6EF) : const Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isRewarded ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                  size: 18,
                                  color: isRewarded ? const Color(0xFF3A0F34) : const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      getDisplayName(item.inviteeHandle),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF16243A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isRewarded ? 'Posted · reward earned' : 'Waiting for first post',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isRewarded ? const Color(0xFF3A0F34) : const Color(0xFF5C6B7D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isRewarded)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    '+25 pts',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
