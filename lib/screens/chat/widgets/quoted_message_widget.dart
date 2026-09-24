import 'package:flutter/material.dart';

/// Shows a quoted message preview inside a chat bubble (reply reference).
class QuotedMessageWidget extends StatelessWidget {
  final String senderHandle;
  final String previewText;
  final bool isMe;
  final bool isQuotedFromMe;
  final VoidCallback? onTap;

  const QuotedMessageWidget({
    super.key,
    required this.senderHandle,
    required this.previewText,
    required this.isMe,
    this.isQuotedFromMe = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cleanSender = senderHandle.replaceAll('@', '').trim();
    final displayName = (isQuotedFromMe || cleanSender.toLowerCase() == 'you')
        ? 'You'
        : '@$cleanSender';

    // Clean contrast matching sent (white in dark, black in light) and received bubbles
    final Color pillBg;
    final Color senderColor;
    final Color textColor;

    if (isMe) {
      if (isDark) {
        // Sent bubble in dark mode is white container
        pillBg = const Color(0xFFF1F5F9);
        senderColor = const Color(0xFF1D4ED8);
        textColor = const Color(0xFF334155);
      } else {
        // Sent bubble in light mode is black container
        pillBg = Colors.white.withValues(alpha: 0.12);
        senderColor = const Color(0xFF93C5FD);
        textColor = Colors.white.withValues(alpha: 0.85);
      }
    } else {
      if (isDark) {
        // Received bubble in dark mode is dark charcoal container
        pillBg = const Color(0xFF141414);
        senderColor = const Color(0xFF60A5FA);
        textColor = const Color(0xFF94A3B8);
      } else {
        // Received bubble in light mode is light grey container
        pillBg = const Color(0xFFE2E8F0);
        senderColor = const Color(0xFF2563EB);
        textColor = const Color(0xFF475569);
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: senderColor, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayName,
              style: TextStyle(
                color: senderColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              previewText,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
