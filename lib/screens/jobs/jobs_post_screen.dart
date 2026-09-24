import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/location/location_models.dart';
import '../../core/location/location_selector_field.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/r2_storage_service.dart';

class JobsPostScreen extends StatefulWidget {
  final PostRepository repository;
  final String authorHandle;

  const JobsPostScreen({
    super.key,
    required this.repository,
    required this.authorHandle,
  });

  @override
  State<JobsPostScreen> createState() => _JobsPostScreenState();
}

class _JobsPostScreenState extends State<JobsPostScreen> {
  final _titleController = TextEditingController();
  final _companyController = TextEditingController();
  final _descController = TextEditingController();
  
  GeoCity? _selectedGeoCity;
  GeoArea? _selectedGeoArea;
  String _workMode = 'On-site'; // 'On-site', 'Remote', 'Hybrid'
  String _selectedEmployment = 'Full-time';
  File? _bannerImage;
  
  bool _showTitleError = false;
  bool _showDescError = false;
  String? _contentFilterError;
  bool _isPublishing = false;
  double _uploadProgress = 0.0;

  final List<String> _employmentTypes = [
    'Full-time',
    'Part-time',
    'Freelance',
    'Internship',
    'Referral',
    'Hiring',
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
  }

  @override
  void dispose() {
    _titleController.dispose();
    _companyController.dispose();
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
                title: const Text('Company / Job Banner', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Choose photo or poster from gallery'),
                onTap: () => Navigator.pop(ctx, 'photo'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF3F4F6),
                  child: Icon(Icons.videocam_rounded, color: Colors.black87),
                ),
                title: const Text('Workplace / Hiring Video', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Upload a short video explaining the role or workplace'),
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
          setState(() => _bannerImage = File(picked.path));
        }
      } else {
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 80,
          maxWidth: 2048,
          maxHeight: 2048,
        );
        if (picked != null) {
          setState(() => _bannerImage = File(picked.path));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking media: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _publishJob() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();

    bool hasError = false;
    if (title.isEmpty) {
      setState(() => _showTitleError = true);
      hasError = true;
    }
    if (desc.isEmpty || _contentFilterError != null) {
      setState(() => _showDescError = true);
      hasError = true;
    }

    if (hasError) return;

    setState(() {
      _isPublishing = true;
      _uploadProgress = 0.2;
    });

    try {
      String? imageUrl;
      if (_bannerImage != null) {
        setState(() => _uploadProgress = 0.5);
        imageUrl = await R2StorageService.uploadMedia(_bannerImage!);
      }

      setState(() => _uploadProgress = 0.85);

      final city = _selectedGeoCity ?? widget.repository.locationService.city;
      final area = _selectedGeoArea ?? widget.repository.locationService.area ?? city.areas.first;
      final company = _companyController.text.trim().isEmpty ? 'Confidential Employer' : _companyController.text.trim();
      final locationStr = '${area.name}, ${city.name} ($_workMode)';

      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: desc,
        category: PostCategory.jobs,
        cityId: city.id,
        areaId: area.id,
        jobTitle: title,
        jobCompany: company,
        jobLocation: locationStr,
        jobType: _selectedEmployment,
        imageUrl: imageUrl,
      );

      setState(() => _uploadProgress = 1.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💼 Job posted successfully!'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create a job post',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: _isPublishing
          ? _buildPublishingState()
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step Progress Indicator (Image 3)
                    _buildStepIndicator(),
                    const SizedBox(height: 24),

                    // 1. Opportunity Section
                    const Text(
                      'Opportunity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Job title *
                    const Text(
                      'Job title *',
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
                        hintText: 'e.g. Senior Flutter Developer',
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
                    const SizedBox(height: 6),
                    const Text(
                      'Use a clear role name so people can find this opportunity.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),

                    // Title Inline Error Banner (Image 3 & 4)
                    if (_showTitleError) ...[
                      const SizedBox(height: 8),
                      _buildErrorBanner('Please enter a job title.'),
                    ],

                    const SizedBox(height: 18),

                    // Company name
                    const Text(
                      'Company',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _companyController,
                      style: const TextStyle(fontSize: 14.5, color: Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'Company name',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Leave blank if the employer should remain confidential.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),

                    const SizedBox(height: 24),

                    // 2. Work setup Section
                    const Text(
                      'Work setup',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Location Picker
                    LocationSelectorField(
                      onLocationSelected: (city, area) {
                        setState(() {
                          _selectedGeoCity = city;
                          _selectedGeoArea = area;
                        });
                      },
                    ),

                    const SizedBox(height: 12),

                    // On-site / Remote / Hybrid Segment
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: ['On-site', 'Remote', 'Hybrid'].map((mode) {
                          final isSelected = _workMode == mode;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _workMode = mode),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  mode,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 3. Employment Section (Image 3)
                    const Text(
                      'Employment',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Grid of 6 Employment types
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 3.2,
                      children: _employmentTypes.map((type) {
                        final isSelected = _selectedEmployment == type;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _selectedEmployment = type),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  type,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB), size: 18),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),

                    // 4. Description Section
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _showDescError ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
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
                              hintText: 'Describe the role, responsibilities, requirements and how to apply...',
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

                    // Description Inline Error Banner (Image 3 & 4)
                    if (_showDescError || _contentFilterError != null) ...[
                      const SizedBox(height: 8),
                      _buildErrorBanner(_contentFilterError ?? 'Please review your description.'),
                    ],

                    const SizedBox(height: 24),

                    // 5. Media Section (Image 3)
                    const Text(
                      'Media',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (_bannerImage != null) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: R2StorageService.isVideoFile(_bannerImage!.path)
                                ? Container(
                                    height: 140,
                                    width: double.infinity,
                                    color: Colors.black87,
                                    child: const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 48),
                                          SizedBox(height: 6),
                                          Text('Hiring / Workplace Video Attached', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  )
                                : Image.file(
                                    _bannerImage!,
                                    height: 140,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => setState(() => _bannerImage = null),
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
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEFF6FF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add_rounded, color: Color(0xFF2563EB), size: 22),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Add company banner or video',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Photo / Video • Optional',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // 6. Publish Job Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                          foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _publishJob,
                        child: const Text(
                          'Publish Job',
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
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _buildStepItem(1, 'Details', true),
        _buildStepLine(),
        _buildStepItem(2, 'Location', false),
        _buildStepLine(),
        _buildStepItem(3, 'Description', false),
        _buildStepLine(),
        _buildStepItem(4, 'Preview', false),
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

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFEE2E2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublishingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(color: Color(0xFF2563EB), strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text(
            _uploadProgress < 0.8
                ? 'Uploading banner image...'
                : 'Publishing job opportunity...',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Making your post visible to Vadodara neighbors',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ],
      ),
    );
  }
}
