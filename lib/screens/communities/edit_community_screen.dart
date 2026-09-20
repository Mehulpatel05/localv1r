import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/community_repository.dart';
import '../../models/community_model.dart';

/// F2: Admin can edit community name, description, and avatar after creation
class EditCommunityScreen extends StatefulWidget {
  final CommunityRepository repository;
  final CommunityModel community;

  const EditCommunityScreen({
    super.key,
    required this.repository,
    required this.community,
  });

  @override
  State<EditCommunityScreen> createState() => _EditCommunityScreenState();
}

class _EditCommunityScreenState extends State<EditCommunityScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  File? _newImageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.community.name);
    _descController = TextEditingController(text: widget.community.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: isDark ? Colors.white : Colors.black,
                child: Icon(Icons.camera_alt, color: isDark ? Colors.black : Colors.white),
              ),
              title: const Text('Camera', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: isDark ? Colors.white : Colors.black,
                child: Icon(Icons.photo_library, color: isDark ? Colors.black : Colors.white),
              ),
              title: const Text('Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 512, maxHeight: 512);
    if (picked != null) {
      setState(() => _newImageFile = File(picked.path));
    }
  }

  Future<void> _save() async {
    final newName = _nameController.text.trim();
    final newDesc = _descController.text.trim();

    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty.')),
      );
      return;
    }

    if (newName.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name must be at least 3 characters.')),
      );
      return;
    }

    if (newDesc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description cannot be empty.')),
      );
      return;
    }

    if (newDesc.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description must be at least 5 characters.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.repository.editCommunity(
        communityId: widget.community.id,
        name: newName,
        description: newDesc,
        imageFile: _newImageFile,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Community updated successfully!')),
        );
        Navigator.pop(context, true); // true = updated
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? Colors.white : Colors.black;

    // Avatar: new file > existing URL > icon fallback
    ImageProvider? avatarImage;
    if (_newImageFile != null) {
      avatarImage = FileImage(_newImageFile!);
    } else if (widget.community.imageUrl != null &&
        widget.community.imageUrl!.isNotEmpty) {
      avatarImage = NetworkImage(widget.community.imageUrl!);
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        title: Text(
          'Edit Community',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                elevation: 0,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? Colors.black : Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Avatar picker
            GestureDetector(
              onTap: _isLoading ? null : _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: isDark ? const Color(0xFF262626) : const Color(0xFFF4F4F4),
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Icon(
                            widget.community.isChannel
                                ? Icons.campaign
                                : Icons.group,
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
                    child: Icon(Icons.camera_alt, color: isDark ? Colors.black : Colors.white, size: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Tap to change photo', style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 12)),
            const SizedBox(height: 28),

            // Name field
            TextField(
              controller: _nameController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Community Name *',
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

            // Description field
            TextField(
              controller: _descController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Description',
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
          ],
        ),
      ),
    );
  }
}