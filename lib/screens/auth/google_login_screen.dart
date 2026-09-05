import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/post_repository.dart';
import '../main/main_screen.dart';
import '../onboarding/permission_request_screen.dart';
import 'create_handle_screen.dart';

class GoogleLoginScreen extends StatefulWidget {
  final PostRepository repository;

  const GoogleLoginScreen({super.key, required this.repository});

  @override
  State<GoogleLoginScreen> createState() => _GoogleLoginScreenState();
}

class _GoogleLoginScreenState extends State<GoogleLoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // User canceled the sign-in
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // Check if user has already created a handle
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data()!.containsKey('handle')) {
          final handle = doc.data()!['handle'] as String;
          
          // Store locally
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('is_logged_in', 'true');
          await prefs.setString('user_handle', handle);
          
          widget.repository.currentUserHandle = handle;
          
          if (!mounted) return;
          // Check if permissions already granted (returning user)
          final permsDone = prefs.getString('perms_done');
          if (!mounted) return;
          if (permsDone == 'true') {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => MainScreen(
                repository: widget.repository,
                currentUserHandle: handle,
              )),
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => PermissionRequestScreen(
                  onComplete: (permContext) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('perms_done', 'true');
                    if (permContext.mounted) {
                      Navigator.of(permContext).pushReplacement(
                        MaterialPageRoute(builder: (_) => MainScreen(
                          repository: widget.repository,
                          currentUserHandle: handle,
                        )),
                      );
                    }
                  },
                ),
              ),
            );
          }
        } else {
          // First time, navigate to Create Handle Screen
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => CreateHandleScreen(
              repository: widget.repository,
              user: user,
            )),
          );
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_city, size: 80, color: Color(0xFF3B82F6)),
              const SizedBox(height: 24),
              const Text(
                'Vadodara Local',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sign in to explore and connect with your city.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 48),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isLoading 
                      ? const SizedBox(
                          width: 20, 
                          height: 20, 
                          child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 2)
                        )
                      : const Icon(Icons.g_mobiledata, size: 36, color: Colors.blue),
                  label: Text(
                    _isLoading ? 'Signing In...' : 'Sign in with Google',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  onPressed: _isLoading ? null : _signInWithGoogle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

