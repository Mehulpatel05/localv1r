import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_colors.dart';

enum MediaPickerMode {
  all,
  photoOnly,
  videoOnly,
}

class MediaAttachmentPicker {
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

    final sheetBg = AppColors.surface;
    final textColor = AppColors.textPrimary;
    final subtextColor = AppColors.textMuted;
    final handleColor = AppColors.divider;

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: sheetBg,
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
                  color: handleColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Attach Media',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 22),
                ),
                title: Text(
                  'Camera',
                  style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
                ),
                subtitle: Text(
                  'Take a photo with camera',
                  style: TextStyle(color: subtextColor, fontSize: 13),
                ),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF5FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF9333EA), size: 22),
                ),
                title: Text(
                  'Gallery',
                  style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
                ),
                subtitle: Text(
                  remainingSlots > 1
                      ? 'Choose photos & videos (up to $remainingSlots)'
                      : 'Choose a photo or video from gallery',
                  style: TextStyle(color: subtextColor, fontSize: 13),
                ),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
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
      if (choice == 'camera') {
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 80,
          maxWidth: 1080,
          maxHeight: 1080,
        );
        if (picked != null) selectedFiles.add(File(picked.path));
      } else if (choice == 'gallery') {
        try {
          if (mode == MediaPickerMode.photoOnly) {
            final pickedList = await picker.pickMultiImage(
              imageQuality: 80,
              maxWidth: 1080,
              maxHeight: 1080,
            );
            if (pickedList.isNotEmpty) {
              for (final x in pickedList) {
                if (selectedFiles.length < remainingSlots) {
                  selectedFiles.add(File(x.path));
                }
              }
            }
          } else if (mode == MediaPickerMode.videoOnly) {
            final picked = await picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: maxVideoDuration,
            );
            if (picked != null) selectedFiles.add(File(picked.path));
          } else {
            final pickedList = await picker.pickMultipleMedia(
              imageQuality: 80,
              maxWidth: 1080,
              maxHeight: 1080,
            );
            if (pickedList.isNotEmpty) {
              for (final x in pickedList) {
                if (selectedFiles.length < remainingSlots) {
                  selectedFiles.add(File(x.path));
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[MediaAttachmentPicker] pickMultipleMedia fallback: $e');
          try {
            final pickedList = await picker.pickMultiImage(
              imageQuality: 80,
              maxWidth: 1080,
              maxHeight: 1080,
            );
            if (pickedList.isNotEmpty) {
              for (final x in pickedList) {
                if (selectedFiles.length < remainingSlots) {
                  selectedFiles.add(File(x.path));
                }
              }
            }
          } catch (_) {
            final picked = await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 88,
              maxWidth: 1440,
              maxHeight: 1440,
            );
            if (picked != null) selectedFiles.add(File(picked.path));
          }
        }
      }
    } catch (e) {
      debugPrint('[MediaAttachmentPicker] Error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick media: $e'), backgroundColor: AppColors.error),
        );
      }
    }

    return selectedFiles;
  }
}
