import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/location/location_selector_field.dart';
import '../../core/location/location_models.dart';
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
  GeoCity? _selectedGeoCity;
  GeoArea? _selectedGeoArea;

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
        cityId: (_selectedGeoCity ?? widget.repository.locationService.city).id,
        areaId: (_selectedGeoArea ?? widget.repository.locationService.area ?? (_selectedGeoCity ?? widget.repository.locationService.city).areas.first).id,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        title: Text(
          'Restaurants',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          if (_isPublishing)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ElevatedButton(
                onPressed: _canPublish ? _publishPost : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canPublish
                      ? (isDark ? Colors.white : Colors.black)
                      : (isDark ? Colors.white12 : Colors.black12),
                  foregroundColor: _canPublish
                      ? (isDark ? Colors.black : Colors.white)
                      : (isDark ? Colors.white38 : Colors.black38),
                  elevation: 0,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text(
                  'Publish',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
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
                    Text(
                      'Restaurant / Dish Name',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _titleController,
                      hint: 'e.g. Mocha Cafe or Cheese Burst Pizza',
                      icon: Icons.fastfood_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),

                    // Rating Slider
                    Text(
                      'Your Rating',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.star_rounded, color: isDark ? Colors.white : Colors.black),
                        const SizedBox(width: 8),
                        Text(
                          '${_rating.toStringAsFixed(1)} / 5.0', 
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _rating,
                            min: 1.0,
                            max: 5.0,
                            divisions: 8,
                            activeColor: isDark ? Colors.white : Colors.black,
                            inactiveColor: isDark ? Colors.white24 : Colors.black12,
                            onChanged: (val) {
                              setState(() => _rating = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Price (Cost for Two)
                    Text(
                      'Cost (Approx)',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _priceController,
                      hint: 'e.g. 500 for two',
                      icon: Icons.currency_rupee,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),

                    // Location fields
                    Text(
                      'Location Details',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LocationSelectorField(
                      onLocationSelected: (city, area) {
                        setState(() {
                          _selectedGeoCity = city;
                          _selectedGeoArea = area;
                        });
                      },
                    ),
                    const SizedBox(height: 20),

                    // Description
                    Text(
                      'Your Review',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descController,
                      maxLines: 5,
                      maxLength: 400,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'How was the food, ambiance, and service?',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Media
                    Text(
                      'Photos (Up to 8)',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildMediaGrid(isDark: isDark),
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
    required bool isDark,
    TextInputType type = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
        ),
        prefixIcon: Icon(
          icon,
          color: isDark ? Colors.white70 : Colors.black54,
          size: 20,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildMediaGrid({required bool isDark}) {
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
                    color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
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
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white : Colors.black87,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          color: isDark ? Colors.black : Colors.white,
                          size: 14,
                        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: isDark ? Colors.white : Colors.black,
          ),
          const SizedBox(height: 24),
          Text(
            _uploadProgress < 0.9
                ? 'Uploading photos... ${(_uploadProgress * 100).toInt()}%'
                : 'Publishing review...',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

