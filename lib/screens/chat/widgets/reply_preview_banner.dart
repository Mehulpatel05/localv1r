import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/name_cache_service.dart';
import '../../../theme/app_colors.dart';

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
    final cleanSender = senderHandle.replaceAll('@', '').trim();
    final cachedName = NameCacheService.instance.getDisplayName(cleanSender);
    final displayName = (isMe || cleanSender.toLowerCase() == 'you')
        ? 'You'
        : (cachedName.isNotEmpty ? cachedName : cleanSender);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        border: Border(
          top: BorderSide(
            color: AppColors.divider,
            width: 1,
          ),
          left: BorderSide(color: AppColors.primary, width: 3.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.reply_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $displayName',
                  style: TextStyle(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  style: TextStyle(
                    color: AppColors.textMuted,
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
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
