import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

enum MediaPickerMode {
  all,
  photoOnly,
  videoOnly,
}

class MediaAttachmentPicker {
  /// Shows a modern bottom sheet to pick photos, videos, or record with camera
  static Future<List<File>> showPickerSheet({
    required BuildContext context,
    MediaPickerMode mode = MediaPickerMode.all,
    int maxFiles = 8,
    int currentFileCount = 0,
    Duration maxVideoDuration = const Duration(minutes: 5),
  }) async {
    final remainingSlots = maxFiles - currentFileCount;
    if (remainingSlots <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum $maxFiles files allowed.')),
      );
      return [];
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Attach Media',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
              if (mode == MediaPickerMode.all || mode == MediaPickerMode.photoOnly) ...[
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(Icons.camera_alt_rounded, color: Color(0xFF2563EB)),
                  ),
                  title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Capture picture using camera'),
                  onTap: () => Navigator.pop(ctx, 'camera_photo'),
                ),
              ],
              if (mode == MediaPickerMode.all || mode == MediaPickerMode.videoOnly) ...[
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFAF5FF),
                    child: Icon(Icons.videocam_rounded, color: Color(0xFF9333EA)),
                  ),
                  title: const Text('Record Video', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Record up to 3 mins video clip'),
                  onTap: () => Navigator.pop(ctx, 'camera_video'),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFECFDF5),
                    child: Icon(Icons.video_library_rounded, color: Color(0xFF10B981)),
                  ),
                  title: const Text('Choose Video', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Select a video from gallery'),
                  onTap: () => Navigator.pop(ctx, 'gallery_video'),
                ),
              ],
              if (mode == MediaPickerMode.all || mode == MediaPickerMode.photoOnly) ...[
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFF1F5F9),
                    child: Icon(Icons.photo_library_rounded, color: Color(0xFF334155)),
                  ),
                  title: const Text('Gallery (Photos & Media)', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Select up to $remainingSlots photos/clips'),
                  onTap: () => Navigator.pop(ctx, 'gallery_media'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (choice == null) return [];

    final picker = ImagePicker();
    final List<File> selectedFiles = [];

    try {
      if (choice == 'camera_photo') {
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 2048,
          maxHeight: 2048,
        );
        if (picked != null) selectedFiles.add(File(picked.path));
      } else if (choice == 'camera_video') {
        final picked = await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(minutes: 3),
        );
        if (picked != null) selectedFiles.add(File(picked.path));
      } else if (choice == 'gallery_video') {
        final picked = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: maxVideoDuration,
        );
        if (picked != null) selectedFiles.add(File(picked.path));
      } else if (choice == 'gallery_media') {
        try {
          final pickedList = await picker.pickMultipleMedia(
            imageQuality: 85,
            maxWidth: 2048,
            maxHeight: 2048,
          );
          if (pickedList.isNotEmpty) {
            for (final x in pickedList) {
              if (selectedFiles.length < remainingSlots) {
                selectedFiles.add(File(x.path));
              }
            }
          }
        } catch (_) {
          final pickedList = await picker.pickMultiImage(
            imageQuality: 85,
            maxWidth: 2048,
            maxHeight: 2048,
          );
          if (pickedList.isNotEmpty) {
            for (final x in pickedList) {
              if (selectedFiles.length < remainingSlots) {
                selectedFiles.add(File(x.path));
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[MediaAttachmentPicker] Error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick media: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }

    return selectedFiles;
  }
}
