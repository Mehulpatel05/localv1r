import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/telegram_storage_service.dart';

/// Dedicated Local Services Post Screen.
class ServicesPostScreen extends StatefulWidget {
  final PostRepository repository;
  final String authorHandle;

  const ServicesPostScreen({
    super.key,
    required this.repository,
    required this.authorHandle,
  });

  @override
  State<ServicesPostScreen> createState() => _ServicesPostScreenState();
}

class _ServicesPostScreenState extends State<ServicesPostScreen> {
  final _areaController = TextEditingController(text: 'Vadodara');
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedServiceCategory = 'Home Maintenance';
  File? _serviceImage;
  String? _errorMessage;
  bool _isPublishing = false;
  double _uploadProgress = 0.0;

  final List<String> _serviceCategories = [
    'Plumbing',
    'Electrical',
    'Home Maintenance',
    'Cleaning',
    'Tutor / Classes',
    'Driver / Transport',
    'Cook / Maid',
    'IT / Computers',
    'Other Service'
  ];

  @override
  void initState() {
    super.initState();
    _descController.addListener(_validateLive);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _areaController.dispose();
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
  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked != null) {
        setState(() => _serviceImage = File(picked.path));
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error selecting image: $e');
    }
  }

  // ── Publishing ─────────────────────────────────────────────────────────
  Future<void> _publishPost() async {
    if (!_canPublish) return;
    setState(() {
      _isPublishing = true;
      _errorMessage = null;
    });

    try {
      String? imageUrl;
      if (_serviceImage != null) {
        setState(() => _uploadProgress = 0.5);
        imageUrl = await TelegramStorageService.uploadImage(_serviceImage!);
      }

      setState(() => _uploadProgress = 0.9);

      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: _descController.text.trim(),
        category: PostCategory.services,
        area: _areaController.text.trim(),
        serviceTitle: _titleController.text.trim(),
        servicePrice: _priceController.text.trim(),
        serviceCategoryText: _selectedServiceCategory,
        imageUrl: imageUrl,
      );

      setState(() => _uploadProgress = 1.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔧 Service offered successfully!'),
            backgroundColor: Color(0xFF3B82F6),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text('Offer a Service',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
        actions: [
          if (_isPublishing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6))),
            )
          else
            TextButton(
              onPressed: _canPublish ? _publishPost : null,
              child: Text(
                'Post',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _canPublish ? const Color(0xFF3B82F6) : Colors.black26,
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

                    // Media (Top for Grid view optimization)
                    const Text('Service Photo (Optional but recommended) *',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildImageUpload(),
                    const SizedBox(height: 20),

                    // Title
                    const Text('Service Title *',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _titleController,
                      hint: 'e.g. AC Repair & Servicing',
                      icon: Icons.title_rounded,
                    ),
                    const SizedBox(height: 20),

                    // Price
                    const Text('Price / Rate *',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _priceController,
                      hint: 'e.g. Starting at ₹299',
                      icon: Icons.currency_rupee_rounded,
                    ),
                    const SizedBox(height: 20),
                    
                    // Service Category
                    const Text('Service Category',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _serviceCategories.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final cat = _serviceCategories[index];
                          final isSelected = _selectedServiceCategory == cat;
                          return ChoiceChip(
                            label: Text(cat),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedServiceCategory = cat);
                              }
                            },
                            backgroundColor: Colors.white,
                            selectedColor: const Color(0xFFEFF6FF),
                            labelStyle: TextStyle(
                              color: isSelected ? const Color(0xFF3B82F6) : Colors.black87,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF3B82F6) : Colors.black12,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // General Area
                    const Text('Location',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _areaController,
                      hint: 'e.g. Alkapuri, Vadodara',
                      icon: Icons.location_on_outlined,
                    ),
                    const SizedBox(height: 20),

                    // Description
                    const Text('Details & Contact info *',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descController,
                      maxLines: 4,
                      maxLength: 400,
                      style: const TextStyle(color: Colors.black87, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Describe your service, experience, contact number, etc...',
                        hintStyle: const TextStyle(color: Colors.black38),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.black12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.black12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
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
      style: const TextStyle(color: Colors.black87, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38),
        prefixIcon: Icon(icon, color: Colors.black54, size: 20),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.black12),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }


  Widget _buildImageUpload() {
    if (_serviceImage != null) {
      return Stack(
        children: [
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
              image: DecorationImage(
                image: FileImage(_serviceImage!),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close,
                    color: Colors.white, size: 18),
              ),
              onPressed: () => setState(() => _serviceImage = null),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        _pickImage();
      },
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12, width: 1),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: Colors.black45, size: 30),
            SizedBox(height: 8),
            Text('Upload Photo',
                style: TextStyle(color: Colors.black54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildPublishingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF3B82F6)),
          const SizedBox(height: 24),
          Text(
            _uploadProgress < 0.9
                ? 'Uploading image... ${(_uploadProgress * 100).toInt()}%'
                : 'Publishing service...',
            style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
