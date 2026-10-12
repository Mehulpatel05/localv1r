import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class LegalAndRulesScreen extends StatefulWidget {
  final int initialTabIndex;

  const LegalAndRulesScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  static void open(BuildContext context, {int initialTab = 0}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalAndRulesScreen(initialTabIndex: initialTab),
      ),
    );
  }

  @override
  State<LegalAndRulesScreen> createState() => _LegalAndRulesScreenState();
}

class _LegalAndRulesScreenState extends State<LegalAndRulesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nearhood Legal & Safety',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Vadodara Community Standards',
              style: TextStyle(
                color: AppColors.primaryText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: const [
            Tab(text: 'Rules'),
            Tab(text: 'Terms'),
            Tab(text: 'Privacy'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCommunityRulesTab(),
          _buildTermsOfServiceTab(),
          _buildPrivacyPolicyTab(),
        ],
      ),
    );
  }

  Widget _buildCommunityRulesTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        _buildHeroBanner(
          icon: Icons.shield_rounded,
          title: 'Vadodara Neighborhood Code',
          description:
              'Nearhood is a safe, family-friendly hyper-local community for residents of Vadodara. Zero tolerance for fraud, harassment, or hatred.',
        ),
        const SizedBox(height: 24),

        _buildSectionHeader('DO\'S — COMMUNITY ETHICS', Icons.check_circle_rounded, AppColors.primary),
        const SizedBox(height: 12),
        _buildRuleCard(
          icon: Icons.favorite_rounded,
          title: 'Help Fellow Residents',
          subtitle:
              'Share blood donation requests, lost-and-found items, genuine local society notices, traffic/road alerts, and verified city recommendations.',
        ),
        _buildRuleCard(
          icon: Icons.category_rounded,
          title: 'Tag the Correct Category',
          subtitle:
              'Post in relevant feeds: Jobs, Rooms/Rent, Buy & Sell, Food & Deals, Events, or Discussions. Keep Vadodara feeds clean.',
        ),
        _buildRuleCard(
          icon: Icons.verified_user_rounded,
          title: 'Honest Listings & Transparent Deals',
          subtitle:
              'When renting a room or selling items in Vadodara, provide real photographs, truthful descriptions, and accurate price tags.',
        ),

        const SizedBox(height: 24),
        _buildSectionHeader('DON\'TS — ZERO TOLERANCE (INSTANT BAN)', Icons.cancel_rounded, AppColors.error),
        const SizedBox(height: 12),
        _buildRuleCard(
          icon: Icons.block_rounded,
          title: 'No Hate Speech, Casteism or Bullying',
          subtitle:
              'Abusive language, communal hate speech, religious intolerance, and trolling local residents or shops are strictly prohibited.',
          isDanger: true,
        ),
        _buildRuleCard(
          icon: Icons.no_adult_content_rounded,
          title: 'Zero Tolerance for Adult / Nudity',
          subtitle:
              'Posting sexual, obscene, or suggestive media in posts, profiles, or 1-on-1 direct chats leads to an immediate permanent device ban.',
          isDanger: true,
        ),
        _buildRuleCard(
          icon: Icons.warning_amber_rounded,
          title: 'No Advance Payment Scams & Fake Jobs',
          subtitle:
              'Demanding registration fees for jobs or QR code advance deposits before meeting in person will be prosecuted with local authorities.',
          isDanger: true,
        ),
        _buildRuleCard(
          icon: Icons.gavel_rounded,
          title: 'No Illegal Items or Substances',
          subtitle:
              'Sale of alcohol (Gujarat Dry State laws), drugs, weapons, fireworks, or prescription medications is prohibited.',
          isDanger: true,
        ),
        _buildRuleCard(
          icon: Icons.lock_person_rounded,
          title: 'No Doxxing (Leaking Personal Info)',
          subtitle:
              'Never share someone\'s private phone number, home address, or personal images without their written consent.',
          isDanger: true,
        ),

        const SizedBox(height: 32),
        _buildGrievanceContactBox(),
      ],
    );
  }

  Widget _buildTermsOfServiceTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        _buildHeroBanner(
          icon: Icons.description_rounded,
          title: 'Terms of Service',
          description:
              'Please read these terms carefully. By accessing or using Nearhood, you agree to be bound by these legally binding terms.',
        ),
        const SizedBox(height: 20),

        _buildLegalParagraph(
          title: '1. Intermediary Status (Section 79, IT Act 2000)',
          body:
              'Nearhood operates strictly as a hyper-local communication platform and intermediary. Nearhood does not employ workers, broker property rentals, or sell retail items directly. Any transaction, interaction, or encounter between users is solely between the respective parties. Nearhood disclaims all liability for peer-to-peer agreements.',
        ),
        _buildLegalParagraph(
          title: '2. Anti-Scam & Advance Payment Disclaimer',
          body:
              'Never transfer money (UPI, Bank Transfer, Cash) to any stranger before physically inspecting the room, flat, or secondhand item in a safe public place. Nearhood will never ask you for money to release a parcel, book a room, or verify your profile.',
        ),
        _buildLegalParagraph(
          title: '3. Vadodara GPS Geofencing Requirement',
          body:
              'Nearhood is an exclusive neighborhood platform built specifically for the residents of Vadodara, Gujarat. To maintain community integrity, device location must remain enabled. The use of GPS spoofers, mock locations, or VPN proxies to falsify presence in Vadodara will result in automatic session termination.',
        ),
        _buildLegalParagraph(
          title: '4. User-Generated Content License',
          body:
              'You retain ownership of the photos, descriptions, and comments you post. By posting, you grant Nearhood a non-exclusive, royalty-free license to display, host, and index your content to neighbors in your area. We reserve the right to remove any content that violates community safety.',
        ),
        _buildLegalParagraph(
          title: '5. Direct Messaging & Calling Rules',
          body:
              'Direct chat and peer-to-peer calling are provided for neighborly coordination. Harassment, stalking, or sending obscene material in direct messages is a punishable criminal offense under the Bharatiya Nyaya Sanhita (BNS) and the IT Act.',
        ),
        _buildLegalParagraph(
          title: '6. Jurisdiction & Governing Law',
          body:
              'These terms are governed by the laws of India. Any legal dispute, claim, or proceeding arising out of Nearhood shall be subject exclusively to the jurisdiction of the competent courts in Vadodara, Gujarat, India.',
        ),

        const SizedBox(height: 32),
        _buildGrievanceContactBox(),
      ],
    );
  }

  Widget _buildPrivacyPolicyTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        _buildHeroBanner(
          icon: Icons.privacy_tip_rounded,
          title: 'Privacy & Data Protection',
          description:
              'Compliant with the Digital Personal Data Protection (DPDP) Act, 2023. We believe privacy is a fundamental right.',
        ),
        const SizedBox(height: 20),

        _buildPrivacyHighlightCard(
          icon: Icons.my_location_rounded,
          title: 'Exact GPS Privacy Guarantee',
          description:
              'Your high-accuracy GPS coordinates are processed securely on-device to determine your Vadodara neighborhood (e.g. Alkapuri, Manjalpur, Akota). We NEVER display your live coordinates, home address, or house location to the public.',
        ),
        _buildPrivacyHighlightCard(
          icon: Icons.phone_in_talk_rounded,
          title: 'WebRTC P2P Calling — No Recording',
          description:
              'Audio and video calls are transmitted peer-to-peer using encrypted WebRTC protocols. Nearhood does not listen to, tap, or record your live conversations on any server.',
        ),
        _buildPrivacyHighlightCard(
          icon: Icons.camera_alt_rounded,
          title: 'Camera, Photos & Audio Permissions',
          description:
              'Camera and photo access are strictly used when you choose to take a photo for a post or share an image in chat. Voice note audio is recorded only while you hold the mic button.',
        ),
        _buildPrivacyHighlightCard(
          icon: Icons.security_rounded,
          title: 'Device ID & Play Integrity',
          description:
              'We use device security tokens and Google Play Integrity to prevent malicious bots, fake reviews, and banned fraudsters from creating duplicate accounts.',
        ),
        _buildPrivacyHighlightCard(
          icon: Icons.delete_forever_rounded,
          title: 'Right to Erasure & Account Deletion',
          description:
              'Under DPDP Act 2023, you have the complete right to delete your account, posts, and personal messages anytime from Settings > Delete My Account. Data and media are permanently and instantly purged.',
        ),

        const SizedBox(height: 32),
        _buildGrievanceContactBox(),
      ],
    );
  }

  Widget _buildHeroBanner({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildRuleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    bool isDanger = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDanger
            ? AppColors.errorSoft
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDanger
              ? const Color(0xFFFCA5A5)
              : AppColors.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: isDanger ? AppColors.error : AppColors.primary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDanger ? const Color(0xFFB3262A) : AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalParagraph({required String title, required String body}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyHighlightCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrievanceContactBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.support_agent_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Grievance Redressal Officer (IT Rules, 2021)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'For content takedowns, cyber fraud reports, or legal inquiries, our Grievance Officer in Vadodara acts within 24 hours:\n\n'
            '• Officer: Legal & Trust Department\n'
            '• Email: grievance@nearhood.in\n'
            '• City: Vadodara, Gujarat 390001, India\n'
            '• Response SLA: Acknowledgment within 24 hours, resolution within 15 days.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
