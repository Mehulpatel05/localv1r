import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'firebase_options.dart';
import 'services/post_repository.dart';
import 'services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'screens/main/main_screen.dart';
import 'services/auth_service.dart';
import 'core/location/location_service.dart';
import 'services/presence_service.dart';
import 'core/theme.dart';
import 'core/auth_repository.dart';
import 'features/auth/login_flow_page.dart';
import 'features/auth/widgets/animated_splash_screen.dart';
import 'services/call_listener_service.dart';

import 'screens/auth/create_handle_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Fast parallel startup: orientation lock + Firebase core initialization
  await Future.wait([
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
    Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ),
  ]);
  
  // Non-blocking asynchronous service setup (does not delay runApp)
  _initNonCriticalServices();

  runApp(const VadodaraLocalApp());
}

void _initNonCriticalServices() {
  FirebaseAppCheck.instance.activate(
    // ignore: deprecated_member_use
    androidProvider: kReleaseMode 
        ? AndroidProvider.playIntegrity 
        : AndroidProvider.debug,
    // ignore: deprecated_member_use
    appleProvider: kReleaseMode 
        ? AppleProvider.deviceCheck 
        : AppleProvider.debug,
  ).catchError((e) {
    debugPrint('AppCheck initialization failed: $e');
  });

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}

class VadodaraLocalApp extends StatefulWidget {
  const VadodaraLocalApp({super.key});

  @override
  State<VadodaraLocalApp> createState() => _VadodaraLocalAppState();
}

class _VadodaraLocalAppState extends State<VadodaraLocalApp> {
  late final LocationService locationService;
  late final PostRepository postRepository;

  bool _isReady = false;
  bool _isSplashFinished = false;
  bool _isLoggedIn = false;
  String _userHandle = 'Guest';

  bool get _canShowMainFlow => _isReady && _isSplashFinished;

  @override
  void initState() {
    super.initState();
    locationService = LocationService();
    postRepository = PostRepository(locationService);
    _bootstrapApp();
  }

  @override
  void dispose() {
    locationService.dispose();
    postRepository.dispose();
    super.dispose();
  }

  /// High-performance parallel warmup:
  /// Pre-warms Auth, Location, and PostRepository concurrently in the background while Splash plays.
  Future<void> _bootstrapApp() async {
    try {
      // 1. Start parallel async initialization tasks
      final authFuture = _checkAuthStatus();
      final locationFuture = locationService.load();
      final results = await Future.wait([
        authFuture,
        locationFuture,
      ]);

      final authData = results[0] as Map<String, dynamic>;
      final isLoggedIn = authData['isLoggedIn'] == true;
      final handle = (authData['userHandle'] as String?) ?? 'Guest';
      final isNewUser = handle.isEmpty || handle == 'Guest' || handle.startsWith('Anon#');

      if (isLoggedIn && !isNewUser) {
        postRepository.currentUserHandle = handle;
        _isLoggedIn = true;
        _userHandle = handle;

        // Background non-critical service setup
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationService().initialize();
          NotificationService().startListening(handle);
          PresenceService.instance.init(handle);
          CallListenerService.instance.startListening(handle);
        });
      }

      _isReady = true;
      if (mounted && _isSplashFinished) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('[Bootstrap] Error during app startup: $e');
      _isReady = true;
      if (mounted && _isSplashFinished) {
        setState(() {});
      }
    }
  }

  // Check login status asynchronously using FlutterSecureStorage and SharedPreferences
  Future<Map<String, dynamic>> _checkAuthStatus() async {
    try {
      final isSecureLoggedIn = await AuthService.instance.isLoggedIn();
      final prefs = await SharedPreferences.getInstance();
      final isLoggedInStr = prefs.getString('is_logged_in');
      var handle = await AuthService.instance.getUserHandle() ?? prefs.getString('user_handle');

      if ((handle == null || handle.isEmpty || handle == 'Guest') && (isSecureLoggedIn || isLoggedInStr == 'true')) {
        final cloudProfile = await AuthService.instance.syncCloudProfile();
        handle = cloudProfile?['handle'] ?? handle;
      }

      return {
        'isLoggedIn': isSecureLoggedIn || isLoggedInStr == 'true',
        'userHandle': handle ?? 'Guest',
      };
    } catch (_) {
      return {'isLoggedIn': false, 'userHandle': 'Guest'};
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: locationService),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Nearhood',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: NearhoodTheme.lightTheme,
        darkTheme: NearhoodTheme.darkTheme,
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: !_canShowMainFlow
              ? AnimatedSplashScreen(
                  key: const ValueKey('splash_view'),
                  onAnimationComplete: () {
                    if (mounted) {
                      setState(() {
                        _isSplashFinished = true;
                      });
                    }
                  },
                )
              : _isLoggedIn
                  ? MainScreen(
                      key: const ValueKey('main_view'),
                      repository: postRepository,
                      currentUserHandle: _userHandle,
                    )
                  : LoginFlowPage(
                      key: const ValueKey('login_flow_view'),
                      authRepository: BackendAuthRepository(),
                      onLoggedIn: () async {
                        try {
                          debugPrint('[MainFlow] onLoggedIn callback triggered.');
                          final prefs = await SharedPreferences.getInstance();
                          final handle = prefs.getString('user_handle') ?? await AuthService.instance.getUserHandle() ?? '';
                          final userId = prefs.getString('user_id') ?? await AuthService.instance.getUserId() ?? '';
                          final phone = prefs.getString('phone_number') ?? await AuthService.instance.getPhoneNumber() ?? '';

                          final isNewUser = AuthService.isNewUserHandle(handle);
                          debugPrint('[MainFlow] Auth evaluation: userId=$userId, phone=$phone, handle="$handle", isNewUser=$isNewUser');

                          if (isNewUser) {
                            debugPrint('[MainFlow] Navigating new user to CreateHandleScreen...');
                            if (navigatorKey.currentState != null) {
                              await navigatorKey.currentState!.push(
                                MaterialPageRoute(
                                  builder: (_) => CreateHandleScreen(
                                    repository: postRepository,
                                    userId: userId,
                                    phoneNumber: phone,
                                  ),
                                ),
                              );
                            } else {
                              debugPrint('[MainFlow] WARNING: navigatorKey.currentState was null during navigation.');
                            }
                          } else {
                            debugPrint('[MainFlow] Existing user detected. Activating main session for $handle...');
                            postRepository.currentUserHandle = handle;
                            NotificationService().initialize();
                            PresenceService.instance.init(handle);
                            CallListenerService.instance.startListening(handle);
                            if (mounted) {
                              setState(() {
                                _isLoggedIn = true;
                                _userHandle = handle;
                              });
                            }
                          }
                        } catch (e, stack) {
                          debugPrint('[MainFlow] ERROR in onLoggedIn: $e\n$stack');
                          rethrow;
                        }
                      },
                    ),
        ),
      ),
    );
  }
}

