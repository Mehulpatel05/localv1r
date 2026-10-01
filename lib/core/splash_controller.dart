import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/post_repository.dart';
import '../services/direct_chat_service.dart';
import '../services/notification_service.dart';

import '../services/chat_preferences_service.dart';
import '../services/friend_repository.dart';
import '../services/presence_service.dart';
import '../core/action_state/action_state_provider.dart';
import '../core/location/location_service.dart';
import '../core/widgets/user_avatar.dart';

class BootstrapResult {
  final bool isLoggedIn;
  final bool isNewUser;
  final String userId;
  final String userHandle;
  final String cityId;

  const BootstrapResult({
    required this.isLoggedIn,
    required this.isNewUser,
    required this.userId,
    required this.userHandle,
    required this.cityId,
  });
}

/// ⚡ Phase 2: Three-Stage Pre-Processing Pipeline Controller
///
/// Stage A — Cold Start:
///   Parallel execution of Auth verification, local cache reads (city, feed snapshot),
///   and server health check before splash even finishes.
///
/// Stage B — Token Resolve & Warm Fetch (0–300ms):
///   JWT decoded into TokenDecisionEngine in memory, triggering a non-blocking
///   background Warm Fetch for city feeds, unread summaries, and action states.
///
/// Stage C — Progressive Reveal:
///   Instant UI render from disk snapshot, smoothly revealing real network data
///   upon warm fetch completion.
class SplashController {
  static final SplashController _instance = SplashController._internal();
  factory SplashController() => _instance;
  static SplashController get instance => _instance;
  SplashController._internal();

  /// Stage A: Cold Start Pipeline (Executed concurrently at startup)
  Future<BootstrapResult> runColdStartPipeline({
    required LocationService locationService,
    required PostRepository postRepository,
  }) async {
    try {
      // 1. Parallel execution of Stage A tasks
      final results = await Future.wait([
        _resolveAuthSession(),
        locationService.ensureLocationPermissionAndAutoDetect(),
        AvatarCacheService.instance.ensureInitialized(),
        _pingServerHealth(),
      ]);

      final authData = results[0] as Map<String, dynamic>;
      final isLoggedIn = authData['isLoggedIn'] == true;
      final isNewUser = authData['isNewUser'] == true;
      final userId = authData['userId'] as String? ?? '';
      final userHandle = authData['handle'] as String? ?? 'Guest';
      final cityId = locationService.cityId.isNotEmpty ? locationService.cityId : 'surat_gujarat';

      // 2. Stage B: Token Resolve & Background Warm Fetch (Non-blocking)
      if (isLoggedIn && !isNewUser && userHandle != 'Guest') {
        warmFetchOnLogin(
          uid: userId,
          handle: userHandle,
          cityId: cityId,
          postRepo: postRepository,
        );
      }

      return BootstrapResult(
        isLoggedIn: isLoggedIn,
        isNewUser: isNewUser,
        userId: userId,
        userHandle: userHandle,
        cityId: cityId,
      );
    } catch (e) {
      debugPrint('[SplashController] Cold start error: $e');
      return const BootstrapResult(
        isLoggedIn: false,
        isNewUser: false,
        userId: '',
        userHandle: 'Guest',
        cityId: 'surat_gujarat',
      );
    }
  }

  /// 🚀 Stage B: Non-blocking Background Warm Fetch (Fire-and-forget on Login & Boot)
  void warmFetchOnLogin({
    required String uid,
    required String handle,
    required String cityId,
    required PostRepository postRepo,
  }) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty || cleanHandle == 'Guest') return;

    // Initialize presence heartbeat & status
    PresenceService.instance.init(cleanHandle);

    final List<Future<dynamic>> warmTasks = [
      // 1. Pre-warm city feeds (Jobs, Rooms, Shops, Food, Events)
      postRepo.prefetchCityFeed(cityId),

      // 2. Pre-warm direct chat conversations and unread badges (0ms Chat list)
      DirectChatService.instance.getChats(cleanHandle),
      DirectChatService.instance.prefetchUnreadSummary(cleanHandle),

      // 3. Pre-warm chat preferences (pinned, muted, archived, favourites)
      ChatPreferencesService.instance.loadPreferences(cleanHandle),

      // 4. Pre-warm friends list for immediate friend picker render
      FriendRepository().fetchFriends(),

      // 5. Pre-warm notification badge counts
      NotificationService.instance.prefetchBadgeCounts(cleanHandle),

      // 6. Pre-warm cloud profile & avatar metadata
      AuthService.instance.syncCloudProfile(),

      // 7. Pre-warm full precomputed user action document (likes, saves, votes)
      ActionStateProvider.instance.prefetchActionStateDocument(),
    ];

    unawaited(
      Future.wait(warmTasks).then((_) {
        // Pre-warm avatars in AvatarCacheService
        final cachedUrls = AvatarCacheService.instance.getAllCachedUrls();
        prewarmImages(cachedUrls);
      }).catchError((e) {
        debugPrint('[SplashController] Warm fetch background warning: $e');
      }),
    );
  }

  /// Pre-warms image URLs directly into Flutter's GPU/RAM ImageCache for instant 0ms visual rendering
  static void prewarmImage(String? url) {
    if (url == null || url.trim().isEmpty || !url.startsWith('http')) return;
    try {
      final provider = NetworkImage(url.trim());
      provider.resolve(ImageConfiguration.empty);
    } catch (_) {}
  }

  /// Pre-warms a list of image URLs in the background
  static void prewarmImages(List<String?> urls) {
    for (final u in urls) {
      prewarmImage(u);
    }
  }

  Future<Map<String, dynamic>> _resolveAuthSession() async {
    try {
      final token = await AuthService.instance.getAccessToken();
      final handle = await AuthService.instance.getUserHandle();
      final uid = await AuthService.instance.getUserId();

      // Token + handle present = user is logged in.
      // NOTE: Our tokens are plain secure random hex strings (not JWTs),
      // so JWT-based isExpired check is meaningless here — the server-side
      // auth middleware validates every request against D1. Trust the stored
      // token and let the server reject it if truly invalid.
      if (token != null && token.isNotEmpty && handle != null && handle.isNotEmpty) {
        final isNewUser = AuthService.isNewUserHandle(handle);
        return {
          'isLoggedIn': true,
          'isNewUser': isNewUser,
          'userId': uid ?? '',
          'handle': handle,
        };
      }

      return {'isLoggedIn': false, 'isNewUser': false, 'userId': '', 'handle': 'Guest'};
    } catch (e) {
      debugPrint('[SplashController] Auth resolution error: $e');
      return {'isLoggedIn': false, 'isNewUser': false, 'userId': '', 'handle': 'Guest'};
    }
  }


  Future<void> _pingServerHealth() async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/health');
      // Render free tier sleeps after 15 min — ping with 30s timeout to wake it up
      // before the user attempts login, so OTP send doesn't timeout
      await http.get(uri).timeout(const Duration(seconds: 30));
    } catch (_) {
      // Non-blocking ping
    }
  }
}
