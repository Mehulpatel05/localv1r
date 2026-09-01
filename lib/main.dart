import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/post_repository.dart';
import 'screens/feed/feed_screen.dart';
import 'screens/auth/device_register_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const VadodaraLocalApp());
}

class VadodaraLocalApp extends StatelessWidget {
  const VadodaraLocalApp({super.key});

  // Check login status asynchronously using encrypted secure storage to route the user
  Future<Map<String, dynamic>> _checkAuthStatus() async {
    const secureStorage = FlutterSecureStorage();
    final isLoggedInStr = await secureStorage.read(key: 'is_logged_in');
    final handle = await secureStorage.read(key: 'user_handle') ?? 'Guest';
    return {
      'isLoggedIn': isLoggedInStr == 'true',
      'userHandle': handle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final postRepository = PostRepository();

    return MaterialApp(
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
            return const Scaffold(
              backgroundColor: Color(0xFF0B0F19),
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
              ),
            );
          }

          final data = snapshot.data;
          if (data != null && data['isLoggedIn'] == true) {
            final handle = data['userHandle'] as String;
            postRepository.currentUserHandle = handle;
            return FeedScreen(
              repository: postRepository,
              currentUserHandle: handle,
            );
          } else {
            return DeviceRegisterScreen(repository: postRepository);
          }
        },
      ),
    );
  }
}
