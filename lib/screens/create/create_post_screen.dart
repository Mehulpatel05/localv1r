import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _areaController = TextEditingController();
  final _cityController = TextEditingController(text: 'Vadodara');
  // Common
  final _contentController = TextEditingController();
  PostCategory _selectedCategory = PostCategory.general;
  String? _errorMessage;
  File? _imageFile;
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
    _areaController.dispose();
    _cityController.dispose();
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

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked != null) setState(() => _imageFile = File(picked.path));
    } catch (e) {
      setState(() => _errorMessage = 'Error selecting image: $e');
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
      String? telegramImageUrl;
      if (_imageFile != null) {
        try {
          telegramImageUrl = await TelegramStorageService.uploadImage(
            _imageFile!,
            onProgress: (p) {
              if (mounted) setState(() => _uploadProgress = p);
            },
          );
        } catch (e) {
          debugPrint('Error uploading image: $e');
        }
        if (telegramImageUrl == null || telegramImageUrl.isEmpty) {
          throw Exception('Image upload failed. Please try again.');
        }
      }
      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: text,
        area: '${_areaController.text.trim()}, ${_cityController.text.trim()}',
        category: _selectedCategory,
        imageUrl: telegramImageUrl,
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

  Widget _buildLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: Colors.black54,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );

  Widget _buildTextField({
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
        style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.4),
        decoration: InputDecoration(
          hintText: hint,
          prefixText: prefixText,
          prefixStyle: const TextStyle(color: Colors.black87, fontSize: 14),
          hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.black12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF3B82F6)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );




  Widget _buildNormalForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _contentController,
          maxLines: 8,
          style: const TextStyle(color: Colors.black87, fontSize: 15, height: 1.4),
          decoration: InputDecoration(
            hintText:
                'Ask a question, share traffic status, warn about police checkers, or vent about civic issues...',
            hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.black12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3B82F6)),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(height: 16),
        if (_imageFile != null)
          Stack(
            children: [
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                  image: DecorationImage(
                      image: FileImage(_imageFile!), fit: BoxFit.cover),
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
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF3B82F6),
              side: const BorderSide(color: Colors.black12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.image, size: 18),
            label: const Text('Add Image (Free Telegram CDN)'),
            onPressed: _isPublishing ? null : _pickImage,
          ),
      ],
    );
  }

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
          'Post Anonymously',
          style: const TextStyle(
              color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              onPressed: _canPublish ? _submitPost : null,
              child: _isPublishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Publish',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
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
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('LOCATION DETAILS',
                            style: TextStyle(
                                color: Colors.black54,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildTextField(
                                controller: _areaController,
                                hint: 'Local Area',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: _buildTextField(
                                controller: _cityController,
                                hint: 'City',
                              ),
                            ),
                          ],
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
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<PostCategory>(
                              dropdownColor: Colors.white,
                              value: _selectedCategory,
                              isExpanded: true,
                              items: PostCategory.values
                                  .where((cat) => 
                                      cat != PostCategory.rooms && 
                                      cat != PostCategory.shop && 
                                      cat != PostCategory.food &&
                                      cat != PostCategory.events &&
                                      cat != PostCategory.jobs)
                                  .map((cat) {
                                return DropdownMenuItem(
                                  value: cat,
                                  child: Row(
                                    children: [
                                      Text(cat.icon),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(cat.label,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.black87,
                                                fontSize: 13)),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedCategory = val!),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildNormalForm(),
              if (_isPublishing && _imageFile != null) ...[
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
                            style: const TextStyle(
                                color: Color(0xFF3B82F6),
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                        backgroundColor: Colors.black12,
                        color: const Color(0xFF3B82F6),
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
                    color: const Color(0xFF7F1D1D).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.5)),
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
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF3B82F6).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock_person,
                            color: const Color(0xFF3B82F6),
                            size: 18),
                        const SizedBox(width: 8),
                        const Text('Anonymity & Compliance Note',
                            style: TextStyle(
                                color: Colors.black87,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Your personal identity (phone, name) is never shown. You are posting under a randomized handle for this session. \n\nUnder India's IT Rules 2021 and DPDP Act 2023, doxxing, harassment, and sharing personal contacts is prohibited. We retain internal cryptographic identifiers for legal notices and repeat offender protection.",
                      style: TextStyle(
                          color: Colors.black54, fontSize: 11, height: 1.5),
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
