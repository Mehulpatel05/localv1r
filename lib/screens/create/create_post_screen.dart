import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_colors.dart';
import '../../core/location/location_models.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/services/name_cache_service.dart';
import '../../core/utils/content_filter.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/post_repository.dart';
import '../../services/r2_storage_service.dart';
import '../../services/token_decision_engine.dart';

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
  GeoCity? _selectedGeoCity;
  GeoArea? _selectedArea;
  bool _isEmergency = false;
  PostCategory _selectedCategory = PostCategory.general;

  final _contentController = TextEditingController();
  String? _errorMessage;
  final List<File> _mediaFiles = [];
  bool _isPublishing = false;
  double _uploadProgress = 0.0;

  double? _attachedLat;
  double? _attachedLng;
  String? _attachedLocationName;
  bool _isFetchingLocation = false;

  @override
  void initState() {
    super.initState();
    final loc = widget.repository.locationService;
    _selectedArea = loc.area ?? loc.city.areas.firstOrNull;
    _contentController.addListener(_validateLiveInput);
  }

  @override
  void dispose() {
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

  Future<void> _pickImagesFromGallery() async {
    try {
      final picker = ImagePicker();
      final pickedImages = await picker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 1440,
        maxHeight: 1440,
      );
      if (pickedImages.isNotEmpty) {
        setState(() {
          for (final x in pickedImages) {
            if (_mediaFiles.length < 10) {
              _mediaFiles.add(File(x.path));
            }
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error selecting images: $e');
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      final picker = ImagePicker();
      final pickedVideo = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 3),
      );
      if (pickedVideo != null) {
        setState(() {
          if (_mediaFiles.length < 10) {
            _mediaFiles.add(File(pickedVideo.path));
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error selecting video: $e');
    }
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

  void _showMediaPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Add Media to Post',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
                    'Choose Photos from Gallery',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImagesFromGallery();
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
                    'Choose Video from Gallery',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickVideoFromGallery();
                  },
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
                    'Take Photo with Camera',
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
                    'Record Video with Camera',
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
      _contentController.text.trim().isNotEmpty &&
      _errorMessage == null;

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
      final String? firstImageUrl = uploadedMediaUrls.isNotEmpty ? uploadedMediaUrls.first : null;

      final double? effectiveLat = _attachedLat ?? effectiveArea?.lat ?? locService.rawLat;
      final double? effectiveLng = _attachedLng ?? effectiveArea?.lng ?? locService.rawLng;

      final postResult = await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: text,
        cityId: effectiveCity.id,
        areaId: effectiveArea?.id ?? effectiveCity.id,
        areaName: effectiveArea?.name ?? 'Vadodara',
        lat: effectiveLat,
        lng: effectiveLng,
        category: _isEmergency ? PostCategory.safetyAlert : _selectedCategory,
        imageUrl: firstImageUrl,
        mediaUrls: uploadedMediaUrls,
      );

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
              onPressed: _isPublishing ? null : _showMediaPickerOptions,
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
                  onTap: _isPublishing ? null : _showMediaPickerOptions,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 110,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
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

  void _showAreaSelectorSheet() {
    final areas = widget.repository.locationService.city.areas;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.location_on_rounded, color: AppColors.primary, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Choose Neighborhood in Vadodara',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.divider),
              Expanded(
                child: ListView.builder(
                  itemCount: areas.length,
                  itemBuilder: (context, index) {
                    final area = areas[index];
                    final isSelected = _selectedArea?.id == area.id;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        color: isSelected ? AppColors.primary : AppColors.textMuted,
                        size: 20,
                      ),
                      title: Text(
                        area.name,
                        style: TextStyle(
                          color: isSelected ? AppColors.primary : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: area.pincode != null
                          ? Text('PIN: ${area.pincode}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11))
                          : null,
                      onTap: () {
                        setState(() => _selectedArea = area);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    UserAvatar(
                      handle: widget.authorHandle,
                      size: 34,
                      fontSize: 12.5,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Posting as ${getDisplayName(widget.authorHandle)}',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          const Text(
                            'Visible to Vadodara community members',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: AppColors.primary,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Posting in Neighborhood',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          Text(
                            _selectedArea?.name ?? 'All Vadodara',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: _showAreaSelectorSheet,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Change',
                          style: TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _isEmergency ? AppColors.errorSoft : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isEmergency ? AppColors.error : AppColors.divider,
                  ),
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
                              fontSize: 13.5,
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
                      onChanged: (val) {
                        setState(() => _isEmergency = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    PostCategory.general,
                    PostCategory.question,
                    PostCategory.events,
                    PostCategory.alerts,
                    PostCategory.safety,
                  ].map((cat) {
                    final isSelected = !_isEmergency && _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: InkWell(
                        onTap: _isEmergency
                            ? null
                            : () => setState(() => _selectedCategory = cat),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.divider,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(cat.icon, style: const TextStyle(fontSize: 13)),
                              const SizedBox(width: 5),
                              Text(
                                cat.label,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
              const SizedBox(height: 16),
              TextField(
                controller: _contentController,
                maxLines: 8,
                cursorColor: AppColors.primary,
                cursorWidth: 2.2,
                cursorHeight: 22.0,
                showCursor: true,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Ask a question, share traffic status, warn about police checkers, or vent about civic issues...',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14.5),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    _isEmergency ? Icons.info_outline_rounded : Icons.star_rounded,
                    size: 14,
                    color: _isEmergency ? AppColors.textMuted : const Color(0xFFD97706),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isEmergency
                        ? "Urgent alerts don't earn points"
                        : "+5 pts for a post (up to 50 pts/day)",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _isEmergency ? AppColors.textMuted : const Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.divider),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.photo_library_rounded, size: 18, color: AppColors.primary),
                    label: Text(
                      _mediaFiles.isEmpty ? 'Add Photos / Videos' : 'Add More (${_mediaFiles.length}/10)',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _isPublishing ? null : _showMediaPickerOptions,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _attachedLat != null ? AppColors.primaryText : AppColors.textPrimary,
                      backgroundColor: _attachedLat != null ? AppColors.primarySoft : AppColors.surface,
                      side: BorderSide(
                        color: _attachedLat != null ? AppColors.primary : AppColors.divider,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isFetchingLocation
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Icon(
                            _attachedLat != null ? Icons.my_location_rounded : Icons.add_location_alt_outlined,
                            size: 18,
                            color: _attachedLat != null ? AppColors.primary : AppColors.textMuted,
                          ),
                    label: Text(
                      _attachedLat != null ? 'Location Added' : 'Add Location',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _isPublishing || _isFetchingLocation ? null : _attachCurrentLocation,
                  ),
                ],
              ),
              if (_attachedLocationName != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _attachedLocationName!,
                          style: const TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: _removeAttachedLocation,
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(Icons.close_rounded, size: 16, color: AppColors.primaryText),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _buildMediaPreviews(),
              if (_isPublishing && _mediaFiles.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
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
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                        backgroundColor: AppColors.chipBg,
                        color: AppColors.primary,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please wait, this might take a moment depending on your network.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.errorSoftText,
                            fontSize: 13,
                            height: 1.4,
                          ),
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
