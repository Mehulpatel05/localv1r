import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized service to handle all runtime permission requests.
class AppPermissionService {
  /// Request all permissions that this app needs.
  static Future<Map<Permission, bool>> requestAllPermissions() async {
    final permissions = <Permission>[
      Permission.notification,
      Permission.photos,
      Permission.storage,
      Permission.locationWhenInUse,
      Permission.camera,
    ];

    final statuses = await permissions.request();
    return {
      for (final entry in statuses.entries) entry.key: entry.value.isGranted,
    };
  }

  /// Open system settings so user can manually grant permissions.
  static Future<void> openSettings() => openAppSettings();

  /// Quick single-permission check.
  static Future<bool> isGranted(Permission permission) async {
    return await permission.isGranted;
  }

  /// Human-readable label for each permission.
  static String labelFor(Permission permission) {
    if (permission == Permission.notification) return 'Notifications';
    if (permission == Permission.photos) return 'Photo Library';
    if (permission == Permission.storage) return 'Storage';
    if (permission == Permission.locationWhenInUse) return 'Location';
    if (permission == Permission.camera) return 'Camera';
    return permission.toString();
  }

  /// Icon for each permission.
  static IconData iconFor(Permission permission) {
    if (permission == Permission.notification) return Icons.notifications_rounded;
    if (permission == Permission.photos) return Icons.photo_library_rounded;
    if (permission == Permission.storage) return Icons.folder_rounded;
    if (permission == Permission.locationWhenInUse) return Icons.location_on_rounded;
    if (permission == Permission.camera) return Icons.camera_alt_rounded;
    return Icons.lock_rounded;
  }

  /// Description for each permission (shown to user).
  static String descriptionFor(Permission permission) {
    if (permission == Permission.notification) {
      return 'Required for new message alerts and local area notifications.';
    }
    if (permission == Permission.photos) {
      return 'Needed to attach photos from your gallery when creating a post.';
    }
    if (permission == Permission.storage) {
      return 'Needed to pick photos from storage when creating a post.';
    }
    if (permission == Permission.locationWhenInUse) {
      return 'Used to show posts from your local area in your local area.';
    }
    if (permission == Permission.camera) {
      return 'Allows you to take a photo directly and attach it to a post.';
    }
    return 'Required for the app to work correctly.';
  }
}
