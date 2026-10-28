import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../../../core/constants/areas_and_categories.dart';
import '../../../core/utils/content_filter.dart';
import '../../../services/ai_category_classifier_service.dart';
import '../../../services/speech_recognition_service.dart';
import '../../../services/groq_whisper_service.dart';
import '../../../services/post_repository.dart';
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
  final AudioRecorder _audioRecorder = AudioRecorder();
  final GroqWhisperService _groqService = GroqWhisperService.instance;
  final AiCategoryClassifierService _aiClassifier = AiCategoryClassifierService.instance;

  final TextEditingController _textController = TextEditingController();
  PostCategory _selectedCategory = PostCategory.general;
  String _detectedLang = 'hi';
  bool _isRecording = false;
  bool _isTranscribing = false;
  double _soundLevel = 0.0;
  bool _isPermissionDenied = false;
  bool _isPublishing = false;
  String? _publishError;
  String? _currentAudioPath;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _recordTimer;
  int _recordSeconds = 0;

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
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _startRecordingAuto();
        }
      });
    });
  }

  @override
  void dispose() {
    _pulseAnimController.dispose();
    _amplitudeSub?.cancel();
    _recordTimer?.cancel();
    _speechService.cancelListening();
    _audioRecorder.dispose();
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

  Future<void> _startRecordingAuto() async {
    if (!mounted) return;
    setState(() {
      _isPermissionDenied = false;
      _isRecording = true;
      _isTranscribing = false;
      _publishError = null;
      _recordSeconds = 0;
    });

    final hasPerm = await _speechService.requestPermission();
    if (!hasPerm) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isPermissionDenied = true;
      });
      return;
    }

    bool started = false;
    try {
      started = await _speechService.startListening(
        onResult: (words, isFinal) {
          if (!mounted) return;
          if (words.trim().isNotEmpty) {
            setState(() {
              _textController.value = TextEditingValue(
                text: words,
                selection: TextSelection.collapsed(offset: words.length),
              );
            });
          }
        },
        onSoundLevelChange: (level) {
          if (!mounted) return;
          setState(() {
            _soundLevel = (level / 10.0).clamp(0.0, 1.0) * 10.0;
          });
        },
      );
    } catch (_) {
      started = false;
    }

    if (started) {
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          _recordSeconds++;
        });
        if (_recordSeconds >= 60) {
          _stopAndTranscribe();
        }
      });
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/ai_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentAudioPath = path;

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _amplitudeSub?.cancel();
      _amplitudeSub = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        if (!mounted) return;
        final normalized = ((amp.current + 50) / 50).clamp(0.0, 1.0);
        setState(() {
          _soundLevel = normalized * 10.0;
        });
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          _recordSeconds++;
        });
        if (_recordSeconds >= 30) {
          _stopAndTranscribe();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _publishError = 'Could not start microphone: $e';
        });
      }
    }
  }

  Future<void> _stopAndTranscribe() async {
    if (!_isRecording && !_isTranscribing) return;
    HapticFeedback.lightImpact();

    _amplitudeSub?.cancel();
    _recordTimer?.cancel();

    if (_speechService.isListening) {
      await _speechService.stopListening();
    }

    String? stoppedPath;
    if (await _audioRecorder.isRecording()) {
      stoppedPath = await _audioRecorder.stop() ?? _currentAudioPath;
    }

    final currentLiveText = _textController.text.trim();

    setState(() {
      _isRecording = false;
      _isTranscribing = true;
      _soundLevel = 0.0;
    });

    try {
      if (currentLiveText.isNotEmpty) {
        final result = await _groqService.polishHinglishAndGrammar(currentLiveText);
        if (!mounted) return;

        if (result != null && result.text.trim().isNotEmpty) {
          final clean = result.text.trim();
          PostCategory resolvedCategory = _aiClassifier.classify(clean);
          if (result.category != null) {
            final catStr = result.category!.toLowerCase();
            for (final cat in _categories) {
              if (cat.name.toLowerCase() == catStr || cat.label.toLowerCase() == catStr) {
                resolvedCategory = cat;
                break;
              }
            }
          }
          setState(() {
            _textController.text = clean;
            _selectedCategory = resolvedCategory;
            _detectedLang = result.language ?? _aiClassifier.detectLanguage(clean);
            _isTranscribing = false;
          });
        } else {
          setState(() {
            _isTranscribing = false;
          });
        }
      } else if (stoppedPath != null) {
        final result = await _groqService.transcribeAudio(stoppedPath);
        try {
          final file = File(stoppedPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}

        if (!mounted) return;

        if (result != null && result.text.trim().isNotEmpty) {
          final clean = result.text.trim();
          PostCategory resolvedCategory = _aiClassifier.classify(clean);
          if (result.category != null) {
            final catStr = result.category!.toLowerCase();
            for (final cat in _categories) {
              if (cat.name.toLowerCase() == catStr || cat.label.toLowerCase() == catStr) {
                resolvedCategory = cat;
                break;
              }
            }
          }
          setState(() {
            _textController.text = clean;
            _selectedCategory = resolvedCategory;
            _detectedLang = result.language ?? _aiClassifier.detectLanguage(clean);
            _isTranscribing = false;
          });
        } else {
          setState(() {
            _isTranscribing = false;
            if (_textController.text.trim().isEmpty) {
              _publishError = 'Could not capture voice clearly. Please tap mic and speak again or type above.';
            }
          });
        }
      } else {
        setState(() {
          _isTranscribing = false;
          if (_textController.text.trim().isEmpty) {
            _publishError = 'Could not capture voice clearly. Please tap mic and speak again or type above.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
          if (_textController.text.trim().isEmpty) {
            _publishError = 'Voice processing error: $e';
          }
        });
      }
    }
  }

  Future<void> _toggleListening() async {
    if (_isTranscribing) return;
    HapticFeedback.lightImpact();
    if (_isRecording) {
      await _stopAndTranscribe();
    } else {
      await _startRecordingAuto();
    }
  }

  Future<void> _submitAndProceed() async {
    if (_isPublishing || _isTranscribing) return;
    HapticFeedback.mediumImpact();

    if (_isRecording) {
      await _stopAndTranscribe();
      if (!mounted) return;
    }

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
    switch (lang.toLowerCase()) {
      case 'gu':
      case 'gu-latn':
        return 'Gujarati';
      case 'hi':
      case 'hi-latn':
        return 'Hindi';
      case 'en':
        return 'English';
      case 'hinglish':
        return 'Hinglish';
      default:
        return 'Hinglish';
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
                  color: _isRecording ? AppColors.primary.withValues(alpha: 0.45) : Colors.grey.shade200,
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
                  hintText: _isTranscribing
                      ? 'AI is converting to Hinglish & perfecting grammar...'
                      : (_isRecording
                          ? 'Listening now... Speak in Hindi, Gujarati, or English'
                          : 'Tap mic to speak or type your post here...'),
                  hintStyle: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: _isRecording ? AppColors.primary : Colors.grey.shade500,
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
                  await openAppSettings();
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
            ] else if (_isTranscribing) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'AI is perfecting grammar & formatting to Hinglish...',
                      style: TextStyle(
                        color: Color(0xFF15803D),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
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
                  final pulse = _isRecording
                      ? (1.0 + (_pulseAnimController.value * 0.12) + (_soundLevel * 0.02))
                      : 1.0;
                  return Transform.scale(
                    scale: pulse,
                    child: Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: _isRecording ? AppColors.primary : Colors.grey.shade100,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isRecording
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : Colors.grey.shade300,
                          width: _isRecording ? 4 : 1.5,
                        ),
                        boxShadow: _isRecording
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
                      child: _isTranscribing
                          ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : Icon(
                              _isRecording ? Icons.stop_rounded : Icons.mic_none,
                              color: _isRecording ? Colors.white : AppColors.primary,
                              size: 32,
                            ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isRecording
                  ? 'Listening (${_recordSeconds}s) · Tap to finish speaking'
                  : (_isTranscribing
                      ? 'Perfecting grammar & converting to Hinglish...'
                      : (text.isNotEmpty
                          ? 'Tap mic to re-speak or edit text above'
                          : 'Tap mic to speak · Powered by Groq AI')),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _isRecording ? AppColors.primary : Colors.grey.shade600,
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
                      onPressed: (_isPublishing || _isTranscribing)
                          ? null
                          : () {
                              setState(() {
                                _textController.clear();
                                _selectedCategory = PostCategory.general;
                                _publishError = null;
                              });
                              _startRecordingAuto();
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
                      backgroundColor: (hasMinLength && !_isTranscribing) ? AppColors.primary : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      elevation: (hasMinLength && !_isTranscribing) ? 2 : 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: (hasMinLength && !_isPublishing && !_isTranscribing) ? _submitAndProceed : null,
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
                        : (_isTranscribing
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
                                    'Transcribing...',
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
                              )),
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
