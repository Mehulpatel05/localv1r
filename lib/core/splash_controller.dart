import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/post_repository.dart';
import '../services/direct_chat_service.dart';
import '../services/notification_service.dart';
import '../services/call_listener_service.dart';
import '../services/chat_preferences_service.dart';
import '../services/friend_repository.dart';
import '../services/presence_service.dart';
import '../core/action_state/action_state_provider.dart';
import '../core/location/location_service.dart';
import '../core/widgets/user_avatar.dart';
import '../services/founding_service.dart';

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
  bool isMainFlowVisible = false;

  Future<BootstrapResult> runColdStartPipeline({
    required LocationService locationService,
    required PostRepository postRepository,
  }) async {
    try {
      unawaited(_pingServerHealth());
      unawaited(FoundingService.instance.fetchCounts());

      final results = await Future.wait([
        _resolveAuthSession(),
        locationService.load(),
        AvatarCacheService.instance.ensureInitialized(),
      ]);

      final authData = results[0] as Map<String, dynamic>;
      final isLoggedIn = authData['isLoggedIn'] == true;
      final isNewUser = authData['isNewUser'] == true;
      final userId = authData['userId'] as String? ?? '';
      final userHandle = authData['handle'] as String? ?? 'Guest';
      final cityId = locationService.cityId.isNotEmpty ? locationService.cityId : 'GJ-VAD';

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
        cityId: 'GJ-VAD',
      );
    }
  }

  void warmFetchOnLogin({
    required String uid,
    required String handle,
    required String cityId,
    required PostRepository postRepo,
  }) {
    final cleanHandle = handle.replaceAll('@', '').trim();
    if (cleanHandle.isEmpty || cleanHandle == 'Guest') return;

    PresenceService.instance.init(cleanHandle);
    CallListenerService.instance.startListening(cleanHandle);

    unawaited(postRepo.prefetchCityFeed(cityId));
    unawaited(DirectChatService.instance.prefetchUnreadSummary(cleanHandle));

    Future.delayed(const Duration(milliseconds: 150), () {
      final List<Future<dynamic>> warmTasks = [
        DirectChatService.instance.getChats(cleanHandle),
        ChatPreferencesService.instance.loadPreferences(cleanHandle),
        FriendRepository().fetchFriends(),
        NotificationService.instance.prefetchBadgeCounts(cleanHandle),
        AuthService.instance.syncCloudProfile(),
        ActionStateProvider.instance.prefetchActionStateDocument(),
        FoundingService.instance.fetchCounts(),
      ];

      Future.wait(warmTasks).then((_) {
        final cachedUrls = AvatarCacheService.instance.getAllCachedUrls();
        prewarmImages(cachedUrls);
      }).catchError((e) {
        debugPrint('[SplashController] Warm fetch background warning: $e');
      });
    });
  }

  static void prewarmImage(String? url) {
    if (url == null || url.trim().isEmpty || !url.startsWith('http')) return;
    try {
      final provider = NetworkImage(url.trim());
      provider.resolve(ImageConfiguration.empty);
    } catch (_) {}
  }

  static void prewarmImages(List<String?> urls) {
    for (final u in urls) {
      prewarmImage(u);
    }
  }

  Future<Map<String, dynamic>> _resolveAuthSession() async {
    try {
      final resolveOperation = () async {
        final token = await AuthService.instance.getAccessToken();
        final handle = await AuthService.instance.getUserHandle();
        final uid = await AuthService.instance.getUserId();

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
      }();

      return await resolveOperation.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final prefToken = prefs.getString('auth_access_token') ?? prefs.getString('access_token');
            final prefHandle = prefs.getString('user_handle') ?? prefs.getString('current_user_handle');
            final prefUid = prefs.getString('user_id');

            if (prefToken != null && prefToken.isNotEmpty && prefHandle != null && prefHandle.isNotEmpty) {
              return {
                'isLoggedIn': true,
                'isNewUser': AuthService.isNewUserHandle(prefHandle),
                'userId': prefUid ?? '',
                'handle': prefHandle,
              };
            }
          } catch (_) {}
          return {'isLoggedIn': false, 'isNewUser': false, 'userId': '', 'handle': 'Guest'};
        },
      );
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
