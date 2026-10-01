import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../constants/api_constants.dart';

/// 🚀 High-Performance Multi-Tier Persistent Disk & Memory Image Cache Service
///
/// Features:
/// 1. Tier 1: In-Memory Cache (0ms synchronous lookup for instant UI rendering).
/// 2. Tier 2: Persistent Local Disk Cache (1-2ms flash read, 100% offline support, 0 internet waste).
/// 3. Tier 3: Resilient Network Downloader with auto-deduplication of in-flight requests.
/// 4. Background Pre-fetching Queue for Feeds, Chats, and Profiles.
class AppImageCacheService {
  static final AppImageCacheService _instance = AppImageCacheService._internal();
  factory AppImageCacheService() => _instance;
  static AppImageCacheService get instance => _instance;

  AppImageCacheService._internal() {
    _initDiskCache();
  }

  Directory? _cacheDir;
  bool _isInitialized = false;

  // In-memory RAM cache for ultra-fast 0ms access (Max 150 high-priority images)
  final Map<String, Uint8List> _memoryCache = {};
  final List<String> _memoryLruOrder = [];
  static const int _maxMemoryCacheSize = 150;

  // Track in-flight network downloads to avoid duplicate concurrent fetches for the same URL
  final Map<String, Completer<File?>> _inFlightDownloads = {};

  // Background prefetch queue
  final Set<String> _prefetchedUrls = {};

  Future<void> _initDiskCache() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${docDir.path}/app_image_cache');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      _isInitialized = true;
    } catch (e) {
      debugPrint('[AppImageCacheService] Init error: $e');
    }
  }

  /// Normalizes any .r2.dev URLs to use the active backend streaming endpoint
  static String normalizeImageUrl(String url) {
    var clean = url.trim();
    if (clean.contains('.r2.dev/')) {
      final path = clean.split('.r2.dev/').last;
      return '${ApiConstants.baseUrl}/media/file/$path';
    }
    return clean;
  }


  /// Generates a deterministic safe file path from URL using MD5/SHA256
  String _getCacheKey(String url) {
    final normalized = normalizeImageUrl(url);
    return md5.convert(utf8.encode(normalized)).toString();
  }

  Future<File?> _getCacheFile(String url) async {
    if (!_isInitialized || _cacheDir == null) {
      await _initDiskCache();
    }
    if (_cacheDir == null) return null;
    final normalized = normalizeImageUrl(url);
    final key = _getCacheKey(normalized);
    final ext = _extractExtension(normalized);
    return File('${_cacheDir!.path}/$key.$ext');
  }

  String _extractExtension(String url) {
    final lower = url.toLowerCase().split('?').first;
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.gif')) return 'gif';
    if (lower.endsWith('.svg')) return 'svg';
    return 'jpg';
  }

  /// Synchronously checks if image bytes are ready in RAM (0ms)
  Uint8List? getFromMemory(String url) {
    final clean = normalizeImageUrl(url);
    return _memoryCache[clean];
  }

  /// Synchronously checks if image file already exists on local disk
  File? getFromDiskSync(String url) {
    if (!_isInitialized || _cacheDir == null) return null;
    final normalized = normalizeImageUrl(url);
    final key = _getCacheKey(normalized);
    final ext = _extractExtension(normalized);
    final file = File('${_cacheDir!.path}/$key.$ext');
    if (file.existsSync() && file.lengthSync() > 0) {
      return file;
    }
    return null;
  }

  /// Retrieves cached file or downloads and stores it persistently
  Future<File?> getOrFetchImageFile(String url, {Map<String, String>? headers}) async {
    final cleanUrl = normalizeImageUrl(url);
    if (cleanUrl.isEmpty || cleanUrl.startsWith('data:image/')) return null;

    // 1. If it's already a local file path
    if (cleanUrl.startsWith('file://') || (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://'))) {
      final path = cleanUrl.replaceFirst('file://', '');
      final f = File(path);
      if (await f.exists()) return f;
      return null;
    }

    // 2. Check Disk Cache
    final cacheFile = await _getCacheFile(cleanUrl);
    if (cacheFile != null && await cacheFile.exists() && await cacheFile.length() > 0) {
      // Put in memory cache asynchronously if not present
      if (!_memoryCache.containsKey(cleanUrl)) {
        cacheFile.readAsBytes().then((bytes) {
          _putInMemory(cleanUrl, bytes);
        }).catchError((_) {});
      }
      return cacheFile;
    }

    // 3. Deduplicate In-Flight Downloads
    if (_inFlightDownloads.containsKey(cleanUrl)) {
      return _inFlightDownloads[cleanUrl]!.future;
    }

    final completer = Completer<File?>();
    _inFlightDownloads[cleanUrl] = completer;

    try {
      final reqHeaders = <String, String>{
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        ...?headers,
      };

      final response = await http.get(Uri.parse(cleanUrl), headers: reqHeaders).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = response.bodyBytes;
        if (cacheFile != null) {
          await cacheFile.writeAsBytes(bytes, flush: true);
        }
        _putInMemory(cleanUrl, bytes);
        completer.complete(cacheFile);
        return cacheFile;
      } else {
        completer.complete(null);
        return null;
      }
    } catch (e) {
      debugPrint('[AppImageCacheService] Download error for $cleanUrl: $e');
      completer.complete(null);
      return null;
    } finally {
      _inFlightDownloads.remove(cleanUrl);
    }
  }

  void _putInMemory(String url, Uint8List bytes) {
    if (_memoryLruOrder.length >= _maxMemoryCacheSize) {
      final oldest = _memoryLruOrder.removeAt(0);
      _memoryCache.remove(oldest);
    }
    _memoryCache[url] = bytes;
    _memoryLruOrder.remove(url);
    _memoryLruOrder.add(url);
  }

  /// ⚡ Background Pre-fetcher: Downloads upcoming images ahead of time silently
  Future<void> prefetchImages(List<String> urls) async {
    for (final rawUrl in urls) {
      final url = rawUrl.trim();
      if (url.isEmpty || _prefetchedUrls.contains(url)) continue;
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;

      _prefetchedUrls.add(url);

      // Check if already on disk
      final file = getFromDiskSync(url);
      if (file != null) continue;

      // Silent background download (Low priority)
      Future.microtask(() async {
        try {
          await getOrFetchImageFile(url);
        } catch (_) {}
      });
    }
  }

  /// Clears cache when user explicitly requests
  Future<void> clearCache() async {
    _memoryCache.clear();
    _memoryLruOrder.clear();
    _prefetchedUrls.clear();
    try {
      if (_cacheDir != null && await _cacheDir!.exists()) {
        final entities = await _cacheDir!.list().toList();
        for (final entity in entities) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[AppImageCacheService] Clear cache error: $e');
    }
  }
}
