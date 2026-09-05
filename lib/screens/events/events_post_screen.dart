import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/telegram_storage_service.dart';

/// Dedicated Events Post Screen.
class EventsPostScreen extends StatefulWidget {
  final PostRepository repository;
  final String authorHandle;

  const EventsPostScreen({
    super.key,
    required this.repository,
    required this.authorHandle,
  });

  @override
  State<EventsPostScreen> createState() => _EventsPostScreenState();
}

class _EventsPostScreenState extends State<EventsPostScreen> {
  final _areaController = TextEditingController();
  final _cityController = TextEditingController(text: 'Vadodara');
  final _titleController = TextEditingController();
  final _dateController = TextEditingController();
  final _locationController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  File? _bannerImage;
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
    _dateController.dispose();
    _locationController.dispose();
    _priceController.dispose();
    _areaController.dispose();
    _cityController.dispose();
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
      _dateController.text.trim().isNotEmpty &&
      _locationController.text.trim().isNotEmpty &&
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
        if (imageUrl == null || imageUrl.isEmpty) {
          throw Exception('Image upload failed. Please try again.');
        }
      }

      setState(() => _uploadProgress = 0.9);

      await widget.repository.addPost(
        authorHandle: widget.authorHandle,
        content: _descController.text.trim(),
        category: PostCategory.events,
        area: '${_areaController.text.trim()}, ${_cityController.text.trim()}',
        eventTitle: _titleController.text.trim(),
        eventDate: _dateController.text.trim(),
        eventLocationText: _locationController.text.trim(),
        eventPrice: _priceController.text.trim().isEmpty ? 'Free' : _priceController.text.trim(),
        imageUrl: imageUrl,
      );

      setState(() => _uploadProgress = 1.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Event posted successfully!'),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text('Host an Event',
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
                'Publish',
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

                    // Event Name
                    const Text('Event Name',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _titleController,
                      hint: 'e.g. Neon Party 2024',
                      icon: Icons.celebration_rounded,
                    ),
                    const SizedBox(height: 20),

                    // Date & Time
                    const Text('Date & Time',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _dateController,
                      hint: 'Select Date & Time',
                      icon: Icons.calendar_today_rounded,
                      readOnly: true,
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2030),
                        );
                        if (date != null && mounted) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (time != null) {
                            final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                            final monthNames = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
                            final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
                            final amPm = time.period == DayPeriod.am ? 'AM' : 'PM';
                            final minute = time.minute.toString().padLeft(2, '0');
                            setState(() {
                              _dateController.text = '${monthNames[dt.month - 1]} ${dt.day}, $hour:$minute $amPm';
                            });
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    
                    // Specific Location
                    const Text('Venue Name / Address',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _locationController,
                      hint: 'e.g. Laxmi Vilas Palace Grounds',
                      icon: Icons.location_on_rounded,
                    ),
                    const SizedBox(height: 20),

                    // Price (Cost for Two)
                    const Text('Ticket Price',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _priceController,
                      hint: 'e.g. ₹500 or Free (Leave blank)',
                      icon: Icons.local_activity_rounded,
                    ),
                    const SizedBox(height: 20),

                    // Location fields
                    const Text('Location Details',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            controller: _areaController,
                            hint: 'Local Area (e.g. Alkapuri)',
                            icon: Icons.map_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: _buildTextField(
                            controller: _cityController,
                            hint: 'City/State',
                            icon: Icons.location_city_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Description
                    const Text('Event Description',
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descController,
                      maxLines: 5,
                      maxLength: 400,
                      style: const TextStyle(color: Colors.black87, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'What is this event about? Who is performing?',
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
                    const SizedBox(height: 20),

                    // Media
                    const Text('Banner Image',
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
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      readOnly: readOnly,
      onTap: onTap,
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

  Widget _buildBannerUpload() {
    if (_bannerImage != null) {
      return Stack(
        children: [
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
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
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12, width: 1.0, style: BorderStyle.solid),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, color: Colors.black45, size: 40),
            SizedBox(height: 12),
            Text('Upload Banner Image',
                style: TextStyle(color: Colors.black54, fontSize: 14)),
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
                ? 'Uploading banner image... ${(_uploadProgress * 100).toInt()}%'
                : 'Publishing event...',
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
