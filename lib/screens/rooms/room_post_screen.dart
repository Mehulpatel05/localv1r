import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/telegram_storage_service.dart';

/// Dedicated Room Listing Post Screen.
/// Completely independent from [CreatePostScreen].
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
  final _cityController = TextEditingController(text: 'Vadodara');
  final _titleController = TextEditingController();
  final _areaController = TextEditingController();
  final _rentController = TextEditingController();
  final _descController = TextEditingController();
  final List<File> _mediaFiles = [];
  String? _errorMessage;
  bool _isPublishing = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _descController.addListener(_validateLive);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _areaController.dispose();
    _cityController.dispose();
    _rentController.dispose();
    _descController.removeListener(_validateLive);
    _descController.dispose();
    super.dispose();
  }

  void _validateLive() {
    final text = _descController.text.trim();
    if (text.isEmpty) {
      if (mounted) setState(() => _errorMessage = null);
      return;
    }
    final err = ContentFilter.validateContent(text);
    if (mounted) setState(() => _errorMessage = err);
  }

  bool get _canPublish =>
      !_isPublishing &&
      _titleController.text.trim().isNotEmpty &&
      _rentController.text.trim().isNotEmpty &&
      _descController.text.trim().isNotEmpty &&
      _errorMessage == null;

  // ── Media pickers ───────────────────────────────────────────────────────
  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(imageQuality: 80);
      if (picked.isNotEmpty) {
        setState(() {
          for (final x in picked) {
            if (_mediaFiles.length < 8) _mediaFiles.add(File(x.path));
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error selecting images: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          if (_mediaFiles.length < 8) _mediaFiles.add(File(picked.path));
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error selecting video: $e');
    }
  }

  // ── Submit ──────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final desc = _descController.text.trim();
    final err = ContentFilter.validateContent(desc);
    if (err != null) {
      setState(() => _errorMessage = err);
      return;
    }

    setState(() {
      _isPublishing = true;
      _uploadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      final List<String> uploadedUrls = [];
      for (int i = 0; i < _mediaFiles.length; i++) {
        final file = _mediaFiles[i];
        String? url;
        try {
          url = await TelegramStorageService.uploadImage(
            file,
            onProgress: (p) {
              if (mounted) {
                setState(() => _uploadProgress =
                    (i / _mediaFiles.length) + (p / _mediaFiles.length));
              }
            },
          );
        } catch (_) {}
        if (url == null || url.isEmpty) {
          throw Exception('Failed to upload one or more images. Please check your connection and try again.');
        }
        if (url.isNotEmpty) uploadedUrls.add(url);
      }

      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: desc,
        category: PostCategory.rooms,
        imageUrl: uploadedUrls.isNotEmpty ? uploadedUrls.first : null,
        roomTitle: _titleController.text.trim(),
        roomArea: '${_areaController.text.trim()}, ${_cityController.text.trim()}',
        roomRent: _rentController.text.trim(),
        mediaUrls: uploadedUrls,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('Room listing posted! Other locals can now see it.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error posting listing: $e';
          _isPublishing = false;
        });
      }
    }
  }

  // ── UI helpers ──────────────────────────────────────────────────────────
  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: Colors.black54,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
  }) =>
      TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style:
            const TextStyle(color: Colors.black87, fontSize: 14, height: 1.4),
        decoration: InputDecoration(
          hintText: hint,
          prefixText: prefixText,
          prefixStyle:
              const TextStyle(color: Colors.black87, fontSize: 14),
          hintStyle:
              const TextStyle(color: Colors.black38, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.black12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.black12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF3B82F6)),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '🏠 List Your Room',
          style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              onPressed: _canPublish ? _submit : null,
              child: _isPublishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Post',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Area dropdown ──────────────────────────────────────────
            _label('LOCATION DETAILS'),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _field(
                    controller: _areaController,
                    hint: 'Local Area (e.g. Alkapuri)',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: _field(
                    controller: _cityController,
                    hint: 'City',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Title ─────────────────────────────────────────────────
            _label('ROOM TITLE *'),
            _field(
              controller: _titleController,
              hint: 'e.g. 1 BHK furnished room in Alkapuri',
            ),
            const SizedBox(height: 14),

            // ── Rent ────────────────────────────────────────────
            _label('MONTHLY RENT *'),
            _field(
              controller: _rentController,
              hint: 'e.g. 8000',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly
              ],
              prefixText: '₹ ',
            ),
            const SizedBox(height: 14),

            // ── Description ────────────────────────────────────────────
            _label('DESCRIPTION *'),
            _field(
              controller: _descController,
              hint:
                  'Furnishing, amenities, rules, nearby landmarks...',
              maxLines: 5,
            ),
            const SizedBox(height: 16),

            // ── Media ─────────────────────────────────────────────────
            _label('PHOTOS & VIDEO (max 8)'),
            if (_mediaFiles.isNotEmpty) ...[
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _mediaFiles.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final file = _mediaFiles[i];
                    final isVideo =
                        file.path.endsWith('.mp4') ||
                            file.path.endsWith('.mov') ||
                            file.path.endsWith('.avi');
                    return Stack(
                      children: [
                        Container(
                          width: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.black12),
                            color: const Color(0xFFF8FAFC),
                            image: isVideo
                                ? null
                                : DecorationImage(
                                    image: FileImage(file),
                                    fit: BoxFit.cover),
                          ),
                          child: isVideo
                              ? const Center(
                                  child: Icon(Icons.videocam,
                                      color: Colors.black26,
                                      size: 36))
                              : null,
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: InkWell(
                            onTap: () => setState(
                                () => _mediaFiles.removeAt(i)),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3B82F6),
                      side: const BorderSide(
                          color: Colors.black12),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.photo_library, size: 16),
                    label: const Text('Add Photos',
                        style: TextStyle(fontSize: 13)),
                    onPressed:
                        _isPublishing || _mediaFiles.length >= 8
                            ? null
                            : _pickImages,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3B82F6),
                      side: const BorderSide(
                          color: Colors.black12),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.videocam, size: 16),
                    label: const Text('Add Video',
                        style: TextStyle(fontSize: 13)),
                    onPressed:
                        _isPublishing || _mediaFiles.length >= 8
                            ? null
                            : _pickVideo,
                  ),
                ),
              ],
            ),

            // ── Upload progress ────────────────────────────────────────
            if (_isPublishing && _mediaFiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Uploading Media...',
                            style: TextStyle(
                                color: Colors.black87,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                        Text(
                            '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                                color: Color(0xFF3B82F6),
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _uploadProgress > 0
                          ? _uploadProgress
                          : null,
                      backgroundColor: Colors.black12,
                      color: const Color(0xFF3B82F6),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],

            // ── Error ──────────────────────────────────────────────────
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFEF4444).withOpacity(0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Color(0xFFF87171), size: 18),
                    const SizedBox(width: 8),
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF3B82F6).withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_person,
                      color:
                          const Color(0xFF3B82F6),
                      size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Posted anonymously under your session handle. Your phone & name are never shown.',
                      style: TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
