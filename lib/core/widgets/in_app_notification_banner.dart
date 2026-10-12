import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/user_avatar.dart';
import '../../theme/app_colors.dart';

class InAppNotificationBanner {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required String title,
    required String body,
    String? handle,
    String? photoUrl,
    bool isEmergency = false,
    required VoidCallback onTap,
  }) {
    dismiss();

    final overlayState = Overlay.maybeOf(context);
    if (overlayState == null) return;

    if (isEmergency) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    } else {
      HapticFeedback.lightImpact();
    }

    final safeTitle = title.trim().isNotEmpty ? title.trim() : 'Nearhood';
    final safeBody = body.trim().isNotEmpty ? body.trim() : 'You have a new notification';

    _currentEntry = OverlayEntry(
      builder: (ctx) => _BannerWidget(
        title: safeTitle,
        body: safeBody,
        handle: handle,
        photoUrl: photoUrl,
        isEmergency: isEmergency,
        onTap: () {
          dismiss();
          onTap();
        },
        onDismiss: dismiss,
      ),
    );

    overlayState.insert(_currentEntry!);

    _dismissTimer = Timer(Duration(milliseconds: isEmergency ? 8000 : 4200), () {
      dismiss();
    });
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _BannerWidget extends StatefulWidget {
  const _BannerWidget({
    required this.title,
    required this.body,
    this.handle,
    this.photoUrl,
    this.isEmergency = false,
    required this.onTap,
    required this.onDismiss,
  });

  final String title;
  final String body;
  final String? handle;
  final String? photoUrl;
  final bool isEmergency;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_BannerWidget> createState() => _BannerWidgetState();
}

class _BannerWidgetState extends State<_BannerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  double _dragOffsetY = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    _animController.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 6 + _dragOffsetY,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onTap: widget.onTap,
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta != null && details.primaryDelta! < 0) {
                setState(() {
                  _dragOffsetY += details.primaryDelta!;
                });
              }
            },
            onVerticalDragEnd: (details) {
              if (_dragOffsetY < -10 || (details.primaryVelocity ?? 0) < -200) {
                _handleDismiss();
              } else {
                setState(() => _dragOffsetY = 0.0);
              }
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.isEmergency ? const Color(0xFF1E0707) : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.isEmergency ? AppColors.error : AppColors.divider,
                    width: widget.isEmergency ? 1.8 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.isEmergency
                          ? AppColors.error.withValues(alpha: 0.35)
                          : const Color(0xFF111827).withValues(alpha: 0.12),
                      blurRadius: widget.isEmergency ? 24 : 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (widget.isEmergency)
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Color(0xFF451111),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          size: 22,
                          color: Color(0xFFFF5252),
                        ),
                      )
                    else if (widget.handle != null && widget.handle!.isNotEmpty)
                      UserAvatar(
                        handle: widget.handle!,
                        photoUrl: widget.photoUrl,
                        size: 38,
                      )
                    else
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.notifications_active_outlined,
                          size: 19,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: widget.isEmergency ? const Color(0xFFFF5252) : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.isEmergency ? const Color(0xFFFFCDD2) : AppColors.textMuted,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _handleDismiss,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: AppColors.textMuted,
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
}
