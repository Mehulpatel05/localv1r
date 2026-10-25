import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_colors.dart';
import '../../core/location/location_models.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/services/name_cache_service.dart';
import '../../core/utils/content_filter.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/post_repository.dart';
import '../../services/r2_storage_service.dart';
import '../../services/token_decision_engine.dart';
import '../../services/rewards_service.dart';
import '../../core/widgets/sliding_category_tab_bar.dart';

class CreatePostScreen extends StatefulWidget {
  final PostRepository repository;
  final String authorHandle;

  const CreatePostScreen({
    super.key,
    required this.repository,
    required this.authorHandle,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const List<PostCategory> _categories = [
    PostCategory.general,
    PostCategory.question,
    PostCategory.events,
    PostCategory.alerts,
    PostCategory.safety,
  ];

  GeoCity? _selectedGeoCity;
  GeoArea? _selectedArea;
  bool _isEmergency = false;
  PostCategory _selectedCategory = PostCategory.general;

  final _contentController = TextEditingController();
  String? _errorMessage;
  final List<File> _mediaFiles = [];
  bool _isPublishing = false;
  double _uploadProgress = 0.0;
  bool _isAnonymous = false;

  double? _attachedLat;
  double? _attachedLng;
  String? _attachedLocationName;
  bool _isFetchingLocation = false;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  File? _recordedAudioFile;
  bool _isRecordingAudio = false;
  bool _isPlayingAudioPreview = false;
  int _audioDurationSeconds = 0;
  Timer? _audioTimer;

  @override
  void initState() {
    super.initState();
    final loc = widget.repository.locationService;
    _selectedArea = loc.area ?? loc.city.areas.firstOrNull;
    _contentController.addListener(_validateLiveInput);
    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      final isPlaying = state.playing && state.processingState != ProcessingState.completed;
      if (isPlaying != _isPlayingAudioPreview) {
        setState(() => _isPlayingAudioPreview = isPlaying);
      }
    });
  }

  @override
  void dispose() {
    _audioTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _contentController.removeListener(_validateLiveInput);
    _contentController.dispose();
    super.dispose();
  }

  void _validateLiveInput() {
    final text = _contentController.text.trim();
    if (text.isEmpty) {
      if (mounted) setState(() => _errorMessage = null);
      return;
    }
    final validationError = ContentFilter.validateContent(text);
    if (mounted) setState(() => _errorMessage = validationError);
  }

  Future<void> _pickPhotosFromGallery() async {
    try {
      final picker = ImagePicker();
      final pickedList = await picker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 1440,
        maxHeight: 1440,
      );
      if (pickedList.isNotEmpty) {
        setState(() {
          for (final x in pickedList) {
            if (_mediaFiles.length < 10) {
              _mediaFiles.add(File(x.path));
            }
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error selecting photos: $e');
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 3),
      );
      if (video != null) {
        setState(() {
          if (_mediaFiles.length < 10) {
            _mediaFiles.add(File(video.path));
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error selecting video: $e');
    }
  }

  void _showGalleryOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.photo_library_rounded, color: AppColors.primary, size: 22),
                  ),
                  title: const Text(
                    'Photos',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickPhotosFromGallery();
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.video_library_rounded, color: AppColors.primary, size: 22),
                  ),
                  title: const Text(
                    'Videos',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickVideoFromGallery();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _capturePhotoFromCamera() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1440,
        maxHeight: 1440,
      );
      if (photo != null) {
        setState(() {
          if (_mediaFiles.length < 10) {
            _mediaFiles.add(File(photo.path));
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error capturing photo: $e');
    }
  }

  Future<void> _captureVideoFromCamera() async {
    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 3),
      );
      if (video != null) {
        setState(() {
          if (_mediaFiles.length < 10) {
            _mediaFiles.add(File(video.path));
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error recording video: $e');
    }
  }

  void _showCameraOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 22),
                  ),
                  title: const Text(
                    'Take Photo',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _capturePhotoFromCamera();
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.videocam_rounded, color: AppColors.primary, size: 22),
                  ),
                  title: const Text(
                    'Record Video',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _captureVideoFromCamera();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }



  Future<void> _attachCurrentLocation() async {
    if (_isPublishing) return;
    setState(() => _isFetchingLocation = true);
    try {
      final locService = widget.repository.locationService;
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos != null) {
        final areaName = _selectedArea?.name ?? locService.area?.name ?? locService.city.name;
        setState(() {
          _attachedLat = pos!.latitude;
          _attachedLng = pos.longitude;
          _attachedLocationName = '$areaName (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
          _isFetchingLocation = false;
        });
      } else if (locService.rawLat != null && locService.rawLng != null) {
        final areaName = _selectedArea?.name ?? locService.area?.name ?? locService.city.name;
        setState(() {
          _attachedLat = locService.rawLat;
          _attachedLng = locService.rawLng;
          _attachedLocationName = '$areaName (${locService.rawLat!.toStringAsFixed(4)}, ${locService.rawLng!.toStringAsFixed(4)})';
          _isFetchingLocation = false;
        });
      } else {
        setState(() => _isFetchingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not fetch GPS coordinates. Please ensure Location is enabled.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isFetchingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _removeAttachedLocation() {
    setState(() {
      _attachedLat = null;
      _attachedLng = null;
      _attachedLocationName = null;
    });
  }

  bool get _canPublish =>
      !_isPublishing &&
      !_isRecordingAudio &&
      (_contentController.text.trim().isNotEmpty || _mediaFiles.isNotEmpty || _recordedAudioFile != null) &&
      _errorMessage == null;

  Future<void> _startAudioRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/post_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
          path: path,
        );
        setState(() {
          _isRecordingAudio = true;
          _audioDurationSeconds = 0;
          _recordedAudioFile = null;
        });
        _audioTimer?.cancel();
        _audioTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() => _audioDurationSeconds++);
          if (_audioDurationSeconds >= 120) {
            _stopAudioRecording();
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Microphone error: $e');
    }
  }

  Future<void> _stopAudioRecording() async {
    _audioTimer?.cancel();
    try {
      final path = await _audioRecorder.stop();
      if (path != null && mounted) {
        final file = File(path);
        if (await file.exists()) {
          setState(() {
            _isRecordingAudio = false;
            _recordedAudioFile = file;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isRecordingAudio = false);
    }
  }

  Future<void> _toggleAudioPreview() async {
    if (_recordedAudioFile == null) return;
    if (_isPlayingAudioPreview) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.setFilePath(_recordedAudioFile!.path);
      await _audioPlayer.play();
    }
  }

  void _removeVoiceNote() {
    _audioPlayer.stop();
    _audioTimer?.cancel();
    setState(() {
      _recordedAudioFile = null;
      _isRecordingAudio = false;
      _audioDurationSeconds = 0;
      _isPlayingAudioPreview = false;
    });
  }

  Future<void> _submitPost() async {
    if (!TokenDecisionEngine.instance.canPost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account is currently restricted from creating posts.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final text = _contentController.text.trim();
    final validationError = ContentFilter.validateContent(text);
    if (validationError != null) {
      setState(() => _errorMessage = validationError);
      return;
    }

    setState(() {
      _isPublishing = true;
      _uploadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      List<String> uploadedMediaUrls = [];
      if (_mediaFiles.isNotEmpty) {
        try {
          uploadedMediaUrls = await R2StorageService.uploadMultipleMedia(
            _mediaFiles,
            onProgress: (p) {
              if (mounted) setState(() => _uploadProgress = p);
            },
          );
        } catch (e) {
          debugPrint('Error uploading media: $e');
        }
        if (uploadedMediaUrls.isEmpty && _mediaFiles.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Color(0xFFF59E0B),
                content: Text('Media upload failed — post will be published without media'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }
      final locService = widget.repository.locationService;
      final effectiveCity = _selectedGeoCity ?? locService.city;
      final effectiveArea = _selectedArea ?? locService.area ?? effectiveCity.areas.firstOrNull;
      String? uploadedAudioUrl;
      if (_recordedAudioFile != null) {
        try {
          uploadedAudioUrl = await R2StorageService.uploadMedia(_recordedAudioFile!);
        } catch (e) {
          debugPrint('Error uploading audio: $e');
        }
      }

      final String? firstImageUrl = uploadedMediaUrls.isNotEmpty ? uploadedMediaUrls.first : null;

      final double? effectiveLat = _attachedLat ?? effectiveArea?.lat ?? locService.rawLat;
      final double? effectiveLng = _attachedLng ?? effectiveArea?.lng ?? locService.rawLng;

      final postResult = await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: text,
        cityId: effectiveCity.id,
        areaId: effectiveArea?.id ?? effectiveCity.id,
        areaName: effectiveArea?.name ?? effectiveCity.name,
        lat: effectiveLat,
        lng: effectiveLng,
        category: _isEmergency ? PostCategory.safetyAlert : _selectedCategory,
        imageUrl: firstImageUrl,
        mediaUrls: uploadedMediaUrls,
        audioUrl: uploadedAudioUrl,
        isAnonymous: _isAnonymous,
      );

      if (_isEmergency) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_urgent_alert_timestamp', DateTime.now().millisecondsSinceEpoch);
      }

      if (mounted) {
        Navigator.pop(context, true);
        final awarded = (postResult['pointsAwarded'] as num?)?.toInt() ?? 0;
        final message = _isEmergency
            ? 'Alert broadcasted successfully!'
            : (awarded > 0 ? 'Published · +$awarded pts' : 'Post published successfully!');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                Icon(
                  (_isEmergency || awarded == 0) ? Icons.check_circle_rounded : Icons.star_rounded,
                  color: const Color(0xFFFEF3C7),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('Failed to publish post: $e'),
          ),
        );
      }
    }
  }

  Widget _buildMediaPreviews() {
    if (_mediaFiles.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_mediaFiles.length == 1) {
      final file = _mediaFiles.first;
      final isVideo = R2StorageService.isVideoFile(file.path);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 220,
                  width: double.infinity,
                  color: AppColors.chipBg,
                  child: isVideo
                      ? Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white38),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                          ),
                        )
                      : Image.file(
                          file,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 220,
                        ),
                ),
              ),
              if (isVideo)
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('Video', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: InkWell(
                  onTap: _isPublishing ? null : () => setState(() => _mediaFiles.clear()),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_mediaFiles.length < 10)
            TextButton.icon(
              onPressed: _isPublishing ? null : _showGalleryOptions,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: Text('Add more (${_mediaFiles.length}/10)'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _mediaFiles.length + (_mediaFiles.length < 10 ? 1 : 0),
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == _mediaFiles.length) {
                return InkWell(
                  onTap: _isPublishing ? null : _showGalleryOptions,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 110,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.divider,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded, color: AppColors.primary, size: 28),
                        SizedBox(height: 4),
                        Text(
                          'Add Media',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final file = _mediaFiles[index];
              final isVideo = R2StorageService.isVideoFile(file.path);
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 110,
                      height: 120,
                      color: AppColors.chipBg,
                      child: isVideo
                          ? Center(
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                              ),
                            )
                          : Image.file(
                              file,
                              fit: BoxFit.cover,
                              width: 110,
                              height: 120,
                            ),
                    ),
                  ),
                  if (isVideo)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 12),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: _isPublishing ? null : () => setState(() => _mediaFiles.removeAt(index)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<bool> _showUrgentAlertConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Urgent Safety Alert',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'This will notify neighbours within 3 km with an urgent safety alert.\n\nPlease use this only for genuine emergencies (e.g. fire, road accident, medical emergency, or lost child).',
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.textMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Confirm',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  Widget _buildToolbarPill({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isActive = false,
    bool isLoading = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.cardBorder,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  icon,
                  size: 14,
                  color: isActive ? Colors.white : AppColors.textPrimary,
                ),
              const SizedBox(width: 4.5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isActive ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locService = widget.repository.locationService;
    final lockedAreaName = _selectedArea?.name ?? locService.area?.name ?? locService.city.name;
    final lockedCityName = locService.city.name;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Post',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: _canPublish ? _submitPost : null,
              child: _isPublishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Publish',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (_isAnonymous)
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: AppColors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.visibility_off_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      )
                    else
                      UserAvatar(
                        handle: widget.authorHandle,
                        size: 38,
                        fontSize: 13.5,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isAnonymous
                                ? '$lockedAreaName Resident'
                                : getDisplayName(widget.authorHandle),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 1.5),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 12, color: AppColors.primary),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  lockedAreaName == lockedCityName
                                      ? lockedCityName
                                      : '$lockedAreaName, $lockedCityName',
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() => _isAnonymous = !_isAnonymous),
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _isAnonymous ? AppColors.primary : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isAnonymous ? AppColors.primary : AppColors.cardBorder,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isAnonymous ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              size: 13,
                              color: _isAnonymous ? Colors.white : AppColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isAnonymous ? 'Anonymous' : 'Public',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _isAnonymous ? Colors.white : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IgnorePointer(
                ignoring: _isEmergency,
                child: Opacity(
                  opacity: _isEmergency ? 0.45 : 1.0,
                  child: Container(
                    height: 40,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: SlidingCategoryTabBar(
                      categories: _categories.map((c) => c.label).toList(),
                      selectedIndex: _categories.indexOf(_selectedCategory).clamp(0, _categories.length - 1),
                      isScrollable: true,
                      onSelected: (index) {
                        if (!_isEmergency && index >= 0 && index < _categories.length) {
                          setState(() => _selectedCategory = _categories[index]);
                        }
                      },
                    ),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _contentController,
                      minLines: 4,
                      maxLines: 8,
                      cursorColor: AppColors.primary,
                      cursorWidth: 2.2,
                      cursorHeight: 22.0,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Share an update, ask neighbours, or discuss local news...',
                        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14.5),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (_attachedLocationName != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded, size: 14, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _attachedLocationName!,
                                style: const TextStyle(
                                  color: AppColors.primaryText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: _removeAttachedLocation,
                              child: const Icon(Icons.close_rounded, size: 14, color: AppColors.primaryText),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_mediaFiles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildMediaPreviews(),
                    ],
                    if (_recordedAudioFile != null || _isRecordingAudio) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isRecordingAudio ? AppColors.errorSoft : AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isRecordingAudio
                                ? AppColors.error.withValues(alpha: 0.3)
                                : AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (_isRecordingAudio) ...[
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Recording Audio... ${_audioDurationSeconds}s',
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: _stopAudioRecording,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.error,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'DONE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              InkWell(
                                onTap: _toggleAudioPreview,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _isPlayingAudioPreview ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Voice Note Attached (${_audioDurationSeconds}s)',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: _removeVoiceNote,
                                child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 20, color: Color(0xFFF1F5F9)),
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                _buildToolbarPill(
                                  icon: Icons.photo_library_rounded,
                                  label: _mediaFiles.isEmpty ? 'Photos' : 'Photos (${_mediaFiles.length})',
                                  isActive: _mediaFiles.isNotEmpty,
                                  onTap: _isPublishing ? null : _showGalleryOptions,
                                ),
                                const SizedBox(width: 6),
                                _buildToolbarPill(
                                  icon: Icons.camera_alt_rounded,
                                  label: 'Camera',
                                  onTap: _isPublishing ? null : _showCameraOptions,
                                ),
                                const SizedBox(width: 6),
                                _buildToolbarPill(
                                  icon: _attachedLat != null ? Icons.my_location_rounded : Icons.add_location_alt_outlined,
                                  label: 'Location',
                                  isActive: _attachedLat != null,
                                  isLoading: _isFetchingLocation,
                                  onTap: _isPublishing || _isFetchingLocation ? null : _attachCurrentLocation,
                                ),
                                const SizedBox(width: 6),
                                _buildToolbarPill(
                                  icon: _isRecordingAudio ? Icons.stop_circle_outlined : Icons.mic_rounded,
                                  label: _recordedAudioFile != null ? 'Voice Note' : (_isRecordingAudio ? 'Stop' : 'Voice Note'),
                                  isActive: _recordedAudioFile != null || _isRecordingAudio,
                                  onTap: _isPublishing
                                      ? null
                                      : (_isRecordingAudio ? _stopAudioRecording : _startAudioRecording),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (RewardsService.isRewardsEnabled) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 12, color: Color(0xFFD97706)),
                                const SizedBox(width: 2),
                                Text(
                                  _isEmergency ? 'Alert' : '+5 pts',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _isEmergency ? AppColors.errorSoft : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isEmergency ? AppColors.error : AppColors.cardBorder,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: _isEmergency ? AppColors.error : AppColors.chipBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: _isEmergency ? Colors.white : AppColors.textMuted,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mark as Urgent Safety Alert',
                            style: TextStyle(
                              color: _isEmergency ? AppColors.errorSoftText : AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Broadcasts to neighbors within 3 km',
                            style: TextStyle(
                              color: _isEmergency ? AppColors.errorSoftText : AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _isEmergency,
                      activeTrackColor: AppColors.error,
                      activeThumbColor: Colors.white,
                      onChanged: (val) async {
                        if (!val) {
                          setState(() => _isEmergency = false);
                          return;
                        }

                        final prefs = await SharedPreferences.getInstance();
                        final lastTimestamp = prefs.getInt('last_urgent_alert_timestamp') ?? 0;
                        final lastTime = DateTime.fromMillisecondsSinceEpoch(lastTimestamp);
                        final elapsed = DateTime.now().difference(lastTime);
                        if (elapsed.inMinutes < 30) {
                          final remaining = 30 - elapsed.inMinutes;
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Urgent safety alerts are limited to 1 every 30 minutes. Please wait $remaining more minute${remaining == 1 ? '' : 's'}.'),
                              backgroundColor: AppColors.error,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        final confirmed = await _showUrgentAlertConfirmationDialog();
                        if (confirmed && mounted) {
                          setState(() => _isEmergency = true);
                        }
                      },
                    ),
                  ],
                ),
              ),
              if (_isPublishing && _mediaFiles.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Uploading Media...',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                        backgroundColor: AppColors.chipBg,
                        color: AppColors.primary,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Please wait, this might take a moment depending on your network.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.error, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
