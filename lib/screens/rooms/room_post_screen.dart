import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/location/location_models.dart';
import '../../core/location/location_selector_field.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/telegram_storage_service.dart';

class RoomPostScreen extends StatefulWidget {
  final PostRepository repository;
  final String authorHandle;

  const RoomPostScreen({
    super.key,
    required this.repository,
    required this.authorHandle,
  });

  @override
  State<RoomPostScreen> createState() => _RoomPostScreenState();
}

class _RoomPostScreenState extends State<RoomPostScreen> {
  final _titleController = TextEditingController();
  final _rentController = TextEditingController();
  final _descController = TextEditingController();

  GeoCity? _selectedGeoCity;
  GeoArea? _selectedGeoArea;
  final List<File> _mediaFiles = [];

  bool _showTitleError = false;
  bool _showRentError = false;
  bool _showDescError = false;
  String? _contentFilterError;

  bool _isPublishing = false;
  double _uploadProgress = 0.0;
  int _uploadCurrentIndex = 0;
  bool _publishError = false;
  bool _publishSuccess = false;

  @override
  void initState() {
    super.initState();
    _descController.addListener(_onDescChanged);
    _titleController.addListener(() {
      if (_showTitleError && _titleController.text.trim().isNotEmpty) {
        setState(() => _showTitleError = false);
      }
    });
    _rentController.addListener(() {
      if (_showRentError && _rentController.text.trim().isNotEmpty) {
        setState(() => _showRentError = false);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _rentController.dispose();
    _descController.removeListener(_onDescChanged);
    _descController.dispose();
    super.dispose();
  }

  void _onDescChanged() {
    final text = _descController.text.trim();
    if (_showDescError && text.isNotEmpty) {
      setState(() => _showDescError = false);
    }
    if (text.isNotEmpty) {
      final err = ContentFilter.validateContent(text);
      if (err != _contentFilterError) {
        setState(() => _contentFilterError = err);
      }
    } else {
      if (_contentFilterError != null) {
        setState(() => _contentFilterError = null);
      }
    }
  }

  Future<void> _pickMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF3F4F6),
                  child: Icon(Icons.photo_library_rounded, color: Colors.black87),
                ),
                title: const Text('Property Photos', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Choose photos from gallery'),
                onTap: () => Navigator.pop(ctx, 'media'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF3F4F6),
                  child: Icon(Icons.videocam_rounded, color: Colors.black87),
                ),
                title: const Text('Room Tour Video', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Upload a video walkthrough of the room'),
                onTap: () => Navigator.pop(ctx, 'video'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null) return;

    try {
      final picker = ImagePicker();
      if (choice == 'video') {
        final picked = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
        if (picked != null) {
          setState(() {
            if (_mediaFiles.length < 8) _mediaFiles.add(File(picked.path));
          });
        }
      } else {
        try {
          final pickedList = await picker.pickMultipleMedia(
            imageQuality: 80,
            maxWidth: 2048,
            maxHeight: 2048,
          );
          if (pickedList.isNotEmpty) {
            setState(() {
              for (final x in pickedList) {
                if (_mediaFiles.length < 8) _mediaFiles.add(File(x.path));
              }
            });
          }
        } catch (_) {
          final picked = await picker.pickMultiImage(
            imageQuality: 80,
            maxWidth: 2048,
            maxHeight: 2048,
          );
          if (picked.isNotEmpty) {
            setState(() {
              for (final x in picked) {
                if (_mediaFiles.length < 8) _mediaFiles.add(File(x.path));
              }
            });
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking media: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _submitListing() async {
    final title = _titleController.text.trim();
    final rent = _rentController.text.trim();
    final desc = _descController.text.trim();

    bool hasError = false;
    if (title.isEmpty) {
      setState(() => _showTitleError = true);
      hasError = true;
    }
    if (rent.isEmpty) {
      setState(() => _showRentError = true);
      hasError = true;
    }
    if (desc.isEmpty || _contentFilterError != null) {
      setState(() => _showDescError = true);
      hasError = true;
    }

    if (hasError) return;

    setState(() {
      _isPublishing = true;
      _publishError = false;
      _uploadProgress = 0.0;
      _uploadCurrentIndex = 0;
    });

    try {
      final List<String> uploadedUrls = [];
      for (int i = 0; i < _mediaFiles.length; i++) {
        setState(() => _uploadCurrentIndex = i + 1);
        final file = _mediaFiles[i];
        final url = await TelegramStorageService.uploadMedia(
          file,
          onProgress: (p) {
            if (mounted) {
              setState(() {
                _uploadProgress = ((i + p) / (_mediaFiles.isEmpty ? 1 : _mediaFiles.length));
              });
            }
          },
        );

        if (url != null && url.isNotEmpty) {
          uploadedUrls.add(url);
        }
      }

      final city = _selectedGeoCity ?? widget.repository.locationService.city;
      final area = _selectedGeoArea ?? widget.repository.locationService.area ?? city.areas.first;

      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: desc,
        cityId: city.id,
        areaId: area.id,
        category: PostCategory.rooms,
        imageUrl: uploadedUrls.isNotEmpty ? uploadedUrls.first : null,
        roomTitle: title,
        roomArea: '${area.name}, ${city.name}',
        roomRent: rent,
        mediaUrls: uploadedUrls,
      );

      if (mounted) {
        setState(() {
          _isPublishing = false;
          _publishSuccess = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _publishError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_publishSuccess) {
      return _buildSuccessState();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'List Your Room',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: const StadiumBorder(),
              ),
              onPressed: _isPublishing ? null : _submitListing,
              child: const Text(
                'Post',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step Progress Indicator (Image 2)
                  _buildStepIndicator(),
                  const SizedBox(height: 24),

                  // 1. LOCATION Section
                  const Text(
                    'LOCATION',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Where is the room?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  LocationSelectorField(
                    onLocationSelected: (city, area) {
                      setState(() {
                        _selectedGeoCity = city;
                        _selectedGeoArea = area;
                      });
                    },
                  ),

                  const SizedBox(height: 24),

                  // 2. ROOM DETAILS Section (Image 2)
                  const Text(
                    'ROOM DETAILS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Listing title *
                  const Text(
                    'Listing title *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(fontSize: 14.5, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'e.g. Furnished 1 BHK near Alkapuri',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _showTitleError ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? Colors.white : Colors.black, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Monthly rent *
                  const Text(
                    'MONTHLY RENT *',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _rentController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      prefixStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      hintText: '8,000',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _showRentError ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? Colors.white : Colors.black, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Set the monthly rent in INR',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),

                  const SizedBox(height: 24),

                  // 3. ABOUT THIS ROOM Section (Image 2)
                  const Text(
                    'ABOUT THIS ROOM',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141414) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _showDescError ? const Color(0xFFEF4444) : (isDark ? Colors.white : Colors.black),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        TextField(
                          controller: _descController,
                          maxLines: 5,
                          maxLength: 500,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                          decoration: const InputDecoration(
                            hintText: 'Describe furnishing, amenities, rules, nearby landmarks...',
                            hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                            border: InputBorder.none,
                            counterText: '',
                            contentPadding: EdgeInsets.all(16),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 14, bottom: 10),
                          child: Text(
                            '${_descController.text.length} / 500',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 4. PHOTOS & VIDEO Section (Image 2)
                  const Text(
                    'PHOTOS & VIDEO',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Good photos help locals understand the space.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),

                  // Media Picker Box
                  GestureDetector(
                    onTap: _mediaFiles.length < 8 ? _pickMedia : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFCBD5E1),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white : Colors.black,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.add_rounded, color: isDark ? Colors.black : Colors.white, size: 24),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Add property photos & video',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Up to 8 media files (${_mediaFiles.length}/8)',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2x2 Photo Grid (Image 2)
                  if (_mediaFiles.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _mediaFiles.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.3,
                      ),
                      itemBuilder: (context, index) {
                        final file = _mediaFiles[index];
                        final isCover = index == 0;
                        final isVideo = TelegramStorageService.isVideoFile(file.path);

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                color: Colors.black12,
                                child: isVideo
                                    ? Container(
                                        color: Colors.black87,
                                        child: const Center(
                                          child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 40),
                                        ),
                                      )
                                    : Image.file(file, fit: BoxFit.cover),
                              ),
                            ),
                            if (isCover)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white : Colors.black,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'COVER PHOTO',
                                    style: TextStyle(
                                      color: isDark ? Colors.black : Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: GestureDetector(
                                onTap: () => setState(() => _mediaFiles.removeAt(index)),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 24),

                  // 5. Privacy Protection Banner (Image 2)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.lock_rounded, color: isDark ? Colors.white : Colors.black, size: 16),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your privacy is protected',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'This listing is posted anonymously under your Nearhood handle. Your phone number and real name are not publicly displayed.',
                                style: TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Uploading Progress Modal (Image 4 State 3)
          if (_isPublishing) _buildUploadingModal(),

          // Error Modal (Image 4 State 4)
          if (_publishError) _buildErrorModal(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _buildStepItem(1, 'Details', true),
        _buildStepLine(),
        _buildStepItem(2, 'Location', false),
        _buildStepLine(),
        _buildStepItem(3, 'Photos', false),
        _buildStepLine(),
        _buildStepItem(4, 'Publish', false),
      ],
    );
  }

  Widget _buildStepItem(int num, String label, bool isActive) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isActive ? (isDark ? Colors.white : Colors.black) : (isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9)),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$num',
            style: TextStyle(
              color: isActive ? (isDark ? Colors.black : Colors.white) : const Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? (isDark ? Colors.white : Colors.black) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine() {
    return Expanded(
      child: Container(
        height: 1.5,
        color: const Color(0xFFE2E8F0),
        margin: const EdgeInsets.only(bottom: 14),
      ),
    );
  }

  // State 3: Upload Progress Modal (Image 4)
  Widget _buildUploadingModal() {
    final pct = (_uploadProgress * 100).toInt().clamp(0, 100);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141414) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF262626) : const Color(0xFFF4F4F4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_upload_rounded, color: isDark ? Colors.white : Colors.black, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'Uploading your listing',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _mediaFiles.isNotEmpty
                  ? 'Photos $_uploadCurrentIndex of ${_mediaFiles.length}'
                  : 'Publishing details...',
              style: TextStyle(color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                minHeight: 8,
                backgroundColor: isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9),
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // State 4: Error Modal (Image 4)
  Widget _buildErrorModal() {
    return Container(
      color: Colors.black45,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Couldn\'t publish your listing',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Something went wrong while uploading your media. Please check your connection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                onPressed: _submitListing,
                child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // State 5: Success Screen (Image 4)
  Widget _buildSuccessState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFECFDF5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'Listing Published',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your room is now visible to people in your local community.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                    foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('View Listing', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
