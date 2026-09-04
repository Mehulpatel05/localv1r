import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/post_repository.dart';
import 'services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'screens/main/main_screen.dart';
import 'screens/auth/google_login_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize Firebase App Check
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
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
  late final PostRepository postRepository;

  @override
  void initState() {
    super.initState();
    postRepository = PostRepository();
  }

  @override
  void dispose() {
    postRepository.dispose();
    super.dispose();
  }

  // Check login status asynchronously using SharedPreferences (faster than SecureStorage) to route the user
  Future<Map<String, dynamic>> _checkAuthStatus() async {
    // Enforce a minimum delay so the Splash Screen is visible for branding
    await Future.delayed(const Duration(milliseconds: 1500));
    
    final prefs = await SharedPreferences.getInstance();
    final isLoggedInStr = prefs.getString('is_logged_in');
    final handle = prefs.getString('user_handle') ?? 'Guest';
    return {
      'isLoggedIn': isLoggedInStr == 'true',
      'userHandle': handle,
    };
  }

  @override
  Widget build(BuildContext context) {

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Vadodara Local',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        primaryColor: const Color(0xFF3B82F6),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF60A5FA),
          surface: Color(0xFF151D30),
          error: Color(0xFFEF4444),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF151D30),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        useMaterial3: true,
      ),
      home: FutureBuilder<Map<String, dynamic>>(
        future: _checkAuthStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: const Color(0xFF0B0F19),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_city, size: 90, color: Color(0xFF3B82F6)),
                    const SizedBox(height: 24),
                    const Text(
                      'VADODARA LOCAL',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Explore • Connect • Thrive',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white60,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 48),
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: Color(0xFF3B82F6),
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
            // Initialize push notifications after login
            NotificationService().initialize();
            return MainScreen(
              repository: postRepository,
              currentUserHandle: handle,
            );
          } else {
            return GoogleLoginScreen(repository: postRepository);
          }
        },
      ),
    );
  }
}

