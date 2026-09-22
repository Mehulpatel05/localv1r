import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// A single row inside a [SettingsGroup] card.
///
/// Spec: padding 14, gap 14, InkWell press tint = field color (no ripple),
/// leading 44×44 circle, icon size 20, ink color.
/// Title 15.5 / w700 / ink. Description 13 / muted / h1.35.
/// Trailing chevron 18 / muted. Min height 72, min tap 48.
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

  /// Custom semantics label. Defaults to "$title, $description, button".
  final String? semanticsLabel;

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nearhoodColors;
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    final bg = _pressed && !disableAnimations ? c.field : Colors.transparent;

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
                        border: Border.all(color: c.ink, width: 2),
                      )
                    : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Leading circle icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c.field,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon, size: 20, color: c.ink),
                    ),
                    const SizedBox(width: 14),
                    // Text column — Expanded so it wraps on small screens
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: c.muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Trailing chevron
                    Icon(Icons.chevron_right, size: 18, color: c.muted),
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
