import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/telegram_storage_service.dart';

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
  final _contentController = TextEditingController();
  VadodaraArea _selectedArea = VadodaraArea.general;
  PostCategory _selectedCategory = PostCategory.general;
  String? _errorMessage;
  File? _imageFile;
  bool _isPublishing = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _contentController.addListener(_validateLiveInput);
    // Default to repo's currently selected area (if it's not general) for user convenience
    if (widget.repository.selectedArea != VadodaraArea.general) {
      _selectedArea = widget.repository.selectedArea;
    }
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
    if (mounted) {
      setState(() {
        _errorMessage = validationError;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked != null) {
        setState(() {
          _imageFile = File(picked.path);
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error selecting image: $e';
      });
    }
  }

  Future<void> _submitPost() async {
    final text = _contentController.text.trim();
    final validationError = ContentFilter.validateContent(text);

    if (validationError != null) {
      setState(() {
        _errorMessage = validationError;
      });
      return;
    }

    setState(() {
      _isPublishing = true;
      _uploadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      String? telegramImageUrl;
      
      // If user selected an image, upload to Telegram private channel or fallback to local Base64
      if (_imageFile != null) {
        try {
          telegramImageUrl = await TelegramStorageService.uploadImage(
            _imageFile!,
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _uploadProgress = progress;
                });
              }
            },
          );
        } catch (_) {}

        // Fallback: If Telegram CDN / backend proxy is offline, use compact Base64 encoding
        if (telegramImageUrl == null || telegramImageUrl.isEmpty) {
          try {
            final bytes = await _imageFile!.readAsBytes();
            final base64String = base64Encode(bytes);
            telegramImageUrl = 'data:image/jpeg;base64,$base64String';
          } catch (e) {
            debugPrint('Failed to encode image to base64: $e');
          }
        }
      }

      // Save post metadata to Cloud Firestore with the image link/data
      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: text,
        area: _selectedArea,
        category: _selectedCategory,
        imageUrl: telegramImageUrl,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('Your post is live in the community feed!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error publishing post: $e';
          _isPublishing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D30),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Post Anonymously',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              onPressed: _errorMessage == null && _contentController.text.trim().isNotEmpty && !_isPublishing
                  ? _submitPost
                  : null,
              child: _isPublishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Publish',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
              // Area & Category dropdowns
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NEIGHBORHOOD AREA',
                          style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF151D30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF243049)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<VadodaraArea>(
                              dropdownColor: const Color(0xFF151D30),
                              value: _selectedArea,
                              isExpanded: true,
                              items: VadodaraArea.values.map((area) {
                                return DropdownMenuItem(
                                  value: area,
                                  child: Text(
                                    area.displayName,
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedArea = val!),
                            ),
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
                        const Text(
                          'POST CATEGORY',
                          style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF151D30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF243049)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<PostCategory>(
                              dropdownColor: const Color(0xFF151D30),
                              value: _selectedCategory,
                              isExpanded: true,
                              items: PostCategory.values.map((cat) {
                                return DropdownMenuItem(
                                  value: cat,
                                  child: Row(
                                    children: [
                                      Text(cat.icon),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          cat.label,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedCategory = val!),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Content textfield
              TextField(
                controller: _contentController,
                maxLines: 8,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'Ask a question, share traffic status, warn about police checkers, or vent about civic issues...',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFF151D30),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF243049)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 16),

              // Image picker layout - Free Telegram CDN
              if (_imageFile != null)
                Stack(
                  children: [
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF243049)),
                        image: DecorationImage(
                          image: FileImage(_imageFile!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: InkWell(
                        onTap: () => setState(() => _imageFile = null),
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
                )
              else
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF60A5FA),
                    side: const BorderSide(color: Color(0xFF243049)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.image, size: 18),
                  label: const Text('Add Image (Free Telegram CDN)'),
                  onPressed: _isPublishing ? null : _pickImage,
                ),

              if (_isPublishing && _imageFile != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151D30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF243049)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Uploading Media...',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                        backgroundColor: const Color(0xFF243049),
                        color: const Color(0xFF3B82F6),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please wait, this might take a moment depending on your network.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],

              // Realtime safety validation feedback card
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F1D1D).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFF87171), fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Anonymity Info notice card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock_person, color: const Color(0xFF60A5FA).withOpacity(0.8), size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'Anonymity & Compliance Note',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your personal identity (phone, name) is never shown. You are posting under a randomized handle for this session. \n\nUnder India\'s IT Rules 2021 and DPDP Act 2023, doxxing, harassment, and sharing personal contacts is prohibited. We retain internal cryptographic identifiers for legal notices and repeat offender protection.',
                      style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.5),
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
