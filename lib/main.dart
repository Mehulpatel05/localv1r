import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'firebase_options.dart';
import 'services/post_repository.dart';
import 'services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/main/main_screen.dart';
import 'services/auth_service.dart';
import 'core/location/location_service.dart';
import 'services/presence_service.dart';
import 'core/theme.dart';
import 'core/auth_repository.dart';
import 'features/auth/login_flow_page.dart';
import 'features/auth/widgets/animated_splash_screen.dart';
import 'services/call_listener_service.dart';
import 'core/splash_controller.dart';
import 'core/action_state/action_state_provider.dart';
import 'services/user_action_state_service.dart';
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
  
  // Optimize Flutter Image Cache for instant 0ms media renders
  PaintingBinding.instance.imageCache.maximumSize = 2500;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 120 * 1024 * 1024; // 120 MB

  // Non-blocking asynchronous service setup (does not delay runApp)
  _initNonCriticalServices();

  runApp(const VadodaraLocalApp());
}

void _initNonCriticalServices() {
  // Register background message handler for push notifications
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
  StreamSubscription<AuthEvent>? _authSub;

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
    _authSub = AuthService.instance.authEvents.listen(_handleAuthEvent);
    _bootstrapApp();
  }

  void _handleAuthEvent(AuthEvent event) {
    if (event == AuthEvent.signedOut || event == AuthEvent.forceSignedOut) {
      postRepository.clearCache();
      if (mounted) {
        setState(() {
          _isLoggedIn = false;
          _userHandle = 'Guest';
        });
      }
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      if (event == AuthEvent.forceSignedOut) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('Session expired or revoked. Please sign in again.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    locationService.dispose();
    postRepository.dispose();
    super.dispose();
  }

  /// ⚡ Phase 2: Three-Stage Pre-Processing Pipeline Bootstrap
  Future<void> _bootstrapApp() async {
    try {
      final result = await SplashController.instance.runColdStartPipeline(
        locationService: locationService,
        postRepository: postRepository,
      );

      if (result.isLoggedIn && !result.isNewUser) {
        postRepository.currentUserHandle = result.userHandle;
        _isLoggedIn = true;
        _userHandle = result.userHandle;

        // Background non-critical service setup
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationService().initialize();
          NotificationService().startListening(result.userHandle);
          PresenceService.instance.init(result.userHandle);
          // Call system hidden for now
          // CallListenerService.instance.startListening(result.userHandle);
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

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: locationService),
        ChangeNotifierProvider.value(value: ActionStateProvider.instance),
        ChangeNotifierProvider.value(value: UserActionStateService.instance),
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
                      postRepository: postRepository,
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

                            if (mounted) {
                              setState(() {
                                _isLoggedIn = true;
                                _userHandle = handle;
                              });
                            }

                            NotificationService().initialize();
                            PresenceService.instance.init(handle);
                            CallListenerService.instance.startListening(handle);

                            // ⚡ Instant Background Cache Preloading (non-blocking)
                            unawaited(
                              SplashController.instance.warmFetchOnLogin(
                                uid: userId,
                                handle: handle,
                                cityId: locationService.cityId.isNotEmpty ? locationService.cityId : 'surat_gujarat',
                                postRepo: postRepository,
                              ),
                            );
                          }
                        } catch (e, stack) {
                          debugPrint('[MainFlow] ERROR in onLoggedIn: $e\n$stack');
                        }
                      },
                    ),
        ),
      ),
    );
  }
}

