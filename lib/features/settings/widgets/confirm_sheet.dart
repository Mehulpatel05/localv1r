import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

enum _ButtonVariant { primary, ghost, danger }

class _SheetButton extends StatefulWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    required this.variant,
    this.isLoading = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final _ButtonVariant variant;
  final bool isLoading;
  final bool enabled;

  @override
  State<_SheetButton> createState() => _SheetButtonState();
}

class _SheetButtonState extends State<_SheetButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    Color bg;
    Color fg;
    Border? border;

    switch (widget.variant) {
      case _ButtonVariant.primary:
        bg = AppColors.primary;
        fg = Colors.white;
        break;
      case _ButtonVariant.ghost:
        bg = Colors.transparent;
        fg = AppColors.textPrimary;
        border = Border.all(color: AppColors.divider, width: 1.5);
        break;
      case _ButtonVariant.danger:
        bg = AppColors.error;
        fg = Colors.white;
        break;
    }

    final scale = (_pressed && widget.enabled && !disableAnimations) ? 0.985 : 1.0;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: Focus(
        child: AnimatedScale(
          scale: scale,
          duration: disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 100),
          child: GestureDetector(
            onTapDown: widget.enabled
                ? (_) => setState(() => _pressed = true)
                : null,
            onTapUp: widget.enabled
                ? (_) {
                    setState(() => _pressed = false);
                    widget.onTap();
                  }
                : null,
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedOpacity(
              opacity: widget.enabled ? 1.0 : 0.5,
              duration: const Duration(milliseconds: 100),
              child: Container(
                height: 54,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  border: border,
                ),
                alignment: Alignment.center,
                child: widget.isLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: fg,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ConfirmSheet extends StatefulWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    this.isDanger = false,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final Future<void> Function() onConfirm;
  final bool isDanger;

  @override
  State<ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<ConfirmSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _handleConfirm() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: !_loading,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(22, 10, 22, 22 + bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHandle(),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.02 * 20,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.body,
              style: const TextStyle(
                fontSize: 14.5,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.error,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetButton(
                  label: widget.confirmLabel,
                  onTap: _loading ? () {} : _handleConfirm,
                  variant: widget.isDanger
                      ? _ButtonVariant.danger
                      : _ButtonVariant.primary,
                  isLoading: _loading,
                  enabled: !_loading,
                ),
                const SizedBox(height: 10),
                _SheetButton(
                  label: widget.cancelLabel,
                  onTap: _loading ? () {} : () => Navigator.of(context).pop(),
                  variant: _ButtonVariant.ghost,
                  enabled: !_loading,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
  required Future<void> Function() onConfirm,
  bool isDanger = false,
}) {
  final disableAnimations = MediaQuery.of(context).disableAnimations;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    sheetAnimationStyle: disableAnimations
        ? AnimationStyle.noAnimation
        : AnimationStyle(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
    builder: (_) => ConfirmSheet(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      onConfirm: onConfirm,
      isDanger: isDanger,
    ),
  );
}
