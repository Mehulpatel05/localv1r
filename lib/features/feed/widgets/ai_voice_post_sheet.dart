import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/areas_and_categories.dart';
import '../../../core/utils/content_filter.dart';
import '../../../services/ai_category_classifier_service.dart';
import '../../../services/post_repository.dart';
import '../../../services/speech_recognition_service.dart';
import '../../../services/token_decision_engine.dart';
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
  final PostRepository? repository;
  final String? currentUserHandle;
  final bool directPublish;

  const AiVoicePostSheet({
    super.key,
    this.repository,
    this.currentUserHandle,
    this.directPublish = false,
  });

  static Future<dynamic> show(
    BuildContext context, {
    PostRepository? repository,
    String? currentUserHandle,
    bool directPublish = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiVoicePostSheet(
        repository: repository,
        currentUserHandle: currentUserHandle,
        directPublish: directPublish,
      ),
    );
  }

  @override
  State<AiVoicePostSheet> createState() => _AiVoicePostSheetState();
}

class _AiVoicePostSheetState extends State<AiVoicePostSheet> with SingleTickerProviderStateMixin {
  final SpeechRecognitionService _speechService = SpeechRecognitionService.instance;
  final AiCategoryClassifierService _aiClassifier = AiCategoryClassifierService.instance;

  final TextEditingController _textController = TextEditingController();
  PostCategory _selectedCategory = PostCategory.general;
  String _detectedLang = 'hi';
  bool _isListening = false;
  double _soundLevel = 0.0;
  bool _speechAvailable = true;
  bool _isPermissionDenied = false;
  bool _isPublishing = false;
  String? _publishError;

  late final AnimationController _pulseAnimController;

  static const List<PostCategory> _categories = [
    PostCategory.general,
    PostCategory.question,
    PostCategory.events,
    PostCategory.alerts,
    PostCategory.safety,
  ];

  @override
  void initState() {
    super.initState();
    _pulseAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _textController.addListener(_onTextChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVoiceInputAuto();
    });
  }

  @override
  void dispose() {
    _pulseAnimController.dispose();
    _speechService.stopListening();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _selectedCategory = _aiClassifier.classify(text);
        _detectedLang = _aiClassifier.detectLanguage(text);
      });
    }
  }

  Future<void> _startVoiceInputAuto() async {
    if (!mounted) return;
    setState(() {
      _isPermissionDenied = false;
      _isListening = true;
      _publishError = null;
    });

    final hasPerm = await _speechService.requestPermission();
    if (!hasPerm) {
      if (!mounted) return;
      final permanentlyDenied = await _speechService.isPermissionPermanentlyDenied();
      setState(() {
        _isListening = false;
        _isPermissionDenied = true;
      });
      if (permanentlyDenied) {
        await _speechService.openSettings();
      }
      return;
    }

    final speechAvailable = await _speechService.initialize();
    if (!speechAvailable) {
      if (mounted) {
        setState(() {
          _speechAvailable = false;
          _isListening = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _speechAvailable = true;
      });
    }

    final started = await _speechService.startListening(
      onResult: (recognizedWords, isFinal) {
        if (!mounted) return;
        setState(() {
          _textController.text = recognizedWords;
          if (recognizedWords.trim().isNotEmpty) {
            _selectedCategory = _aiClassifier.classify(recognizedWords);
            _detectedLang = _aiClassifier.detectLanguage(recognizedWords);
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
        } else if (status == 'listening') {
          setState(() {
            _isListening = true;
          });
        }
      },
    );

    if (!started && mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  Future<void> _toggleListening() async {
    HapticFeedback.lightImpact();
    if (_isListening) {
      await _speechService.stopListening();
      if (mounted) setState(() => _isListening = false);
    } else {
      await _startVoiceInputAuto();
    }
  }

  Future<void> _submitAndProceed() async {
    if (_isPublishing) return;
    HapticFeedback.mediumImpact();

    await _speechService.stopListening();
    if (!mounted) return;

    final clean = _textController.text.trim();
    if (clean.length < 15) {
      setState(() {
        _publishError = 'Please speak or write at least 15 characters to post (currently ${clean.length}/15).';
      });
      return;
    }

    if (!widget.directPublish || widget.repository == null) {
      Navigator.pop(
        context,
        AiVoicePostResult(
          text: clean,
          category: _selectedCategory,
          detectedLanguage: _detectedLang,
        ),
      );
      return;
    }

    if (!TokenDecisionEngine.instance.canPost) {
      setState(() {
        _publishError = 'Your account is currently restricted from creating posts.';
      });
      return;
    }

    final validationError = ContentFilter.validateContent(clean);
    if (validationError != null) {
      setState(() {
        _publishError = validationError;
      });
      return;
    }

    setState(() {
      _isPublishing = true;
      _publishError = null;
    });

    try {
      final locService = widget.repository!.locationService;
      final effectiveCity = locService.city;
      final effectiveArea = locService.area ?? effectiveCity.areas.firstOrNull;
      final double? effectiveLat = effectiveArea?.lat ?? locService.rawLat;
      final double? effectiveLng = effectiveArea?.lng ?? locService.rawLng;

      await widget.repository!.addPost(
        authorHandle: widget.currentUserHandle ?? '',
        content: clean,
        category: _selectedCategory,
        cityId: effectiveCity.id,
        areaId: effectiveArea?.id ?? effectiveCity.id,
        areaName: effectiveArea?.name ?? effectiveCity.name,
        lat: effectiveLat,
        lng: effectiveLng,
      );

      if (!mounted) return;

      Navigator.pop(context, true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFFFEF3C7),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Posted to ${_selectedCategory.label} successfully!',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _publishError = 'Failed to publish post: $e';
        });
      }
    }
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
    final text = _textController.text.trim();
    final hasMinLength = text.length >= 15;
    final hasAnyText = text.isNotEmpty;

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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7EAF5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.language,
                            size: 14,
                            color: AppColors.primary,
                          ),
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
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 110, maxHeight: 180),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F7FA),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _isListening ? AppColors.primary.withValues(alpha: 0.45) : Colors.grey.shade200,
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _textController,
                maxLines: null,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                  height: 1.45,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: _isListening
                      ? 'Listening now... Speak in Hindi, Gujarati, or English'
                      : 'Tap mic to speak or type your post here...',
                  hintStyle: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: _isListening ? AppColors.primary : Colors.grey.shade500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hasMinLength
                      ? '✓ Ready to post (${text.length} characters)'
                      : '${text.length} / 15 characters minimum',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: hasMinLength ? const Color(0xFF059669) : const Color(0xFFD97706),
                  ),
                ),
                Text(
                  'Auto-categorized by AI',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Category:',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B5E68),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: _categories.map((cat) {
                        final isSelected = cat == _selectedCategory;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedCategory = cat;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : Colors.grey.shade300,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(cat.icon, style: const TextStyle(fontSize: 12)),
                                  const SizedBox(width: 4),
                                  Text(
                                    cat.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected ? Colors.white : const Color(0xFF333333),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            if (_isPermissionDenied) ...[
              const SizedBox(height: 12),
              const Text(
                'Microphone permission is required to listen.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () async {
                  await _speechService.openSettings();
                },
                icon: const Icon(Icons.settings, size: 16, color: AppColors.primary),
                label: const Text(
                  'Open Settings',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ] else if (!_speechAvailable) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Speech engine not ready. You can type directly above.',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _startVoiceInputAuto,
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _toggleListening,
              child: AnimatedBuilder(
                animation: _pulseAnimController,
                builder: (context, child) {
                  final pulse = _isListening
                      ? (1.0 + (_pulseAnimController.value * 0.12) + (_soundLevel * 0.02))
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
            const SizedBox(height: 8),
            Text(
              _isListening
                  ? 'Listening automatically... Speak now'
                  : (_speechAvailable ? 'Mic paused · Tap to speak' : 'Type your update above'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _isListening ? AppColors.primary : Colors.grey.shade600,
              ),
            ),
            if (_publishError != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _publishError!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                if (hasAnyText)
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isPublishing
                          ? null
                          : () {
                              setState(() {
                                _textController.clear();
                                _selectedCategory = PostCategory.general;
                                _publishError = null;
                              });
                              _startVoiceInputAuto();
                            },
                      child: const Text(
                        'Re-speak',
                        style: TextStyle(
                          color: Color(0xFF5A5258),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                if (hasAnyText) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasMinLength ? AppColors.primary : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      elevation: hasMinLength ? 2 : 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: (hasMinLength && !_isPublishing) ? _submitAndProceed : null,
                    child: _isPublishing
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Posting...',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                widget.directPublish ? 'Post Now' : 'Continue to Post',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                widget.directPublish ? Icons.send_rounded : Icons.arrow_forward_rounded,
                                size: 18,
                              ),
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
