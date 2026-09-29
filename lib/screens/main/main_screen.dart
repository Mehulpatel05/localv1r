import 'package:flutter/material.dart';
import '../../services/post_repository.dart';
import '../feed/feed_screen.dart';
import '../bazar/bazar_screen.dart';
import '../chat/chat_list_screen.dart';
import '../profile/profile_screen.dart';
import '../../services/notification_service.dart';
import '../../services/direct_chat_service.dart';
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
  final Set<int> _mountedTabs = {0, 1, 2, 3};
  late final List<Widget?> _cachedTabs = [null, null, null, null];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 4; i++) {
      _cachedTabs[i] = _createTab(i);
    }
  }

  @override
  void dispose() {
    _currentIndexNotifier.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (_currentIndexNotifier.value == index) return;
    _currentIndexNotifier.value = index;
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
        return BazarScreen(
          currentUserHandle: widget.currentUserHandle,
        );
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<int>(
        valueListenable: _currentIndexNotifier,
        builder: (context, currentIndex, _) {
          return IndexedStack(
            index: currentIndex,
            children: List.generate(4, (index) => _getOrCreateTab(index)),
          );
        },
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _currentIndexNotifier,
        builder: (context, currentIndex, _) {
          const barBg = Colors.black;
          const borderColor = Color(0xFF072E33);
          const activePillColor = Color(0xFF072E33);

          return Container(
            decoration: const BoxDecoration(
              color: barBg,
              border: Border(
                top: BorderSide(color: borderColor, width: 1.5),
              ),
            ),
            child: SafeArea(
              child: SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth / 4;
                      final pillColumn = currentIndex;
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // Active indicator pill with Deep Teal #072E33
                          AnimatedPositioned(
                            duration: AppMotion.durationMicro,
                            curve: AppMotion.interactiveCurve,
                            left: pillColumn * itemWidth + (itemWidth - 56) / 2,
                            width: 56,
                            top: 4,
                            bottom: 4,
                            child: Container(
                              decoration: BoxDecoration(
                                color: activePillColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF0E525B), width: 1.0),
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
                              ),
                              _buildNavItem(
                                index: 1,
                                currentIndex: currentIndex,
                                icon: Icons.storefront_outlined,
                                selectedIcon: Icons.storefront_rounded,
                                tooltip: 'Bazar',
                              ),
                              ValueListenableBuilder<int>(
                                valueListenable: DirectChatService.instance.unreadCountNotifier,
                                builder: (context, preloadedUnread, _) {
                                  return StreamBuilder<int>(
                                    initialData: preloadedUnread,
                                    stream: NotificationService().getUnreadChatCount(widget.currentUserHandle),
                                    builder: (context, snapshot) {
                                      final unreadCount = snapshot.data ?? preloadedUnread;
                                      return _buildNavItem(
                                        index: 2,
                                        currentIndex: currentIndex,
                                        icon: Icons.chat_bubble_outline_rounded,
                                        selectedIcon: Icons.chat_bubble_rounded,
                                        tooltip: 'Chats',
                                        badgeCount: unreadCount,
                                      );
                                    },
                                  );
                                },
                              ),
                              // Profile tab
                              _buildProfileNavItem(
                                currentIndex: currentIndex,
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
    int badgeCount = 0,
  }) {
    final isSelected = currentIndex == index;
    const selectedColor = Colors.white;
    const unselectedColor = Color(0xFF90B4B6);

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
                              color: Colors.black,
                              width: 1.5,
                            ),
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

class _ProfileNavAvatar extends StatefulWidget {
  const _ProfileNavAvatar();

  @override
  State<_ProfileNavAvatar> createState() => _ProfileNavAvatarState();
}

class _ProfileNavAvatarState extends State<_ProfileNavAvatar> {
  @override
  Widget build(BuildContext context) {
    final mainState = context.findAncestorStateOfType<_MainScreenState>();
    final currentIndex = mainState?._currentIndexNotifier.value ?? 0;
    final handle = mainState?.widget.currentUserHandle ?? 'me';
    final isSelected = currentIndex == 3;

    const ringColor = Colors.white;
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
