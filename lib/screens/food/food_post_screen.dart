import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/telegram_storage_service.dart';

/// Dedicated Food & Cafes Post Screen.
class FoodPostScreen extends StatefulWidget {
  final PostRepository repository;
  final String authorHandle;

  const FoodPostScreen({
    super.key,
    required this.repository,
    required this.authorHandle,
  });

  @override
  State<FoodPostScreen> createState() => _FoodPostScreenState();
}

class _FoodPostScreenState extends State<FoodPostScreen> {
  String? _selectedArea;
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  final List<File> _mediaFiles = [];
  String? _errorMessage;
  bool _isPublishing = false;
  double _uploadProgress = 0.0;
  
  // Rating out of 5
  double _rating = 4.0;

  @override
  void initState() {
    super.initState();
    _descController.addListener(_validateLive);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
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
      _priceController.text.trim().isNotEmpty &&
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

  void _removeMedia(int index) {
    setState(() {
      _mediaFiles.removeAt(index);
    });
  }

  // ── Publishing ─────────────────────────────────────────────────────────
  Future<void> _publishPost() async {
    if (!_canPublish) return;
    setState(() {
      _isPublishing = true;
      _errorMessage = null;
    });

    try {
      final List<String> uploadedUrls = [];
      
      for (int i = 0; i < _mediaFiles.length; i++) {
        setState(() => _uploadProgress = (i / _mediaFiles.length) * 0.8);
        final file = _mediaFiles[i];
        final url = await TelegramStorageService.uploadImage(file);
        if (url != null) {
          uploadedUrls.add(url);
        }
      }

      setState(() => _uploadProgress = 0.9);

      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: _descController.text.trim(),
        category: PostCategory.food,
        foodTitle: _titleController.text.trim(),
        foodPrice: _priceController.text.trim(),
        foodRating: _rating,
        imageUrl: uploadedUrls.isNotEmpty ? uploadedUrls.first : null,
        mediaUrls: uploadedUrls,
      );

      setState(() => _uploadProgress = 1.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Review posted successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isPublishing = false;
        _errorMessage = 'Failed to publish: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        elevation: 0,
        title: const Text('Post Food Review',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (_isPublishing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _canPublish ? _publishPost : null,
              child: Text(
                'Publish',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _canPublish ? const Color(0xFFF59E0B) : Colors.white38,
                ),
              ),
            )
        ],
      ),
      body: _isPublishing
          ? _buildPublishingState()
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(_errorMessage!,
                                    style: const TextStyle(color: Colors.red))),
                          ],
                        ),
                      ),

                    // Restaurant/Dish Name
                    const Text('Restaurant / Dish Name',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _titleController,
                      hint: 'e.g. Mocha Cafe or Cheese Burst Pizza',
                      icon: Icons.fastfood_rounded,
                    ),
                    const SizedBox(height: 20),

                    // Rating Slider
                    const Text('Your Rating',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 8),
                        Text('${_rating.toStringAsFixed(1)} / 5.0', 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        Expanded(
                          child: Slider(
                            value: _rating,
                            min: 1.0,
                            max: 5.0,
                            divisions: 8,
                            activeColor: const Color(0xFFF59E0B),
                            onChanged: (val) {
                              setState(() => _rating = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Price (Cost for Two)
                    const Text('Cost (Approx)',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _priceController,
                      hint: 'e.g. 500 for two',
                      icon: Icons.currency_rupee,
                    ),
                    const SizedBox(height: 20),

                    // Area
                    const Text('Location',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildAreaDropdown(),
                    const SizedBox(height: 20),

                    // Description
                    const Text('Your Review',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descController,
                      maxLines: 5,
                      maxLength: 400,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'How was the food, ambiance, and service?',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: const Color(0xFF151D30),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Media
                    const Text('Photos (Up to 8)',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildMediaGrid(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType type = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        filled: true,
        fillColor: const Color(0xFF151D30),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildAreaDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF151D30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          dropdownColor: const Color(0xFF151D30),
          value: _selectedArea,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
          items: <String>[].map((area) {
            return DropdownMenuItem(
              value: area,
              child: Text(area,
                  style: const TextStyle(color: Colors.white)),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedArea = val);
          },
        ),
      ),
    );
  }

  Widget _buildMediaGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (_mediaFiles.length < 8)
              GestureDetector(
                onTap: () {
                  FocusScope.of(context).unfocus();
                  _pickImages();
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF151D30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF243049)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate, color: Color(0xFFF59E0B)),
                      SizedBox(height: 4),
                      Text('Add',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            for (int i = 0; i < _mediaFiles.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _mediaFiles[i],
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: -4,
                    right: -4,
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black87,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 14),
                      ),
                      onPressed: () => _removeMedia(i),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPublishingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFFF59E0B)),
          const SizedBox(height: 24),
          Text(
            _uploadProgress < 0.9
                ? 'Uploading photos... ${(_uploadProgress * 100).toInt()}%'
                : 'Publishing review...',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
