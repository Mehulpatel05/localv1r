import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/telegram_storage_service.dart';

/// Dedicated Jobs Post Screen.
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
  final _locationController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedJobType = 'Full-time';
  File? _bannerImage;
  String? _errorMessage;
  bool _isPublishing = false;
  double _uploadProgress = 0.0;

  final List<String> _jobTypes = [
    'Full-time',
    'Part-time',
    'Contract / Freelance',
    'Internship',
    'Seeking Referral',
    'Hiring / Requirement'
  ];

  @override
  void initState() {
    super.initState();
    _descController.addListener(_validateLive);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _companyController.dispose();
    _locationController.dispose();
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
      _descController.text.trim().isNotEmpty &&
      _errorMessage == null;

  // ── Media pickers ───────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked != null) {
        setState(() => _bannerImage = File(picked.path));
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
      if (_bannerImage != null) {
        setState(() => _uploadProgress = 0.5);
        imageUrl = await TelegramStorageService.uploadImage(_bannerImage!);
      }

      setState(() => _uploadProgress = 0.9);

      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: _descController.text.trim(),
        category: PostCategory.jobs,
        jobTitle: _titleController.text.trim(),
        jobCompany: _companyController.text.trim().isEmpty ? 'Confidential' : _companyController.text.trim(),
        jobLocation: _locationController.text.trim().isEmpty ? 'Remote / Undisclosed' : _locationController.text.trim(),
        jobType: _selectedJobType,
        imageUrl: imageUrl,
      );

      setState(() => _uploadProgress = 1.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💼 Job posted successfully!'),
            backgroundColor: Color(0xFF0A66C2),
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
        title: const Text('Post a Job / Request',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
        actions: [
          if (_isPublishing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A66C2))),
            )
          else
            TextButton(
              onPressed: _canPublish ? _publishPost : null,
              child: Text(
                'Post',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _canPublish ? const Color(0xFF0A66C2) : Colors.black26,
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

                    // Job Title
                    const Text('Job Title / Role *',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _titleController,
                      hint: 'e.g. Senior Flutter Developer',
                      icon: Icons.work_outline_rounded,
                    ),
                    const SizedBox(height: 20),

                    // Company Name
                    const Text('Company Name',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _companyController,
                      hint: 'e.g. Google India (Leave blank if confidential)',
                      icon: Icons.business_rounded,
                    ),
                    const SizedBox(height: 20),
                    
                    // Location
                    const Text('Specific Location / Remote',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _locationController,
                      hint: 'e.g. Alkapuri or Remote',
                      icon: Icons.location_on_outlined,
                    ),
                    const SizedBox(height: 20),

                    // Job Type
                    const Text('Post Type',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      items: _jobTypes,
                      value: _selectedJobType,
                      onChanged: (val) => setState(() => _selectedJobType = val!),
                    ),
                    const SizedBox(height: 20),

                    // General Area
                    const Text('General Area',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildAreaDropdown(),
                    const SizedBox(height: 20),

                    // Description
                    const Text('Description / Details *',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descController,
                      maxLines: 5,
                      maxLength: 500,
                      style: const TextStyle(color: Colors.black87, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Share the job requirements, how to apply, or what kind of referral you need...',
                        hintStyle: const TextStyle(color: Colors.black38),
                        filled: true,
                        fillColor: const Color(0xFFF3F2EF),
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
                    const SizedBox(height: 20),

                    // Media
                    const Text('Company Logo or Banner (Optional)',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildBannerUpload(),
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
        fillColor: const Color(0xFFF3F2EF),
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

  Widget _buildDropdown({
    required List<String> items,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F2EF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
          items: items.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Text(type, style: const TextStyle(color: Colors.black87)),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildAreaDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F2EF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: Container(
          isExpanded: true,
          
          icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
          
          onChanged: (val) {
            if (val != null) setState(() => _selectedArea = val);
          },
        ),
      ),
    );
  }

  Widget _buildBannerUpload() {
    if (_bannerImage != null) {
      return Stack(
        children: [
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
              image: DecorationImage(
                image: FileImage(_bannerImage!),
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
              onPressed: () => setState(() => _bannerImage = null),
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
        height: 100,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F2EF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12, width: 1),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, color: Colors.black45, size: 30),
            SizedBox(height: 8),
            Text('Upload Image',
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
          const CircularProgressIndicator(color: Color(0xFF0A66C2)),
          const SizedBox(height: 24),
          Text(
            _uploadProgress < 0.9
                ? 'Uploading image... ${(_uploadProgress * 100).toInt()}%'
                : 'Publishing post...',
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
