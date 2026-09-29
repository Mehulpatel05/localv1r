import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../motion.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';

/// 🚀 Ultra-Fast Interactive Like Capsule Widget
/// Features:
/// 1. 0ms instant optimistic UI state & number transition.
/// 2. Instagram-grade heart pulse pop animation.
/// 3. Tactile haptic feedback.
/// 4. Non-blocking background network synchronization.
class LikeCapsule extends StatefulWidget {
  final Post post;
  final PostRepository repository;
  final bool isCompact;
  final VoidCallback? onLikeSuccess;
  final VoidCallback? onVoteSuccess;

  const LikeCapsule({
    super.key,
    required this.post,
    required this.repository,
    this.isCompact = false,
    this.onLikeSuccess,
    this.onVoteSuccess,
  });

  @override
  State<LikeCapsule> createState() => _LikeCapsuleState();
}

class _LikeCapsuleState extends State<LikeCapsule> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Local optimistic state for 0ms instantaneous UI updates
  bool? _optimisticIsLiked;
  int? _optimisticCount;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOutBack)), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 50),
    ]).animate(_pulseController);
  }

  @override
  void didUpdateWidget(LikeCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.userVote != widget.post.userVote ||
        oldWidget.post.upvotes != widget.post.upvotes) {
      _optimisticIsLiked = null;
      _optimisticCount = null;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleToggleLike() {
    final bool currentLiked = _optimisticIsLiked ?? (widget.post.userVote == 1);
    final int currentCount = _optimisticCount ?? (widget.post.upvotes > 0 ? widget.post.upvotes : 0);

    final bool newLiked = !currentLiked;
    final int newCount = (currentCount + (newLiked ? 1 : -1)).clamp(0, 9999999);

    // ⚡ 0ms Tactile & Visual Reaction
    HapticFeedback.lightImpact();

    if (newLiked) {
      _pulseController.forward(from: 0.0);
    }

    setState(() {
      _optimisticIsLiked = newLiked;
      _optimisticCount = newCount;
    });

    widget.onLikeSuccess?.call();
    widget.onVoteSuccess?.call();

    // Fire background non-blocking server call
    unawaited(() async {
      try {
        await widget.repository.votePost(widget.post.id, 1);
      } catch (e) {
        if (mounted) {
          // Rollback on genuine network failure
          setState(() {
            _optimisticIsLiked = currentLiked;
            _optimisticCount = currentCount;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF1E293B),
              content: Text(
                'Like update failed: ${e.toString().replaceAll("Exception: ", "")}',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final bool isLiked = _optimisticIsLiked ?? (widget.post.userVote == 1);
    final int likeCount = _optimisticCount ?? (widget.post.upvotes > 0 ? widget.post.upvotes : 0);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final double height = widget.isCompact ? 32 : 36;
    final double iconSize = widget.isCompact ? 16 : 18;
    final double fontSize = widget.isCompact ? 12 : 13;
    final double horizontalPadding = widget.isCompact ? 10 : 12;

    const Color likeRed = Color(0xFFEF4444);
    final Color unlikedColor = isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E);

    final Color capsuleBg = isDark
        ? (isLiked ? const Color(0xFF261316) : const Color(0xFF1A1A1A))
        : (isLiked ? const Color(0xFFFEE2E2) : const Color(0xFFF4F4F4));

    final Color capsuleBorder = isDark
        ? (isLiked ? const Color(0xFF5A2028) : const Color(0xFF262626))
        : (isLiked ? const Color(0xFFFECACA) : const Color(0xFFE6E6E6));

    final Color contentColor = isLiked ? likeRed : unlikedColor;

    return Semantics(
      button: true,
      label: isLiked ? 'Unlike post' : 'Like post',
      value: '$likeCount likes',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleToggleLike,
          borderRadius: BorderRadius.circular(18),
          splashColor: likeRed.withValues(alpha: 0.15),
          highlightColor: likeRed.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: AppMotion.durationMicro,
            height: height,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            decoration: BoxDecoration(
              color: capsuleBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: capsuleBorder,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: Icon(
                      isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      key: ValueKey<bool>(isLiked),
                      size: iconSize,
                      color: contentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Text(
                    '$likeCount',
                    key: ValueKey<int>(likeCount),
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                      color: contentColor,
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
