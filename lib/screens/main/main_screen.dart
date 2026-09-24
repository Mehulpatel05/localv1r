import 'package:flutter/material.dart';
import '../../services/post_repository.dart';
import '../feed/feed_screen.dart';
import '../chat/chat_list_screen.dart';
import '../profile/profile_screen.dart';
import '../communities/communities_list_screen.dart';
import '../../services/community_repository.dart';
import '../../services/notification_service.dart';
import '../../core/motion.dart';
import '../../core/widgets/user_avatar.dart';

class MainScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const MainScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  final ValueNotifier<int> _currentIndexNotifier = ValueNotifier<int>(0);
  final Set<int> _mountedTabs = {0};
  late final List<Widget?> _cachedTabs = [null, null, null, null];
  late final CommunityRepository _communityRepository;
  late final AnimationController _tabTransitionController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _communityRepository = CommunityRepository()..currentUserHandle = widget.currentUserHandle;
    
    _tabTransitionController = AnimationController(
      vsync: this,
      duration: AppMotion.durationStandard,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _tabTransitionController,
      curve: AppMotion.enterCurve,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.012), // ~8-10px rise
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _tabTransitionController,
        curve: AppMotion.enterCurve,
      ),
    );

    _tabTransitionController.value = 1.0;
  }

  @override
  void dispose() {
    _currentIndexNotifier.dispose();
    _tabTransitionController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (_currentIndexNotifier.value == index) return;
    
    _mountedTabs.add(index);
    _currentIndexNotifier.value = index;

    _tabTransitionController.forward(from: 0.0);
  }

  Widget _getOrCreateTab(int index) {
    if (!_mountedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    _cachedTabs[index] ??= _createTab(index);
    return _cachedTabs[index]!;
  }

  Widget _createTab(int index) {
    switch (index) {
      case 0:
        return FeedScreen(
          repository: widget.repository,
          currentUserHandle: widget.currentUserHandle,
          onOpenProfileTab: () => _onTabTapped(3),
        );
      case 1:
        return CommunitiesListScreen(repository: _communityRepository);
      case 2:
        return ChatListScreen(
          currentUserHandle: widget.currentUserHandle,
        );
      case 3:
        return ProfileScreen(
          repository: widget.repository,
          currentUserHandle: widget.currentUserHandle,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: ValueListenableBuilder<int>(
        valueListenable: _currentIndexNotifier,
        builder: (context, currentIndex, _) {
          return SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: IndexedStack(
                index: currentIndex,
                children: List.generate(4, (index) => _getOrCreateTab(index)),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _currentIndexNotifier,
        builder: (context, currentIndex, _) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final barBg = isDark ? Colors.black : Colors.white;
          final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6);
          final activePillColor = isDark ? Colors.white.withValues(alpha: 0.14) : const Color(0xFFEAEAEA);

          return Container(
            decoration: BoxDecoration(
              color: barBg,
              border: Border(
                top: BorderSide(color: borderColor, width: 1.0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth / 4;
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // Sliding active indicator pill
                          AnimatedPositioned(
                            duration: AppMotion.durationMicro,
                            curve: AppMotion.interactiveCurve,
                            left: currentIndex * itemWidth + (itemWidth - 58) / 2,
                            width: 58,
                            top: 4,
                            bottom: 4,
                            child: Container(
                              decoration: BoxDecoration(
                                color: activePillColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                          // Navigation items
                          Row(
                            children: [
                              _buildNavItem(
                                index: 0,
                                currentIndex: currentIndex,
                                icon: Icons.home_outlined,
                                selectedIcon: Icons.home_rounded,
                                tooltip: 'Home',
                                isDark: isDark,
                              ),
                              _buildNavItem(
                                index: 1,
                                currentIndex: currentIndex,
                                icon: Icons.people_outline_rounded,
                                selectedIcon: Icons.people_rounded,
                                tooltip: 'Communities',
                                isDark: isDark,
                              ),
                              StreamBuilder<int>(
                                stream: NotificationService().getUnreadChatCount(widget.currentUserHandle),
                                builder: (context, snapshot) {
                                  final unreadCount = snapshot.data ?? 0;
                                  return _buildNavItem(
                                    index: 2,
                                    currentIndex: currentIndex,
                                    icon: Icons.chat_bubble_outline_rounded,
                                    selectedIcon: Icons.chat_bubble_rounded,
                                    tooltip: 'Chats',
                                    isDark: isDark,
                                    badgeCount: unreadCount,
                                  );
                                },
                              ),
                              // Profile tab with live avatar
                              _buildProfileNavItem(
                                currentIndex: currentIndex,
                                isDark: isDark,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required int currentIndex,
    required IconData icon,
    required IconData selectedIcon,
    String? tooltip,
    required bool isDark,
    int badgeCount = 0,
  }) {
    final isSelected = currentIndex == index;
    final selectedColor = isDark ? Colors.white : Colors.black;
    final unselectedColor = isDark ? const Color(0xFF9A9A9A) : const Color(0xFF8E8E93);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTabTapped(index),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: Tooltip(
            message: tooltip ?? '',
            child: SizedBox(
              height: 48,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedScale(
                      scale: isSelected ? 1.06 : 1.0,
                      duration: AppMotion.durationMicro,
                      curve: AppMotion.interactiveCurve,
                      child: Icon(
                        isSelected ? selectedIcon : icon,
                        size: 25,
                        color: isSelected ? selectedColor : unselectedColor,
                      ),
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        top: -5,
                        right: -10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? Colors.black : Colors.white,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileNavItem({
    required int currentIndex,
    required bool isDark,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTabTapped(3),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: const Tooltip(
            message: 'Profile',
            child: SizedBox(
              height: 48,
              child: Center(
                child: _ProfileNavAvatar(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Separate StatefulWidget so it can listen to ValueListenableBuilder independently
class _ProfileNavAvatar extends StatefulWidget {
  const _ProfileNavAvatar();

  @override
  State<_ProfileNavAvatar> createState() => _ProfileNavAvatarState();
}

class _ProfileNavAvatarState extends State<_ProfileNavAvatar> {
  @override
  Widget build(BuildContext context) {
    // Walk up to find the MainScreen's currentIndex and handle
    final mainState = context.findAncestorStateOfType<_MainScreenState>();
    final currentIndex = mainState?._currentIndexNotifier.value ?? 0;
    final handle = mainState?.widget.currentUserHandle ?? 'me';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = currentIndex == 3;

    final ringColor = isDark ? Colors.white : Colors.black;
    final borderWidth = isSelected ? 2.0 : 0.0;

    return AnimatedScale(
      scale: isSelected ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? ringColor : Colors.transparent,
            width: borderWidth,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: UserAvatar(
          handle: handle,
          size: 26,
          fontSize: 10,
          enableFullViewOnTap: false,
        ),
      ),
    );
  }
}
