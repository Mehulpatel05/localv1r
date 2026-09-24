import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shown above the chat input bar when the user swipes to reply a message.
class ReplyPreviewBanner extends StatelessWidget {
  final String senderHandle;
  final String previewText;
  final VoidCallback onCancel;
  final bool isMe;

  const ReplyPreviewBanner({
    super.key,
    required this.senderHandle,
    required this.previewText,
    required this.onCancel,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cleanSender = senderHandle.replaceAll('@', '').trim();
    final displayName = (isMe || cleanSender.toLowerCase() == 'you')
        ? 'You'
        : '@$cleanSender';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : const Color(0xFFF1F5F9),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0),
            width: 1,
          ),
          left: const BorderSide(color: Color(0xFF2563EB), width: 3.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.reply_rounded,
            size: 18,
            color: const Color(0xFF2563EB),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $displayName',
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF9A9A9A)
                        : const Color(0xFF64748B),
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onCancel();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: isDark
                    ? const Color(0xFF9A9A9A)
                    : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
