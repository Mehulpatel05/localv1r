import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/location/location_models.dart';
import '../../core/location/location_selector_field.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/telegram_storage_service.dart';

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
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();

  GeoCity? _selectedGeoCity;
  GeoArea? _selectedGeoArea;
  String _selectedCategory = 'Electrical';
  File? _serviceImage;

  bool _showTitleError = false;
  bool _showPriceError = false;
  bool _showDescError = false;
  String? _contentFilterError;

  bool _isPublishing = false;
  double _uploadProgress = 0.0;
  bool _publishError = false;
  bool _publishSuccess = false;

  final List<Map<String, dynamic>> _categories = [
    {'name': 'Plumbing', 'icon': Icons.build_rounded},
    {'name': 'Electrical', 'icon': Icons.bolt_rounded},
    {'name': 'Home', 'icon': Icons.home_rounded},
    {'name': 'Cleaning', 'icon': Icons.cleaning_services_rounded},
    {'name': 'Tutors', 'icon': Icons.menu_book_rounded},
    {'name': 'Drivers', 'icon': Icons.directions_car_rounded},
    {'name': 'Cook', 'icon': Icons.restaurant_rounded},
    {'name': 'IT', 'icon': Icons.laptop_chromebook_rounded},
    {'name': 'Other', 'icon': Icons.more_horiz_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _descController.addListener(_onDescChanged);
    _titleController.addListener(() {
      if (_showTitleError && _titleController.text.trim().isNotEmpty) {
        setState(() => _showTitleError = false);
      }
    });
    _priceController.addListener(() {
      if (_showPriceError && _priceController.text.trim().isNotEmpty) {
        setState(() => _showPriceError = false);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
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
                title: const Text('Service Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Choose photo from gallery'),
                onTap: () => Navigator.pop(ctx, 'photo'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF3F4F6),
                  child: Icon(Icons.videocam_rounded, color: Colors.black87),
                ),
                title: const Text('Service Demo / Video', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Upload a video demonstration of your service'),
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
          setState(() => _serviceImage = File(picked.path));
        }
      } else {
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 80,
          maxWidth: 2048,
          maxHeight: 2048,
        );
        if (picked != null) {
          setState(() => _serviceImage = File(picked.path));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting media: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _submitService() async {
    final title = _titleController.text.trim();
    final price = _priceController.text.trim();
    final desc = _descController.text.trim();

    bool hasError = false;
    if (title.isEmpty) {
      setState(() => _showTitleError = true);
      hasError = true;
    }
    if (price.isEmpty) {
      setState(() => _showPriceError = true);
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
      _uploadProgress = 0.1;
    });

    try {
      String? imageUrl;
      if (_serviceImage != null) {
        setState(() => _uploadProgress = 0.4);
        imageUrl = await TelegramStorageService.uploadMedia(
          _serviceImage!,
          onProgress: (p) {
            if (mounted) {
              setState(() => _uploadProgress = 0.4 + (p * 0.4));
            }
          },
        );
      }

      setState(() => _uploadProgress = 0.85);

      final city = _selectedGeoCity ?? widget.repository.locationService.city;
      final area = _selectedGeoArea ?? widget.repository.locationService.area ?? city.areas.first;

      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: desc,
        category: PostCategory.services,
        cityId: city.id,
        areaId: area.id,
        serviceTitle: title,
        servicePrice: price,
        serviceCategoryText: _selectedCategory,
        imageUrl: imageUrl,
      );

      setState(() => _uploadProgress = 1.0);

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_publishSuccess) {
      return _buildSuccessState();
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Offer a Service',
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
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: const StadiumBorder(),
              ),
              onPressed: _isPublishing ? null : _submitService,
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
                  // Hero Header (Image 3)
                  const Text(
                    'Offer a Service',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Help people around your community.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 18),

                  // Step Progress Indicator (Image 3)
                  _buildStepIndicator(),
                  const SizedBox(height: 24),

                  // 1. SERVICE PHOTO Section (Image 3)
                  const Text(
                    'SERVICE PHOTO',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Add a clear photo of your work or service.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 10),

                  if (_serviceImage != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: TelegramStorageService.isVideoFile(_serviceImage!.path)
                              ? Container(
                                  height: 150,
                                  width: double.infinity,
                                  color: Colors.black87,
                                  child: const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 48),
                                        SizedBox(height: 6),
                                        Text('Service Video Attached', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                )
                              : Image.file(
                                  _serviceImage!,
                                  height: 150,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _serviceImage = null),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    GestureDetector(
                      onTap: _pickMedia,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24),
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
                              decoration: const BoxDecoration(
                                color: Color(0xFFEFF6FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add_rounded, color: Color(0xFF2563EB), size: 24),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Add Photo or Video',
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Recommended: clear photo or short work video',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // 2. SERVICE DETAILS Section (Image 3)
                  const Text(
                    'SERVICE DETAILS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Service Title *
                  const Text(
                    'Service Title *',
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
                      hintText: 'e.g. AC Repair & Servicing',
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
                        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Name your service clearly so locals know what you offer.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),

                  const SizedBox(height: 16),

                  // Price / Rate *
                  const Text(
                    'Price / Rate *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _priceController,
                    style: const TextStyle(fontSize: 14.5, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'e.g. Starting at ₹299',
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
                          color: _showPriceError ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'You can mention per visit, per hour, or a starting price.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),

                  const SizedBox(height: 24),

                  // 3. Choose a category Section (Image 3)
                  const Text(
                    'Choose a category',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categories.map((cat) {
                      final name = cat['name'] as String;
                      final icon = cat['icon'] as IconData;
                      final isSelected = _selectedCategory == name;

                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icon,
                                size: 14,
                                color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF2563EB)),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  // 4. SERVICE LOCATION Section (Image 3)
                  const Text(
                    'SERVICE LOCATION',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Where do you provide this service?',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 10),

                  LocationSelectorField(
                    onLocationSelected: (city, area) {
                      setState(() {
                        _selectedGeoCity = city;
                        _selectedGeoArea = area;
                      });
                    },
                  ),

                  const SizedBox(height: 24),

                  // 5. ABOUT YOUR SERVICE Section (Image 3)
                  const Text(
                    'ABOUT YOUR SERVICE',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tell locals what you offer.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _showDescError ? const Color(0xFFEF4444) : const Color(0xFF2563EB),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        TextField(
                          controller: _descController,
                          maxLines: 4,
                          maxLength: 400,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                          decoration: const InputDecoration(
                            hintText: 'Describe your service, experience, availability, contact details, etc.',
                            hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                            border: InputBorder.none,
                            counterText: '',
                            contentPadding: EdgeInsets.all(16),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 14, bottom: 10),
                          child: Text(
                            '${_descController.text.length} / 400',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 6. Privacy Notice Banner (Image 3)
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
                          child: const Icon(Icons.lock_rounded, color: Color(0xFF2563EB), size: 16),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your privacy matters',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Your listing is shared using your Nearhood handle. Only the information you choose to include is shown publicly.',
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

                  // 7. Post Service Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white : Colors.black,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _isPublishing ? null : _submitService,
                      child: const Text(
                        'Post Service',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Publishing Progress Modal (Image 4 Group 6)
          if (_isPublishing) _buildPublishingModal(),

          // Error Modal (Image 4 Group 8)
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
        _buildStepItem(2, 'Service', false),
        _buildStepLine(),
        _buildStepItem(3, 'Location', false),
        _buildStepLine(),
        _buildStepItem(4, 'Publish', false),
      ],
    );
  }

  Widget _buildStepItem(int num, String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$num',
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF94A3B8),
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
            color: isActive ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
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

  // Group 6: Publishing Progress Modal (Image 4)
  Widget _buildPublishingModal() {
    return Container(
      color: Colors.black45,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Publishing your service',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Uploading details...',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                minHeight: 8,
                backgroundColor: const Color(0xFFF1F5F9),
                color: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 16),
            _buildStatusStep('Uploading image...', _uploadProgress > 0.4),
            const SizedBox(height: 8),
            _buildStatusStep('Publishing service...', _uploadProgress > 0.8),
            const SizedBox(height: 8),
            _buildStatusStep('Service published', _uploadProgress >= 1.0),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusStep(String label, bool isDone) {
    return Row(
      children: [
        Icon(
          isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 16,
          color: isDone ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isDone ? FontWeight.w700 : FontWeight.w500,
            color: isDone ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  // Group 8: Error Modal (Image 4)
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
              'Couldn\'t publish service',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Something went wrong. Please check your connection and try again.',
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
                onPressed: _submitService,
                child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Group 7: Success Screen (Image 4)
  Widget _buildSuccessState() {
    return Scaffold(
      backgroundColor: Colors.white,
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
                'Service Posted',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your service is now visible to people in your local community.',
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
                  child: const Text('View Service', style: TextStyle(fontWeight: FontWeight.w700)),
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
