import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../motion.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';

/// Interactive upvote/downvote capsule widget with optimistic UI,
/// 300ms tap debouncing, animated score counters, and error rollback.
class VoteCapsule extends StatefulWidget {
  final Post post;
  final PostRepository repository;
  final bool isCompact;
  final VoidCallback? onVoteSuccess;

  const VoteCapsule({
    super.key,
    required this.post,
    required this.repository,
    this.isCompact = false,
    this.onVoteSuccess,
  });

  @override
  State<VoteCapsule> createState() => _VoteCapsuleState();
}

class _VoteCapsuleState extends State<VoteCapsule> {
  DateTime? _lastVoteTapTime;
  bool _isVoting = false;

  void _handleVote(int direction) async {
    final now = DateTime.now();
    if (_lastVoteTapTime != null &&
        now.difference(_lastVoteTapTime!).inMilliseconds < 300) {
      // Debounce rapid double-taps within 300ms
      return;
    }
    _lastVoteTapTime = now;

    if (_isVoting) return;

    // Haptic feedback for tactile feel
    HapticFeedback.selectionClick();

    setState(() => _isVoting = true);

    try {
      await widget.repository.votePost(widget.post.id, direction);
      if (mounted) {
        widget.onVoteSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1E293B),
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vote update failed: ${e.toString().replaceAll("Exception: ", "")}',
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isVoting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final int userVote = post.userVote;
    final int score = post.score;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color inkColor = isDark ? Colors.white : Colors.black;
    final Color upColor = userVote == 1 ? inkColor : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E));
    final Color downColor = userVote == -1 ? const Color(0xFFEF4444) : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E));
    final Color scoreColor = userVote == 1
        ? inkColor
        : (userVote == -1 ? const Color(0xFFEF4444) : (isDark ? Colors.white : Colors.black));

    final double height = widget.isCompact ? 32 : 36;
    final double iconSize = widget.isCompact ? 18 : 22;
    final double fontSize = widget.isCompact ? 12 : 13;

    final Color capsuleBg = isDark
        ? (userVote == 1 ? Colors.white12 : const Color(0xFF1A1A1A))
        : (userVote == 1 ? const Color(0xFFEAEAEA) : const Color(0xFFF4F4F4));
    final Color capsuleBorder = isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6);

    return Container(
      height: height,
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
          // Upvote Button
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.symmetric(horizontal: widget.isCompact ? 4 : 8),
            splashRadius: 18,
            icon: Icon(
              Icons.keyboard_arrow_up_rounded,
              size: iconSize,
              color: upColor,
            ),
            onPressed: () => _handleVote(1),
          ),

          // Score Value
          AnimatedSwitcher(
            duration: AppMotion.durationMicro,
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Text(
              '$score',
              key: ValueKey<int>(score),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: scoreColor,
              ),
            ),
          ),

          // Downvote Button
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.symmetric(horizontal: widget.isCompact ? 4 : 8),
            splashRadius: 18,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: iconSize,
              color: downColor,
            ),
            onPressed: () => _handleVote(-1),
          ),
        ],
      ),
    );
  }
}
