import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/community_repository.dart';

class CreateCommunityScreen extends StatefulWidget {
  final CommunityRepository repository;
  final bool isChannel;

  const CreateCommunityScreen({
    super.key,
    required this.repository,
    required this.isChannel,
  });

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isLoading = false;
  File? _selectedImage; // Feature #7: community avatar

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  // Feature #7: Pick avatar image from gallery
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    final description = _descController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name.')),
      );
      return;
    }

    if (name.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name must be at least 3 characters.')),
      );
      return;
    }

    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description.')),
      );
      return;
    }

    if (description.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description must be at least 5 characters.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.repository.createCommunity(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        isChannel: widget.isChannel,
        imageFile: _selectedImage, // Feature #7: pass avatar
      );
      if (mounted) Navigator.pop(context, true); // F7: signal success to parent
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.isChannel ? 'Channel' : 'Group';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        title: Text(
          'Create New $type',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Feature #7: Avatar picker
            GestureDetector(
              onTap: _isLoading ? null : _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: isDark ? const Color(0xFF262626) : const Color(0xFFF4F4F4),
                    backgroundImage: _selectedImage != null
                        ? FileImage(_selectedImage!)
                        : null,
                    child: _selectedImage == null
                        ? Icon(
                            widget.isChannel ? Icons.campaign : Icons.group,
                            size: 48,
                            color: accentColor,
                          )
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: isDark ? Colors.black : Colors.white, width: 2),
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      color: isDark ? Colors.black : Colors.white,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to add photo',
              style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 12),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _nameController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: '$type Name *',
                labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                filled: true,
                fillColor: isDark ? const Color(0xFF141414) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: accentColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _descController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Description (What is this $type about?)',
                labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                filled: true,
                fillColor: isDark ? const Color(0xFF141414) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: accentColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : Colors.black,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  shape: const StadiumBorder(),
                  disabledBackgroundColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3),
                ),
                child: _isLoading
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: isDark ? Colors.black : Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        'Create $type',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.black : Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}