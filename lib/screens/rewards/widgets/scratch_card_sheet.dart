import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/rewards_model.dart';
import '../../../services/rewards_service.dart';

class ScratchCardSheet extends StatefulWidget {
  final ScratchCardItem card;
  final VoidCallback? onScratched;

  const ScratchCardSheet({
    super.key,
    required this.card,
    this.onScratched,
  });

  static Future<void> show(
    BuildContext context, {
    required ScratchCardItem card,
    VoidCallback? onScratched,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ScratchCardSheet(
        card: card,
        onScratched: onScratched,
      ),
    );
  }

  @override
  State<ScratchCardSheet> createState() => _ScratchCardSheetState();
}

class _ScratchCardSheetState extends State<ScratchCardSheet>
    with SingleTickerProviderStateMixin {
  late bool _isScratched;
  bool _isClaiming = false;
  int _pointsAwarded = 0;
  final List<Offset> _points = [];
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _isScratched = widget.card.isScratched;
    _pointsAwarded = widget.card.pointsAmount;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );

    if (_isScratched) {
      _animController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, RenderBox box) {
    if (_isScratched || _isClaiming) return;
    final localPos = box.globalToLocal(details.globalPosition);
    if (localPos.dx >= 0 &&
        localPos.dx <= box.size.width &&
        localPos.dy >= 0 &&
        localPos.dy <= box.size.height) {
      setState(() {
        _points.add(localPos);
      });
      if (_points.length > 35) {
        _revealCard();
      }
    }
  }

  Future<void> _revealCard() async {
    if (_isScratched || _isClaiming) return;
    setState(() {
      _isClaiming = true;
      _isScratched = true;
    });

    HapticFeedback.heavyImpact();
    _animController.forward(from: 0.0);

    final res = await RewardsService.instance.scratchCard(widget.card.id);
    if (mounted) {
      setState(() {
        _isClaiming = false;
        if (res['success'] == true) {
          _pointsAwarded = (res['pointsAwarded'] as num?)?.toInt() ?? widget.card.pointsAmount;
        }
      });
      widget.onScratched?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1E24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(
          top: BorderSide(color: Color(0xFF134E5E), width: 1.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4.5,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF134E5E),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.stars_rounded,
                  size: 20,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.card.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _isScratched
              ? 'Congratulations! Reward added to your balance.'
              : 'Rub your finger over the card or tap to reveal!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 24),
          _buildCardBox(),
          const SizedBox(height: 24),
          if (!_isScratched)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2DD4BF),
                  foregroundColor: const Color(0xFF031214),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _revealCard,
                icon: const Icon(Icons.touch_app_rounded, size: 20),
                label: const Text(
                  'Quick Scratch & Reveal',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E8A3E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Collect Points & Close',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardBox() {
    return Container(
      width: double.infinity,
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isScratched ? const Color(0xFFF59E0B) : const Color(0xFF2DD4BF),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (_isScratched ? const Color(0xFFF59E0B) : const Color(0xFF2DD4BF))
                .withValues(alpha: 0.25),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            _buildRewardContent(),
            if (!_isScratched)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    return GestureDetector(
                      onPanUpdate: (details) {
                        final box = ctx.findRenderObject() as RenderBox?;
                        if (box != null) {
                          _onPanUpdate(details, box);
                        }
                      },
                      child: CustomPaint(
                        painter: ScratchFoilPainter(points: _points),
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardContent() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF072E33), Color(0xFF0F4C54)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    colors: [Color(0xFFFDE68A), Color(0xFFD97706)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                      blurRadius: 18,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.monetization_on_rounded,
                  size: 46,
                  color: Color(0xFF78350F),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '+$_pointsAwarded Points',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFDE68A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Instant Nearhood Loyalty Bonus',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2DD4BF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScratchFoilPainter extends CustomPainter {
  final List<Offset> points;

  ScratchFoilPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    final foilPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1E3A42), Color(0xFF134E5E), Color(0xFF0F766E)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(22),
      ),
      foilPaint,
    );

    final patternPaint = Paint()
      ..color = const Color(0xFF2DD4BF).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (double i = -size.height; i < size.width; i += 24) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        patternPaint,
      );
    }

    final textSpan = TextSpan(
      text: 'SCRATCH HERE',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.85),
        fontSize: 16,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.5,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );

    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 46.0
      ..style = PaintingStyle.stroke;

    if (points.isNotEmpty) {
      final path = Path();
      path.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, clearPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScratchFoilPainter oldDelegate) {
    return oldDelegate.points.length != points.length;
  }
}
