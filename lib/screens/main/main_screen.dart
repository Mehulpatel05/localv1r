import 'dart:math' as math;
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
  double _animFromIndex = 0.0;
  double _animToIndex = 0.0;
  late final AnimationController _liquidAnimController;
  late final Animation<double> _liquidPositionAnim;

  @override
  void initState() {
    super.initState();
    _cachedTabs[0] = _createTab(0);
    _liquidAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _liquidPositionAnim = CurvedAnimation(
      parent: _liquidAnimController,
      curve: Curves.easeInOutCubic,
    );
    _liquidAnimController.value = 1.0;
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
    _liquidAnimController.dispose();
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
    final currentProgress = _liquidPositionAnim.value;
    _animFromIndex = _animFromIndex + (_animToIndex - _animFromIndex) * currentProgress;
    _animToIndex = index.toDouble();
    _liquidAnimController.forward(from: 0.0);
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
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: Container(
                      width: 236,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFFE5ECEB),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2C7880).withValues(alpha: 0.12),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final totalWidth = constraints.maxWidth;
                          final totalHeight = constraints.maxHeight;
                          final itemWidth = totalWidth / 3;
                          const circleSize = 42.0;

                          return AnimatedBuilder(
                            animation: _liquidAnimController,
                            builder: (context, _) {
                              final progress = _liquidPositionAnim.value;
                              final currentPos = _animFromIndex + (_animToIndex - _animFromIndex) * progress;
                              final totalDistance = (_animToIndex - _animFromIndex).abs();
                              final stretchFactor = (totalDistance > 0.05)
                                  ? (math.sin(progress.clamp(0.0, 1.0) * math.pi) * 0.42 * math.min(totalDistance, 1.7))
                                  : 0.0;
                              final stretch = 1.0 + stretchFactor;
                              final currentW = circleSize * stretch;
                              final currentH = circleSize / math.sqrt(stretch);
                              final currentCenterX = currentPos * itemWidth + itemWidth / 2;
                              final currentLeft = currentCenterX - currentW / 2;
                              final currentTop = (totalHeight - currentH) / 2;

                              return Stack(
                                alignment: Alignment.centerLeft,
                                children: [
                                  Positioned(
                                    left: currentLeft,
                                    top: currentTop,
                                    width: currentW,
                                    height: currentH,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(currentH / 2),
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFF338890),
                                            Color(0xFF23656C),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF2C7880).withValues(alpha: 0.35),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      _buildNavItem(
                                        index: 0,
                                        currentPos: currentPos,
                                        icon: Icons.home_outlined,
                                        selectedIcon: Icons.home_rounded,
                                        tooltip: 'Home',
                                      ),
                                      _buildNavItem(
                                        index: 1,
                                        currentPos: currentPos,
                                        icon: Icons.storefront_outlined,
                                        selectedIcon: Icons.storefront_rounded,
                                        tooltip: 'Bazar',
                                      ),
                                      ValueListenableBuilder<int>(
                                        valueListenable: DirectChatService.instance.unreadCountNotifier,
                                        builder: (context, unreadCount, _) {
                                          return _buildNavItem(
                                            index: 2,
                                            currentPos: currentPos,
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
    required double currentPos,
    required IconData icon,
    required IconData selectedIcon,
    String? tooltip,
    int badgeCount = 0,
  }) {
    final dist = (currentPos - index).abs();
    final activeT = (1.0 - dist / 0.45).clamp(0.0, 1.0);
    final iconColor = Color.lerp(const Color(0xFF2C7880), Colors.white, activeT)!;
    const circleSize = 42.0;

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
                SizedBox(
                  width: circleSize,
                  height: circleSize,
                  child: Center(
                    child: Icon(
                      activeT > 0.5 ? selectedIcon : icon,
                      size: 22,
                      color: iconColor,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
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
                          fontSize: 9.5,
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
