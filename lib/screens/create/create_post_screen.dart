import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/location/location_models.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/utils/content_filter.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/post_repository.dart';
import '../../services/r2_storage_service.dart';

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

  // Common
  final _contentController = TextEditingController();
  String? _errorMessage;
  final List<File> _mediaFiles = [];
  bool _isPublishing = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
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

  Future<void> _pickMedia() async {
    try {
      final picker = ImagePicker();
      final pickedList = await picker.pickMultipleMedia(
        imageQuality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
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
      // Fallback for platform compatibility
      try {
        final picker = ImagePicker();
        final pickedImages = await picker.pickMultiImage(
          imageQuality: 90,
          maxWidth: 2048,
          maxHeight: 2048,
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
      } catch (fallbackError) {
        setState(() => _errorMessage = 'Error selecting media: $fallbackError');
      }
    }
  }

  bool get _canPublish =>
      !_isPublishing &&
      _contentController.text.trim().isNotEmpty &&
      _errorMessage == null;

  Future<void> _submitPost() async {
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
          // Upload failed — post without media, show warning
          debugPrint('Media upload failed, posting without media');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Color(0xFFF59E0B),
                content: Text('⚠️ Media upload failed — post will be published without media'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }
      final locService = widget.repository.locationService;
      final effectiveCity = _selectedGeoCity ?? locService.city;
      final String? firstImageUrl = uploadedMediaUrls.isNotEmpty ? uploadedMediaUrls.first : null;

      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: text,
        cityId: effectiveCity.id,
        category: PostCategory.general,
        imageUrl: firstImageUrl,
        mediaUrls: uploadedMediaUrls,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('Post published successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to publish post: $e'),
          ),
        );
      }
    }
  }

  Widget _buildMediaPreviews(bool isDark) {
    if (_mediaFiles.isEmpty) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.white : Colors.black,
          side: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.image, size: 18),
        label: const Text('Add Image'),
        onPressed: _isPublishing ? null : _pickMedia,
      );
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
                  color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFF0F172A),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
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
              onPressed: _isPublishing ? null : _pickMedia,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: Text('Add more (${_mediaFiles.length}/10)'),
              style: TextButton.styleFrom(
                foregroundColor: isDark ? Colors.white70 : Colors.black87,
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
                // Add more card
                return InkWell(
                  onTap: _isPublishing ? null : _pickMedia,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 110,
                    height: 120,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 28),
                        const SizedBox(height: 4),
                        Text(
                          'Add (${_mediaFiles.length}/10)',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
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
                      color: isDark ? const Color(0xFF141414) : const Color(0xFF0F172A),
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

  Widget _buildNormalForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _contentController,
          maxLines: 8,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15, height: 1.4),
          decoration: InputDecoration(
            hintText:
                'Ask a question, share traffic status, warn about police checkers, or vent about civic issues...',
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 14),
            filled: true,
            fillColor: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? Colors.white : Colors.black),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(height: 16),
        _buildMediaPreviews(isDark),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Post Anonymously',
          style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                shape: const StadiumBorder(),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: _canPublish ? _submitPost : null,
              child: _isPublishing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: isDark ? Colors.black : Colors.white, strokeWidth: 2),
                    )
                  : const Text('Publish',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13.5)),
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
              // Author identity bar
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
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
                            'Posting as @${widget.authorHandle.replaceAll('@', '')}',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          const Text(
                            'Visible to Vadodara community members',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('POST LOCATION',
                            style: TextStyle(
                                color: Colors.black54,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_on_rounded, size: 16, color: isDark ? Colors.white : Colors.black),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Vadodara (Citywide)',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('POST CATEGORY',
                            style: TextStyle(
                                color: Colors.black54,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Row(
                            children: const [
                              Text('💬', style: TextStyle(fontSize: 14)),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'General Chat',
                                  style: TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildNormalForm(),
              if (_isPublishing && _mediaFiles.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Uploading Media...',
                              style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                          Text(
                            '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                        backgroundColor: isDark ? const Color(0xFF262626) : Colors.black12,
                        color: isDark ? Colors.white : Colors.black,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please wait, this might take a moment depending on your network.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
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
                    color: const Color(0xFF7F1D1D).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFF87171), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_errorMessage!,
                            style: const TextStyle(
                                color: Color(0xFFF87171),
                                fontSize: 13,
                                height: 1.4)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lock_person,
                          color: isDark ? Colors.white : Colors.black87,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Anonymity & Compliance Note',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Your personal identity (phone, name) is never shown. You are posting under a randomized handle for this session. \n\nUnder India's IT Rules 2021 and DPDP Act 2023, doxxing, harassment, and sharing personal contacts is prohibited. We retain internal cryptographic identifiers for legal notices and repeat offender protection.",
                      style: TextStyle(
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
