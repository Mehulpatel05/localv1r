import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/presence_service.dart';

/// Multi-tier high-performance Avatar Cache Service
/// - In-memory synchronous 0ms lookups
/// - Persistent disk caching via SharedPreferences
/// - Seamless background cloud synchronization
class AvatarCacheService extends ChangeNotifier {
  static final AvatarCacheService _instance = AvatarCacheService._internal();
  factory AvatarCacheService() => _instance;
  static AvatarCacheService get instance => _instance;

  AvatarCacheService._internal() {
    _initPersistence();
  }

  static const String baseUrl = 'https://localv1r.onrender.com/api/v1';

  final Map<String, String?> _cache = {};
  final Set<String> _inFlightFetches = {};
  SharedPreferences? _prefs;
  bool _initialized = false;

  /// Loads locally stored avatars into memory on app launch
  Future<void> _initPersistence() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;

      // 1. Preload own photo URL if available
      final myPhoto = _prefs?.getString('user_photo_url') ?? _prefs?.getString('profile_photo_url');
      final myHandle = _prefs?.getString('user_handle');
      if (myHandle != null && myHandle.isNotEmpty && myPhoto != null && myPhoto.isNotEmpty) {
        final clean = myHandle.replaceAll('@', '').trim().toLowerCase();
        _cache[clean] = myPhoto;
      }

      // 2. Preload all cached avatar keys
      final keys = _prefs?.getKeys() ?? {};
      for (final k in keys) {
        if (k.startsWith('avatar_cache_')) {
          final handle = k.substring('avatar_cache_'.length);
          final url = _prefs?.getString(k);
          if (handle.isNotEmpty && url != null && url.isNotEmpty) {
            _cache[handle.toLowerCase()] = url;
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[AvatarCacheService] Error initializing persistent cache: $e');
    }
  }

  /// Ensure persistent cache is ready
  Future<void> ensureInitialized() async {
    if (!_initialized) {
      await _initPersistence();
    }
  }

  /// Retrieves cached avatar URL synchronously if present in memory, else null
  String? getCachedUrl(String handle) {
    final clean = handle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return null;
    return _cache[clean];
  }

  /// Sets or updates the cached avatar URL for a handle, persists to disk, and notifies listeners
  void setCachedUrl(String handle, String? photoUrl, {bool persist = true}) {
    final clean = handle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return;
    final val = (photoUrl != null && photoUrl.trim().isNotEmpty) ? photoUrl.trim() : null;
    
    if (_cache[clean] != val) {
      _cache[clean] = val;
      notifyListeners();
    }

    if (persist) {
      _persistHandleUrl(clean, val);
    }
  }

  Future<void> _persistHandleUrl(String cleanHandle, String? url) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final key = 'avatar_cache_$cleanHandle';
      if (url != null && url.isNotEmpty) {
        await _prefs?.setString(key, url);
      } else {
        await _prefs?.remove(key);
      }
    } catch (_) {}
  }

  /// Bulk prime cache (e.g. from feed posts or friend lists)
  void primeCache(Map<String, String?> entries) {
    bool hasChanged = false;
    entries.forEach((handle, url) {
      final clean = handle.replaceAll('@', '').trim().toLowerCase();
      if (clean.isNotEmpty) {
        final val = (url != null && url.trim().isNotEmpty) ? url.trim() : null;
        if (_cache[clean] != val) {
          _cache[clean] = val;
          hasChanged = true;
          if (val != null) {
            _persistHandleUrl(clean, val);
          }
        }
      }
    });
    if (hasChanged) {
      notifyListeners();
    }
  }

  /// Fetches avatar URL from Backend D1 `profiles/{handle}` if not already cached
  Future<String?> fetchAvatarUrl(String handle, {bool forceRefresh = false}) async {
    final clean = handle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return null;

    if (!forceRefresh && _cache.containsKey(clean) && _cache[clean] != null) {
      return _cache[clean];
    }

    if (_inFlightFetches.contains(clean)) {
      int wait = 0;
      while (_inFlightFetches.contains(clean) && wait < 15) {
        await Future.delayed(const Duration(milliseconds: 100));
        wait++;
      }
      return _cache[clean];
    }

    _inFlightFetches.add(clean);

    try {
      final uri = Uri.parse('$baseUrl/auth/profile/${Uri.encodeComponent(clean)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final user = data['user'] as Map<String, dynamic>?;
        final photoUrl = (user?['avatarUrl'] as String?)?.trim();
        final validUrl = (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null;
        _cache[clean] = validUrl;
        _persistHandleUrl(clean, validUrl);
      } else if (res.statusCode == 404) {
        _cache[clean] = null;
      }
    } catch (e) {
      debugPrint('[AvatarCacheService] Error fetching avatar for @$clean: $e');
    } finally {
      _inFlightFetches.remove(clean);
      notifyListeners();
    }

    return _cache[clean];
  }

  /// Saves current user's photoUrl into SharedPreferences cache for instant cold starts
  Future<void> saveMyPhotoUrlLocally(String photoUrl) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString('user_photo_url', photoUrl);
      await _prefs?.setString('profile_photo_url', photoUrl);

      final myHandle = _prefs?.getString('user_handle');
      if (myHandle != null && myHandle.isNotEmpty) {
        setCachedUrl(myHandle, photoUrl);
      }
    } catch (_) {}
  }

  /// Loads current user's locally cached photoUrl
  Future<String?> getMyPhotoUrlLocally() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      return _prefs?.getString('user_photo_url') ?? _prefs?.getString('profile_photo_url');
    } catch (_) {
      return null;
    }
  }
}

/// Universal Instagram-Grade User Avatar Widget
/// - Perfect 1:1 circular fit with BoxFit.cover (never stretched or squashed)
/// - Instagram Story / Profile ring support with customizable gradient and white spacer
/// - Smooth loading placeholder with initials
/// - Deterministic branded fallback initial avatars
/// - Real-time reactive cache updates via AvatarCacheService
/// - Online status badge support
/// - Built-in full-screen HD photo popup dialog
class UserAvatar extends StatefulWidget {
  final String handle;
  final String? photoUrl;
  final double size;
  final bool showOnlineBadge;
  final bool? isOnline;
  final VoidCallback? onTap;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final double? fontSize;
  final double? badgeSize;

  // Instagram-style ring properties
  final bool showRing;
  final Gradient? ringGradient;
  final double ringWidth;
  final double ringGap;
  final Widget? editBadge;
  final bool enableFullViewOnTap;

  const UserAvatar({
    super.key,
    required this.handle,
    this.photoUrl,
    this.size = 40,
    this.showOnlineBadge = false,
    this.isOnline,
    this.onTap,
    this.border,
    this.boxShadow,
    this.fontSize,
    this.badgeSize,
    this.showRing = false,
    this.ringGradient,
    this.ringWidth = 2.5,
    this.ringGap = 2.5,
    this.editBadge,
    this.enableFullViewOnTap = false,
  });

  /// Instagram signature story gradient palette
  static const Gradient instagramGradient = LinearGradient(
    colors: [
      Color(0xFFFBAA47),
      Color(0xFFD91A46),
      Color(0xFFA60F93),
    ],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );

  /// Nearhood brand gradient palette
  static const Gradient brandGradient = LinearGradient(
    colors: [
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  State<UserAvatar> createState() => _UserAvatarState();

  /// Opens an Instagram-style full-screen HD avatar pop-up
  static void showFullAvatar(BuildContext context, {required String handle, required String? photoUrl}) {
    final clean = handle.replaceAll('@', '').trim();
    final url = (photoUrl != null && photoUrl.isNotEmpty)
        ? photoUrl
        : AvatarCacheService.instance.getCachedUrl(clean);

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: ClipOval(
                child: (url != null && url.isNotEmpty)
                    ? Image.network(
                        url,
                        cacheWidth: 480,
                        cacheHeight: 480,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: const Color(0xFF1E293B),
                            child: const Center(
                              child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => _buildFallbackInitial(clean, 240, 72),
                      )
                    : _buildFallbackInitial(clean, 240, 72),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '@$clean',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  static Widget _buildFallbackInitial(String clean, double size, double fontSize) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: _UserAvatarState._getGradientForHandle(clean),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          _UserAvatarState._getInitials(clean),
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}

class _UserAvatarState extends State<UserAvatar> {
  static const List<List<Color>> _avatarGradients = [
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // Blue
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // Purple
    [Color(0xFFEC4899), Color(0xFFBE185D)], // Pink
    [Color(0xFF10B981), Color(0xFF047857)], // Emerald
    [Color(0xFFF59E0B), Color(0xFFB45309)], // Amber
    [Color(0xFF06B6D4), Color(0xFF0E7490)], // Cyan
    [Color(0xFF6366F1), Color(0xFF4338CA)], // Indigo
    [Color(0xFF14B8A6), Color(0xFF0F766E)], // Teal
    [Color(0xFFF97316), Color(0xFFC2410C)], // Orange
  ];

  static List<Color> _getGradientForHandle(String handle) {
    if (handle.isEmpty) return _avatarGradients[0];
    int hash = 0;
    for (int i = 0; i < handle.length; i++) {
      hash = (hash << 5) - hash + handle.codeUnitAt(i);
      hash &= 0x7FFFFFFF;
    }
    return _avatarGradients[hash % _avatarGradients.length];
  }

  static String _getInitials(String handle) {
    if (handle.isEmpty) return 'U';
    final clean = handle.replaceAll('@', '').replaceAll('.', ' ').replaceAll('_', ' ').trim();
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (clean.length >= 2) {
      return clean.substring(0, 2).toUpperCase();
    }
    return clean.isNotEmpty ? clean[0].toUpperCase() : 'U';
  }

  @override
  void initState() {
    super.initState();
    _checkAndFetchAvatar();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handle != widget.handle || oldWidget.photoUrl != widget.photoUrl) {
      _checkAndFetchAvatar();
    }
  }

  void _checkAndFetchAvatar() {
    final clean = widget.handle.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.photoUrl != null && widget.photoUrl!.isNotEmpty) {
        AvatarCacheService.instance.setCachedUrl(clean, widget.photoUrl);
      } else {
        final cached = AvatarCacheService.instance.getCachedUrl(clean);
        if (cached == null) {
          AvatarCacheService.instance.fetchAvatarUrl(clean);
        }
      }
    });
  }

  Uint8List? _decodeBase64(String src) {
    try {
      String clean = src.trim();
      if (clean.contains(',')) {
        clean = clean.split(',').last;
      }
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }

  Widget _buildAvatarImage({
    required String? url,
    required String cleanHandle,
    required double imageSize,
    required double effectiveFontSize,
  }) {
    if (url != null && url.trim().isNotEmpty) {
      final trimmed = url.trim();

      // 1. Base64 support
      if (trimmed.startsWith('data:image/')) {
        final bytes = _decodeBase64(trimmed);
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            width: imageSize,
            height: imageSize,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) => _buildInitialsPlaceholder(cleanHandle, imageSize, effectiveFontSize),
          );
        }
      }

      // 2. Local File path support (instant 0ms render before/during upload)
      if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
        try {
          final localFile = File(trimmed.replaceFirst('file://', ''));
          if (localFile.existsSync()) {
            return Image.file(
              localFile,
              width: imageSize,
              height: imageSize,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) => _buildInitialsPlaceholder(cleanHandle, imageSize, effectiveFontSize),
            );
          }
        } catch (_) {}
      }

      // 3. Network URL with Instagram-grade 1:1 square decode cache
      final cacheDimension = (imageSize * 2.5).round().clamp(72, 360);

      return Image.network(
        trimmed,
        width: imageSize,
        height: imageSize,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        cacheWidth: cacheDimension,
        cacheHeight: cacheDimension,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _buildInitialsPlaceholder(cleanHandle, imageSize, effectiveFontSize);
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildInitialsPlaceholder(cleanHandle, imageSize, effectiveFontSize);
        },
      );
    }

    return _buildInitialsPlaceholder(cleanHandle, imageSize, effectiveFontSize);
  }

  Widget _buildInitialsPlaceholder(String cleanHandle, double size, double fontSize) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: _getGradientForHandle(cleanHandle),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          _getInitials(cleanHandle),
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanHandle = widget.handle.replaceAll('@', '').trim();
    final effectiveFontSize = widget.fontSize ?? (widget.size * 0.40).clamp(11.0, 32.0);
    final effectiveBadgeSize = widget.badgeSize ?? (widget.size * 0.28).clamp(9.0, 18.0);

    final Widget baseAvatar = ListenableBuilder(
      listenable: AvatarCacheService.instance,
      builder: (context, _) {
        String? resolvedUrl = widget.photoUrl;
        if (resolvedUrl == null || resolvedUrl.trim().isEmpty) {
          resolvedUrl = AvatarCacheService.instance.getCachedUrl(cleanHandle);
        }

        // Compute inner image size when ring is applied
        final double ringOffset = widget.showRing ? ((widget.ringWidth + widget.ringGap) * 2) : 0;
        final double innerSize = (widget.size - ringOffset).clamp(16.0, widget.size);

        Widget innerCircle = Container(
          width: innerSize,
          height: innerSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: widget.border,
            boxShadow: widget.showRing ? null : widget.boxShadow,
          ),
          child: ClipOval(
            child: _buildAvatarImage(
              url: resolvedUrl,
              cleanHandle: cleanHandle,
              imageSize: innerSize,
              effectiveFontSize: effectiveFontSize,
            ),
          ),
        );

        if (widget.showRing) {
          final gradient = widget.ringGradient ?? UserAvatar.instagramGradient;
          return Container(
            width: widget.size,
            height: widget.size,
            padding: EdgeInsets.all(widget.ringWidth),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              boxShadow: widget.boxShadow ?? [
                BoxShadow(
                  color: const Color(0xFFD91A46).withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Container(
              padding: EdgeInsets.all(widget.ringGap),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: innerCircle,
            ),
          );
        }

        return innerCircle;
      },
    );

    Widget avatarCore;

    // Online Status Badge
    if (widget.showOnlineBadge && cleanHandle.isNotEmpty) {
      if (widget.isOnline != null) {
        avatarCore = Stack(
          clipBehavior: Clip.none,
          children: [
            baseAvatar,
            if (widget.isOnline == true)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: effectiveBadgeSize,
                  height: effectiveBadgeSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: widget.size >= 44 ? 2.5 : 1.8,
                    ),
                  ),
                ),
              ),
          ],
        );
      } else {
        avatarCore = StreamBuilder<UserPresence>(
          stream: PresenceService.instance.getPresenceStream(cleanHandle),
          initialData: PresenceService.instance.getCachedPresence(cleanHandle),
          builder: (context, snapshot) {
            final isOnline = snapshot.data?.isOnline == true;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                baseAvatar,
                if (isOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: effectiveBadgeSize,
                      height: effectiveBadgeSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: widget.size >= 44 ? 2.5 : 1.8,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      }
    } else {
      avatarCore = baseAvatar;
    }

    // Edit Badge (e.g. Camera / Plus badge on profile screen)
    if (widget.editBadge != null) {
      avatarCore = Stack(
        clipBehavior: Clip.none,
        children: [
          avatarCore,
          Positioned(
            bottom: 0,
            right: 0,
            child: widget.editBadge!,
          ),
        ],
      );
    }

    final VoidCallback? effectiveTap = widget.onTap ??
        (widget.enableFullViewOnTap
            ? () {
                final clean = widget.handle.replaceAll('@', '').trim();
                final cached = AvatarCacheService.instance.getCachedUrl(clean);
                UserAvatar.showFullAvatar(context, handle: clean, photoUrl: widget.photoUrl ?? cached);
              }
            : null);

    if (effectiveTap != null) {
      return GestureDetector(
        onTap: effectiveTap,
        behavior: HitTestBehavior.opaque,
        child: avatarCore,
      );
    }

    return avatarCore;
  }
}
