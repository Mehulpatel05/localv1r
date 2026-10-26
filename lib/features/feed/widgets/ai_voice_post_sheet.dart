import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/areas_and_categories.dart';
import '../../../services/ai_category_classifier_service.dart';
import '../../../services/speech_recognition_service.dart';
import '../../../theme/app_colors.dart';

class AiVoicePostResult {
  final String text;
  final PostCategory category;
  final String detectedLanguage;

  const AiVoicePostResult({
    required this.text,
    required this.category,
    required this.detectedLanguage,
  });
}

class AiVoicePostSheet extends StatefulWidget {
  const AiVoicePostSheet({super.key});

  static Future<AiVoicePostResult?> show(BuildContext context) {
    return showModalBottomSheet<AiVoicePostResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AiVoicePostSheet(),
    );
  }

  @override
  State<AiVoicePostSheet> createState() => _AiVoicePostSheetState();
}

class _AiVoicePostSheetState extends State<AiVoicePostSheet> with SingleTickerProviderStateMixin {
  final SpeechRecognitionService _speechService = SpeechRecognitionService.instance;
  final AiCategoryClassifierService _aiClassifier = AiCategoryClassifierService.instance;

  String _spokenText = '';
  PostCategory _suggestedCategory = PostCategory.general;
  String _detectedLang = 'hi';
  bool _isListening = false;
  double _soundLevel = 0.0;
  String? _errorMessage;

  late final AnimationController _pulseAnimController;

  @override
  void initState() {
    super.initState();
    _pulseAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVoiceListening();
    });
  }

  @override
  void dispose() {
    _pulseAnimController.dispose();
    _speechService.stopListening();
    super.dispose();
  }

  Future<void> _startVoiceListening() async {
    setState(() {
      _errorMessage = null;
      _isListening = true;
    });

    final success = await _speechService.startListening(
      onResult: (recognizedWords, isFinal) {
        if (!mounted) return;
        setState(() {
          _spokenText = recognizedWords;
          if (_spokenText.trim().isNotEmpty) {
            _suggestedCategory = _aiClassifier.classify(_spokenText);
            _detectedLang = _aiClassifier.detectLanguage(_spokenText);
          }
          if (isFinal) {
            _isListening = false;
          }
        });
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
        setState(() {
          _soundLevel = level.clamp(0.0, 10.0);
        });
      },
      onStatusChange: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() {
            _isListening = false;
          });
        }
      },
    );

    if (!success && mounted) {
      setState(() {
        _isListening = false;
        _errorMessage = 'Microphone access is unavailable or voice engine not responding.';
      });
    }
  }

  Future<void> _toggleListening() async {
    HapticFeedback.lightImpact();
    if (_isListening) {
      await _speechService.stopListening();
      if (mounted) setState(() => _isListening = false);
    } else {
      await _startVoiceListening();
    }
  }

  void _submitAndProceed() {
    HapticFeedback.mediumImpact();
    _speechService.stopListening();
    final clean = _spokenText.trim();
    if (clean.isEmpty) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(
      context,
      AiVoicePostResult(
        text: clean,
        category: _suggestedCategory,
        detectedLanguage: _detectedLang,
      ),
    );
  }

  String _formatLanguageLabel(String lang) {
    switch (lang) {
      case 'gu':
      case 'gu-Latn':
        return 'Gujarati';
      case 'hi':
      case 'hi-Latn':
        return 'Hindi';
      case 'en':
        return 'English';
      default:
        return 'Hindi / Hinglish';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasText = _spokenText.trim().isNotEmpty;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'AI Voice Post',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E141D),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7EAF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.language, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        _formatLanguageLabel(_detectedLang),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 110, maxHeight: 180),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F7FA),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _isListening ? AppColors.primary.withValues(alpha: 0.4) : Colors.grey.shade200,
                  width: 1.5,
                ),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  hasText
                      ? _spokenText
                      : (_isListening
                          ? 'Listening... Speak in Hindi, Gujarati, or English'
                          : 'Tap microphone to speak your update'),
                  style: TextStyle(
                    fontSize: hasText ? 16 : 14.5,
                    fontWeight: hasText ? FontWeight.w600 : FontWeight.w500,
                    color: hasText
                        ? const Color(0xFF1A1A1A)
                        : (_isListening ? AppColors.primary : Colors.grey.shade500),
                    height: 1.4,
                  ),
                ),
              ),
            ),
            if (hasText) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text(
                    'AI Category:',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B5E68),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _suggestedCategory.icon,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _suggestedCategory.label,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _toggleListening,
              child: AnimatedBuilder(
                animation: _pulseAnimController,
                builder: (context, child) {
                  final pulse = _isListening
                      ? (1.0 + (_pulseAnimController.value * 0.14) + (_soundLevel * 0.02))
                      : 1.0;
                  return Transform.scale(
                    scale: pulse,
                    child: Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: _isListening ? AppColors.primary : Colors.grey.shade100,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isListening
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : Colors.grey.shade300,
                          width: _isListening ? 4 : 1.5,
                        ),
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.white : AppColors.primary,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isListening ? 'Listening... Tap to stop' : 'Tap to speak',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _isListening ? AppColors.primary : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (hasText)
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _spokenText = '';
                          _suggestedCategory = PostCategory.general;
                        });
                        _startVoiceListening();
                      },
                      child: const Text(
                        'Clear',
                        style: TextStyle(
                          color: Color(0xFF5A5258),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                if (hasText) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasText ? AppColors.primary : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      elevation: hasText ? 2 : 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: hasText ? _submitAndProceed : null,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Continue to Post',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
