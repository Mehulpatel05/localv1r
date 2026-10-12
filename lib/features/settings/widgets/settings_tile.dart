import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

class SettingsTile extends StatefulWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.semanticsLabel,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final bg = _pressed && !disableAnimations ? AppColors.chipBg : Colors.transparent;

    return Semantics(
      label: widget.semanticsLabel ??
          '${widget.title}, ${widget.description}, button',
      button: true,
      child: Focus(
        child: Builder(
          builder: (ctx) {
            final hasFocus = Focus.of(ctx).hasFocus;
            return GestureDetector(
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) {
                setState(() => _pressed = false);
                widget.onTap();
              },
              onTapCancel: () => setState(() => _pressed = false),
              child: AnimatedContainer(
                duration: disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 80),
                color: bg,
                constraints: const BoxConstraints(minHeight: 72),
                padding: const EdgeInsets.all(14),
                decoration: hasFocus
                    ? BoxDecoration(
                        border: Border.all(color: AppColors.primary, width: 2),
                      )
                    : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.chipBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon, size: 20, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.description,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
