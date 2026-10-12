import 'package:flutter/material.dart';
import '../../../core/services/name_cache_service.dart';
import '../../../theme/app_colors.dart';

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
    final cleanSender = senderHandle.replaceAll('@', '').trim();
    final cachedName = NameCacheService.instance.getDisplayName(cleanSender);
    final displayName = (isQuotedFromMe || cleanSender.toLowerCase() == 'you')
        ? 'You'
        : (cachedName.isNotEmpty ? cachedName : cleanSender);

    final Color pillBg;
    final Color senderColor;
    final Color textColor;

    if (isMe) {
      pillBg = Colors.white.withValues(alpha: 0.18);
      senderColor = Colors.white;
      textColor = Colors.white.withValues(alpha: 0.9);
    } else {
      pillBg = AppColors.chipBg;
      senderColor = AppColors.primaryText;
      textColor = AppColors.textMuted;
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
