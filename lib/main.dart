import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/post_repository.dart';
import 'services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'screens/main/main_screen.dart';
import 'screens/auth/phone_login_screen.dart';
import 'services/auth_service.dart';
import 'core/location/location_service.dart';
import 'services/presence_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize Firebase App Check
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: const bool.fromEnvironment('dart.vm.product') 
          ? AndroidProvider.playIntegrity 
          : AndroidProvider.debug,
    );
  } catch (e) {
    debugPrint('AppCheck initialization failed: $e');
  }
  
  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const VadodaraLocalApp());
}

class VadodaraLocalApp extends StatefulWidget {
  const VadodaraLocalApp({super.key});

  @override
  State<VadodaraLocalApp> createState() => _VadodaraLocalAppState();
}

class _VadodaraLocalAppState extends State<VadodaraLocalApp> {
  late final LocationService locationService;
  late final PostRepository postRepository;

  @override
  void initState() {
    super.initState();
    locationService = LocationService();
    postRepository = PostRepository(locationService);
    locationService.load();
  }

  @override
  void dispose() {
    locationService.dispose();
    postRepository.dispose();
    super.dispose();
  }

  // Check login status asynchronously using FlutterSecureStorage and SharedPreferences
  Future<Map<String, dynamic>> _checkAuthStatus() async {
    // Enforce a minimum delay so the Splash Screen is visible for branding
    await Future.delayed(const Duration(milliseconds: 1500));
    
    final isSecureLoggedIn = await AuthService.instance.isLoggedIn();
    final prefs = await SharedPreferences.getInstance();
    final isLoggedInStr = prefs.getString('is_logged_in');
    final handle = await AuthService.instance.getUserHandle() ?? prefs.getString('user_handle') ?? 'Guest';
    
    return {
      'isLoggedIn': isSecureLoggedIn || isLoggedInStr == 'true',
      'userHandle': handle,
    };
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
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        primaryColor: const Color(0xFF3B82F6),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF60A5FA),
          surface: Colors.white,
          error: Colors.red,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 1,
          iconTheme: IconThemeData(color: Colors.black87),
          titleTextStyle: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        useMaterial3: true,
      ),
      home: FutureBuilder<Map<String, dynamic>>(
        future: _checkAuthStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/nearhood_logo.png',
                      width: 220,
                      height: 180,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 36),
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        color: Color(0xFF1A6B5F),
                        strokeWidth: 3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data;
          if (data != null && data['isLoggedIn'] == true) {
            final handle = data['userHandle'] as String;
            postRepository.currentUserHandle = handle;
            // Initialize push notifications and presence after login
            NotificationService().initialize();
            PresenceService.instance.init(handle);
            return MainScreen(
              repository: postRepository,
              currentUserHandle: handle,
            );
          } else {
            return PhoneLoginScreen(repository: postRepository);
          }
        },
      ),
    ),
    );
  }
}

