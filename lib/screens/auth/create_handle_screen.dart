import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/post_repository.dart';
import '../main/main_screen.dart';
import '../onboarding/permission_request_screen.dart';

class CreateHandleScreen extends StatefulWidget {
  final PostRepository repository;
  final User user;

  const CreateHandleScreen({
    super.key,
    required this.repository,
    required this.user,
  });

  @override
  State<CreateHandleScreen> createState() => _CreateHandleScreenState();
}

class _CreateHandleScreenState extends State<CreateHandleScreen> {
  final _handleController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Default handle based on email prefix
    if (widget.user.email != null) {
      final emailParts = widget.user.email!.split('@');
      if (emailParts.isNotEmpty) {
        _handleController.text = emailParts[0];
      }
    }
  }

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _createHandle() async {
    final handle = _handleController.text.trim();
    if (handle.isEmpty) {
      setState(() => _errorMessage = 'Username cannot be empty');
      return;
    }

    final RegExp handleRegex = RegExp(r'^[a-z0-9]{3,20}$');
    if (!handleRegex.hasMatch(handle)) {
      setState(() => _errorMessage = 'Username must be 3-20 characters (only lowercase letters & numbers)');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final handleRef = FirebaseFirestore.instance.collection('profiles').doc(handle);
      
      final isSuccess = await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(handleRef);
        if (doc.exists) {
          return false;
        }
        
        // Save to profiles collection (Public Data) atomically
        transaction.set(handleRef, {
          'handle': handle,
          'ownerUid': widget.user.uid,
          'friendCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        return true;
      });

      if (!isSuccess) {
        setState(() {
          _errorMessage = 'Username is already taken. Please choose another.';
          _isLoading = false;
        });
        return;
      }

      // Save to users collection (Private Data)
      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).set({
        'handle': handle,
        'email': widget.user.email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Save locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('is_logged_in', 'true');
      await prefs.setString('user_handle', handle);

      widget.repository.currentUserHandle = handle;

      if (!mounted) return;
      // First time user — show permission onboarding
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PermissionRequestScreen(
            onComplete: (permContext) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('perms_done', 'true');
              if (permContext.mounted) {
                Navigator.of(permContext).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => MainScreen(
                      repository: widget.repository,
                      currentUserHandle: handle,
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Create Username'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a username to identify yourself in the app.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _handleController,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'Username',
                labelStyle: const TextStyle(color: Colors.black54),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF243049)),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isLoading ? null : _createHandle,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Continue',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

