import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/api_constants.dart';

enum AppAssetType {
  splash,
  homeFeedHeader,
  profileHeader,
  profileBodyBackground,
}

class AppAssetDescriptor {
  final AppAssetType type;
  final String remoteKey;
  final String cachedFilename;
  final String fallbackAsset;
  final String etagKey;

  const AppAssetDescriptor({
    required this.type,
    required this.remoteKey,
    required this.cachedFilename,
    required this.fallbackAsset,
    required this.etagKey,
  });
}

class AppAssetService {
  AppAssetService._();
  static final AppAssetService instance = AppAssetService._();

  static const List<AppAssetDescriptor> _descriptors = [
    AppAssetDescriptor(
      type: AppAssetType.splash,
      remoteKey: 'static/nearhood_splash_background.webp',
      cachedFilename: 'cached_splash_background.webp',
      fallbackAsset: 'assets/images/nearhood_splash_background.webp',
      etagKey: 'nearhood_splash_etag',
    ),
    AppAssetDescriptor(
      type: AppAssetType.homeFeedHeader,
      remoteKey: 'static/nearhood_home_feed_header.webp',
      cachedFilename: 'cached_home_feed_header.webp',
      fallbackAsset: 'assets/images/nearhood_home_feed_header.webp',
      etagKey: 'nearhood_home_feed_header_etag',
    ),
    AppAssetDescriptor(
      type: AppAssetType.profileHeader,
      remoteKey: 'static/nearhood_profile_city_header.webp',
      cachedFilename: 'cached_profile_city_header.webp',
      fallbackAsset: 'assets/images/nearhood_profile_city_header.webp',
      etagKey: 'nearhood_profile_city_header_etag',
    ),
    AppAssetDescriptor(
      type: AppAssetType.profileBodyBackground,
      remoteKey: 'static/nearhood_profile_body_background.webp',
      cachedFilename: 'cached_profile_body_background.webp',
      fallbackAsset: 'assets/images/nearhood_profile_body_background.webp',
      etagKey: 'nearhood_profile_body_background_etag',
    ),
  ];

  final Map<AppAssetType, File> _cachedFiles = {};
  final ValueNotifier<int> revisionNotifier = ValueNotifier<int>(0);
  bool _isSyncing = false;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final desc in _descriptors) {
        final file = File('${dir.path}/${desc.cachedFilename}');
        if (await file.exists() && await file.length() > 500) {
          _cachedFiles[desc.type] = file;
        }
      }
      _isInitialized = true;
      revisionNotifier.value++;
    } catch (_) {}
  }

  ImageProvider getImageProvider(AppAssetType type) {
    final cached = _cachedFiles[type];
    if (cached != null && cached.existsSync() && cached.lengthSync() > 500) {
      return FileImage(cached);
    }
    final desc = _descriptors.firstWhere((d) => d.type == type);
    return AssetImage(desc.fallbackAsset);
  }

  ImageProvider getSplashImageProvider() => getImageProvider(AppAssetType.splash);
  ImageProvider getHomeFeedHeaderProvider() => getImageProvider(AppAssetType.homeFeedHeader);
  ImageProvider getProfileHeaderProvider() => getImageProvider(AppAssetType.profileHeader);
  ImageProvider getProfileBodyBackgroundProvider() => getImageProvider(AppAssetType.profileBodyBackground);

  Future<void> syncAllFromServer() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final prefs = await SharedPreferences.getInstance();

      for (final desc in _descriptors) {
        await _syncSingleAsset(desc, dir, prefs);
      }
    } catch (_) {
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncSingleAsset(
    AppAssetDescriptor desc,
    Directory dir,
    SharedPreferences prefs,
  ) async {
    try {
      final targetFile = File('${dir.path}/${desc.cachedFilename}');
      final tempFile = File('${dir.path}/${desc.cachedFilename}.tmp');
      final currentEtag = prefs.getString(desc.etagKey);

      final uri = Uri.parse('${ApiConstants.rootUrl}/api/v2/media/file/${desc.remoteKey}');
      final headers = <String, String>{
        'Accept': 'image/webp,image/*,*/*',
      };
      if (currentEtag != null && currentEtag.isNotEmpty && targetFile.existsSync()) {
        headers['If-None-Match'] = currentEtag;
      }

      final response = await http.get(uri, headers: headers).timeout(
        const Duration(milliseconds: 4000),
      );

      if (response.statusCode == 304) {
        if (targetFile.existsSync() && targetFile.lengthSync() > 500) {
          _cachedFiles[desc.type] = targetFile;
        }
        return;
      }

      if (response.statusCode == 200 && response.bodyBytes.length > 500) {
        await tempFile.writeAsBytes(response.bodyBytes, flush: true);
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.rename(targetFile.path);

        final newEtag = response.headers['etag'] ?? response.headers['ETag'];
        if (newEtag != null && newEtag.isNotEmpty) {
          await prefs.setString(desc.etagKey, newEtag);
        }

        _cachedFiles[desc.type] = targetFile;
        revisionNotifier.value++;
      }
    } catch (_) {}
  }
}
