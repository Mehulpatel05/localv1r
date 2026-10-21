import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../services/post_repository.dart';
import '../feed/feed_screen.dart';
import '../bazar/bazar_screen.dart';
import '../chat/chat_list_screen.dart';
import '../../services/notification_service.dart';
import '../../services/direct_chat_service.dart';
import '../../services/rewards_service.dart';
import '../../services/auth_service.dart';
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
  late final List<Widget?> _cachedTabs = [null, null, null];

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
    final serverCityName = (userObj?['cityName'] ?? userObj?['homeCityName'] ?? userObj?['home_city_name'] ?? me['city_name']) as String?;

    final locService = widget.repository.locationService;
    if (serverCityName != null && serverCityName.trim().isNotEmpty) {
      final effectiveCityId = (serverCityId != null && serverCityId.isNotEmpty) ? serverCityId : locService.city.id;
      GeoCity resolvedCity = LocationEngine.lookupCity(effectiveCityId) ?? locService.city;
      if (resolvedCity.name != serverCityName.trim()) {
        resolvedCity = GeoCity(
          id: resolvedCity.id,
          stateId: resolvedCity.stateId,
          name: serverCityName.trim(),
          enabled: true,
          areas: resolvedCity.areas,
          lat: resolvedCity.lat,
          lng: resolvedCity.lng,
        );
      }
      if (locService.city.id != resolvedCity.id || locService.city.name != resolvedCity.name) {
        await locService.setCity(resolvedCity);
      }
    } else if (serverCityId != null && serverCityId.isNotEmpty && locService.city.id != serverCityId) {
      final resolvedCity = LocationEngine.lookupCity(serverCityId);
      if (resolvedCity != null) {
        await locService.setCity(resolvedCity);
      }
    }

    if (serverAreaName != null && serverAreaName.trim().isNotEmpty) {
      final effectiveCityId = (serverCityId != null && serverCityId.isNotEmpty) ? serverCityId : locService.city.id;
      final effectiveAreaId = (serverAreaId != null && serverAreaId.isNotEmpty) ? serverAreaId : effectiveCityId;
      if (locService.area?.name != serverAreaName.trim() || locService.area?.id != effectiveAreaId) {
        final matched = LocationEngine.lookupArea(effectiveAreaId);
        await locService.setArea(
          GeoArea(
            id: effectiveAreaId,
            cityId: locService.city.id,
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
    if (index == 0) {
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
        );
      case 1:
        return BazarScreen(
          currentUserHandle: widget.currentUserHandle,
        );
      case 2:
        return ChatListScreen(
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
              children: List.generate(3, (index) => _getOrCreateTab(index)),
            ),
            bottomNavigationBar: AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Container(
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(
                        color: const Color(0xFFE5ECEB),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final itemWidth = constraints.maxWidth / 3;
                        const circleSize = 52.0;
                        final pillColumn = currentIndex;
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              left: pillColumn * itemWidth + (itemWidth - circleSize) / 2,
                              width: circleSize,
                              height: circleSize,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2C7880),
                                  shape: BoxShape.circle,
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
    const circleSize = 52.0;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          _onTabTapped(index);
        },
        child: Tooltip(
          message: tooltip ?? '',
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? Colors.transparent : const Color(0xFFEFF5F6),
                  ),
                  child: Center(
                    child: Icon(
                      isSelected ? selectedIcon : icon,
                      size: 24,
                      color: isSelected ? Colors.white : const Color(0xFF2C7880),
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white,
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
    );
  }
}
