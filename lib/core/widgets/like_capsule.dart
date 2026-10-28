import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../motion.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../../theme/app_colors.dart';

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

  bool? _optimisticIsLiked;
  int? _optimisticCount;
  bool _isToggling = false;

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
    if (oldWidget.post.id != widget.post.id) {
      _optimisticIsLiked = null;
      _optimisticCount = null;
    } else if (!_isToggling) {
      final repoVote = widget.repository.getUserVote(widget.post.id);
      _optimisticIsLiked = (repoVote == 1 || widget.post.userVote == 1);
      _optimisticCount = widget.post.upvotes > 0 ? widget.post.upvotes : 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleToggleLike() {
    if (_isToggling) return;
    _isToggling = true;

    final repoVote = widget.repository.getUserVote(widget.post.id);
    final bool currentLiked = _optimisticIsLiked ?? (repoVote == 1 || widget.post.userVote == 1);
    final int currentCount = _optimisticCount ?? (widget.post.upvotes > 0 ? widget.post.upvotes : 0);

    final bool newLiked = !currentLiked;
    final int newCount = (currentCount + (newLiked ? 1 : -1)).clamp(0, 9999999);

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

    unawaited(() async {
      try {
        await widget.repository.votePost(widget.post.id, 1);
      } catch (e) {
        if (mounted) {
          setState(() {
            _optimisticIsLiked = currentLiked;
            _optimisticCount = currentCount;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.textPrimary,
              content: Text(
                'Like update failed: ${e.toString().replaceAll("Exception: ", "")}',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } finally {
        _isToggling = false;
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final repoVote = widget.repository.getUserVote(widget.post.id);
    final bool isLiked = _optimisticIsLiked ?? (repoVote == 1 || widget.post.userVote == 1);
    final int likeCount = _optimisticCount ?? (widget.post.upvotes > 0 ? widget.post.upvotes : 0);

    final double height = widget.isCompact ? 30 : 36;
    final double iconSize = widget.isCompact ? 15 : 18;
    final double fontSize = widget.isCompact ? 12 : 13;
    final double horizontalPadding = widget.isCompact ? 11 : 12;

    final Color capsuleBg = isLiked
        ? (widget.isCompact ? const Color(0xFFF7EAF5) : AppColors.primarySoft)
        : (widget.isCompact ? const Color(0xFFF6EEF4) : AppColors.likeBg);
    final Color capsuleBorder = isLiked
        ? (widget.isCompact ? const Color(0xFFEBDCE8) : AppColors.primarySoft)
        : (widget.isCompact ? const Color(0xFFEBDCE8) : AppColors.divider);
    final Color contentColor = isLiked
        ? (widget.isCompact ? const Color(0xFF3B1038) : AppColors.primaryText)
        : (widget.isCompact ? const Color(0xFF3B1038) : AppColors.textMuted);

    return Semantics(
      button: true,
      label: isLiked ? 'Unlike post' : 'Like post',
      value: likeCount == 1 ? '1 like' : '$likeCount likes',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleToggleLike,
          borderRadius: BorderRadius.circular(18),
          splashColor: AppColors.primary.withValues(alpha: 0.12),
          highlightColor: AppColors.primary.withValues(alpha: 0.06),
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
