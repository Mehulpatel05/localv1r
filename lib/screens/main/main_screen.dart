import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../services/post_repository.dart';
import '../feed/feed_screen.dart';
import '../bazar/bazar_screen.dart';
import '../profile/profile_screen.dart';
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

class _MainScreenState extends State<MainScreen> {
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
            extendBody: true,
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
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: SizedBox(
                  height: 68,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                    child: Center(
                      heightFactor: 1.0,
                      child: Container(
                        width: 236,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: AppColors.divider,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _buildNavItem(
                              index: 0,
                              isSelected: currentIndex == 0,
                              icon: Icons.home_rounded,
                              tooltip: 'Home',
                            ),
                            _buildNavItem(
                              index: 1,
                              isSelected: currentIndex == 1,
                              icon: Icons.storefront_rounded,
                              tooltip: 'Bazar',
                            ),
                            _buildNavItem(
                              index: 2,
                              isSelected: currentIndex == 2,
                              icon: Icons.chat_bubble_rounded,
                              tooltip: 'Chat',
                              badgeNotifier: DirectChatService.instance.unreadCountNotifier,
                            ),
                            _buildNavItem(
                              index: 3,
                              isSelected: currentIndex == 3,
                              icon: Icons.person_rounded,
                              tooltip: 'Profile',
                            ),
                          ],
                        ),
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
    required bool isSelected,
    required IconData icon,
    String? tooltip,
    ValueNotifier<int>? badgeNotifier,
  }) {
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
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 21,
                      color: isSelected ? Colors.white : const Color(0xFF5A5258),
                    ),
                  ),
                ),
                if (badgeNotifier != null)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: ValueListenableBuilder<int>(
                      valueListenable: badgeNotifier,
                      builder: (context, badgeCount, _) {
                        if (badgeCount <= 0) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        );
                      },
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
