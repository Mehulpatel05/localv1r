import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../services/post_repository.dart';
import '../feed/feed_screen.dart';
import '../bazar/bazar_screen.dart';
import '../chat/chat_list_screen.dart';
import '../profile/profile_screen.dart';
import '../../services/notification_service.dart';
import '../../services/direct_chat_service.dart';
import '../../services/rewards_service.dart';
import '../../services/auth_service.dart';
import '../../core/motion.dart';
import '../../core/widgets/user_avatar.dart';
import '../../features/auth/widgets/confirm_area_sheet.dart';
import '../../features/auth/widgets/city_paused_dialog.dart';
import '../../core/location/location_engine.dart';
import '../auth/create_handle_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _cachedTabs[0] = _createTab(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAreaAndCityStatus();
      NotificationService.instance.initialize();
      NotificationService.instance.startListening(widget.currentUserHandle);
      NotificationService.instance.syncFcmTokenForUser(widget.currentUserHandle);
      NotificationService.instance.prefetchBadgeCounts(widget.currentUserHandle);
      DirectChatService.instance.prefetchUnreadSummary(widget.currentUserHandle);
    });
  }

  Future<void> _checkAreaAndCityStatus() async {
    final me = await AuthService.instance.fetchMe();
    if (!mounted || me == null) return;

    final userObj = me['user'] as Map<String, dynamic>?;
    final serverAreaId = (userObj?['areaId'] ?? userObj?['homeAreaId'] ?? userObj?['home_area_id'] ?? me['area_id']) as String?;
    final serverAreaName = (userObj?['areaName'] ?? userObj?['homeAreaName'] ?? userObj?['home_area_name'] ?? me['area_name']) as String?;
    final serverCityId = (userObj?['cityId'] ?? userObj?['homeCityId'] ?? userObj?['home_city_id'] ?? me['city_id']) as String?;

    final locService = widget.repository.locationService;
    if (serverAreaName != null && serverAreaName.trim().isNotEmpty) {
      final effectiveCityId = (serverCityId != null && serverCityId.isNotEmpty) ? serverCityId : locService.city.id;
      final resolvedCity = LocationEngine.lookupCity(effectiveCityId) ?? locService.city;
      if (locService.city.id != resolvedCity.id) {
        await locService.setCity(resolvedCity);
      }
      final effectiveAreaId = (serverAreaId != null && serverAreaId.isNotEmpty) ? serverAreaId : effectiveCityId;
      if (locService.area?.name != serverAreaName.trim() || locService.area?.id != effectiveAreaId) {
        final matched = LocationEngine.lookupArea(effectiveAreaId);
        await locService.setArea(
          GeoArea(
            id: effectiveAreaId,
            cityId: resolvedCity.id,
            name: serverAreaName.trim(),
            lat: matched?.lat ?? locService.rawLat,
            lng: matched?.lng ?? locService.rawLng,
            pincode: matched?.pincode,
          ),
        );
      }
    }

    if (!mounted) return;

    final cityStatus = me['city_status'] as String? ?? me['user']?['cityStatus'] as String? ?? 'active';
    final cityMessage = me['city_message'] as String? ?? me['user']?['cityMessage'] as String?;
    final areaConfirmed = me['area_confirmed'] == 1 || me['user']?['areaConfirmed'] == true;
    final areaName = locService.area?.name ?? serverAreaName ?? serverAreaId ?? 'Alkapuri';
    final cityName = locService.city.name;

    if (cityStatus == 'paused') {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => CityPausedDialog(
          message: cityMessage,
          cityName: cityName,
        ),
      );
    } else if (!areaConfirmed) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ConfirmAreaSheet(
          currentAreaName: areaName,
          currentCityName: cityName,
          onAreaConfirmed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Area successfully confirmed!'),
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          onChangeArea: () async {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => CreateHandleScreen(
                  repository: widget.repository,
                  userId: '',
                  isChangeArea: true,
                ),
              ),
            );
            if (result == true && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Area successfully updated!'),
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              _checkAreaAndCityStatus();
            }
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _currentIndexNotifier.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (!_mountedTabs.contains(index)) {
      _mountedTabs.add(index);
      _cachedTabs[index] = _createTab(index);
      setState(() {});
    }
    if (_currentIndexNotifier.value == index) return;
    _currentIndexNotifier.value = index;
    if (index == 0 || index == 3) {
      RewardsService.instance.fetchSummary();
    }
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
    return ValueListenableBuilder<int>(
      valueListenable: _currentIndexNotifier,
      builder: (context, currentIndex, _) {
        return PopScope(
          canPop: currentIndex == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (currentIndex != 0) {
              _onTabTapped(0);
            }
          },
          child: Scaffold(
            backgroundColor: Colors.white,
            body: IndexedStack(
              index: currentIndex,
              children: List.generate(4, (index) => _getOrCreateTab(index)),
            ),
            bottomNavigationBar: AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  left: false,
                  right: false,
                  child: SizedBox(
                    height: 64,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final itemWidth = constraints.maxWidth / 4;
                          final pillColumn = currentIndex;
                          return Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              AnimatedPositioned(
                                duration: AppMotion.durationMicro,
                                curve: AppMotion.interactiveCurve,
                                left: pillColumn * itemWidth + (itemWidth - 58) / 2,
                                width: 58,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDBF1E3),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                              ),
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
                                    builder: (context, unreadCount, _) {
                                      return _buildNavItem(
                                        index: 2,
                                        currentIndex: currentIndex,
                                        icon: Icons.chat_bubble_outline_rounded,
                                        selectedIcon: Icons.chat_bubble_rounded,
                                        tooltip: 'Chats',
                                        badgeCount: unreadCount,
                                      );
                                    },
                                  ),
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
              ),
            ),
          ),
        );
      },
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
                        color: isSelected ? AppColors.primary : AppColors.textMuted,
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
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.surface,
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
          child: Tooltip(
            message: 'Profile',
            child: SizedBox(
              height: 48,
              child: Center(
                child: _ProfileNavAvatar(
                  isSelected: currentIndex == 3,
                  handle: widget.currentUserHandle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileNavAvatar extends StatelessWidget {
  final bool isSelected;
  final String handle;

  const _ProfileNavAvatar({
    required this.isSelected,
    required this.handle,
  });

  @override
  Widget build(BuildContext context) {
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
            color: isSelected ? AppColors.primary : Colors.transparent,
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
