import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/motion.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/presence_service.dart';
import '../../services/auth_service.dart';
import '../../services/telegram_storage_service.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/instagram_avatar_cropper.dart';
import '../main/main_screen.dart';
import '../onboarding/permission_request_screen.dart';
import 'phone_login_screen.dart';

enum UsernameState {
  empty,
  focused,
  checking,
  available,
  taken,
  invalid,
  reserved,
}

class CreateHandleScreen extends StatefulWidget {
  final PostRepository repository;
  final String userId;
  final String? phoneNumber;
  final User? user;

  const CreateHandleScreen({
    super.key,
    required this.repository,
    required this.userId,
    this.phoneNumber,
    this.user,
  });

  @override
  State<CreateHandleScreen> createState() => _CreateHandleScreenState();
}

class _CreateHandleScreenState extends State<CreateHandleScreen> {
  final TextEditingController _handleController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  UsernameState _state = UsernameState.empty;
  Timer? _debounceTimer;
  bool _isSubmitting = false;
  String? _customErrorMessage;
  File? _pickedProfileImage;

  Future<void> _showPhotoPickerSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Add Profile Picture',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF3B82F6), size: 22),
                ),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(color: Color(0xFFF5F3FF), shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF8B5CF6), size: 22),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_pickedProfileImage != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(color: Color(0xFFFEF2F2), shape: BoxShape.circle),
                    child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
                  ),
                  title: const Text('Remove Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFFEF4444))),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _pickedProfileImage = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (picked != null) {
        final rawFile = File(picked.path);

        if (!mounted) return;

        // Open Instagram Move and Scale interactive cropper
        final croppedFile = await InstagramAvatarCropper.cropImage(
          context,
          imageFile: rawFile,
        );

        if (croppedFile != null && mounted) {
          setState(() => _pickedProfileImage = croppedFile);
        }
      }
    } catch (e) {
      debugPrint('Error picking profile image: $e');
    }
  }

  // Cache previously checked handles to prevent unnecessary Firestore query abuse
  final Map<String, bool> _availabilityCache = {};

  // Security: Reserved keywords to prevent staff/system impersonation & routing collisions
  static const Set<String> _reservedUsernames = {
    'admin',
    'administrator',
    'root',
    'system',
    'sysadmin',
    'support',
    'nearhood',
    'official',
    'help',
    'info',
    'moderator',
    'mod',
    'security',
    'staff',
    'team',
    'null',
    'undefined',
    'api',
    'auth',
    'developer',
    'bot',
    'service',
    'vadodara',
    'government',
    'police',
  };

  @override
  void initState() {
    super.initState();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        if (_handleController.text.trim().isEmpty) {
          setState(() => _state = UsernameState.empty);
        }
      }
    });

    // Default handle suggestion based on email prefix if available
    if (widget.user?.email != null) {
      final emailParts = widget.user!.email!.split('@');
      if (emailParts.isNotEmpty) {
        final sanitized = emailParts[0]
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (sanitized.isNotEmpty) {
          _handleController.text = sanitized;
          _validateAndCheckAvailability(sanitized, immediate: true);
        }
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _handleController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    _debounceTimer?.cancel();
    final trimmed = value.trim().toLowerCase();

    if (trimmed.isEmpty) {
      setState(() {
        _state = UsernameState.empty;
        _customErrorMessage = null;
      });
      return;
    }

    // Security Check 1: Input Regex Sanitization (Only lowercase alphanumeric, 3-20 chars)
    final RegExp validRegex = RegExp(r'^[a-z0-9]{3,20}$');
    if (!validRegex.hasMatch(trimmed)) {
      setState(() {
        _state = UsernameState.invalid;
        _customErrorMessage =
            'Username must be 3–20 characters using lowercase letters and numbers.';
      });
      return;
    }

    // Security Check 2: Reserved Usernames
    if (_reservedUsernames.contains(trimmed)) {
      setState(() {
        _state = UsernameState.reserved;
        _customErrorMessage = 'This username is reserved and cannot be used.';
      });
      return;
    }

    // Security Check 3: Content Filtering (Prohibited / Harassment / Doxxing words)
    final filterViolation = ContentFilter.validateContent(trimmed);
    if (filterViolation != null) {
      setState(() {
        _state = UsernameState.invalid;
        _customErrorMessage = 'Username contains prohibited words or patterns.';
      });
      return;
    }

    // Check memory cache first
    if (_availabilityCache.containsKey(trimmed)) {
      setState(() {
        _state = _availabilityCache[trimmed]!
            ? UsernameState.available
            : UsernameState.taken;
        _customErrorMessage = null;
      });
      return;
    }

    // Format is valid, start checking state & debouncing firestore call (450ms)
    setState(() {
      _state = UsernameState.checking;
      _customErrorMessage = null;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      _checkAvailability(trimmed);
    });
  }

  void _validateAndCheckAvailability(String handle, {bool immediate = false}) {
    final trimmed = handle.trim().toLowerCase();
    if (trimmed.isEmpty) {
      setState(() => _state = UsernameState.empty);
      return;
    }

    final RegExp validRegex = RegExp(r'^[a-z0-9]{3,20}$');
    if (!validRegex.hasMatch(trimmed)) {
      setState(() {
        _state = UsernameState.invalid;
        _customErrorMessage =
            'Username must be 3–20 characters using lowercase letters and numbers.';
      });
      return;
    }

    if (_reservedUsernames.contains(trimmed)) {
      setState(() {
        _state = UsernameState.reserved;
        _customErrorMessage = 'This username is reserved and cannot be used.';
      });
      return;
    }

    setState(() => _state = UsernameState.checking);
    if (immediate) {
      _checkAvailability(trimmed);
    } else {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 450), () {
        _checkAvailability(trimmed);
      });
    }
  }

  Future<void> _checkAvailability(String handle) async {
    // Check if session exists
    if (widget.userId.isEmpty && FirebaseAuth.instance.currentUser == null) {
      setState(() {
        _state = UsernameState.invalid;
        _customErrorMessage = 'Session expired. Please sign in again.';
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(handle)
          .get();

      // Guard if user has changed text while query was in-flight
      if (!mounted || _handleController.text.trim().toLowerCase() != handle) {
        return;
      }

      final isAvailable = !doc.exists;
      _availabilityCache[handle] = isAvailable;

      setState(() {
        if (isAvailable) {
          _state = UsernameState.available;
          _customErrorMessage = null;
        } else {
          _state = UsernameState.taken;
          _customErrorMessage = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = UsernameState.available;
      });
    }
  }

  Future<void> _createHandle() async {
    final handle = _handleController.text.trim().toLowerCase();
    final RegExp validRegex = RegExp(r'^[a-z0-9]{3,20}$');

    // Security Gate 1: Strict Format Check
    if (!validRegex.hasMatch(handle) || _reservedUsernames.contains(handle)) {
      setState(() {
        _state = UsernameState.invalid;
        _customErrorMessage = 'Invalid or reserved username.';
      });
      return;
    }

    // Security Gate 2: Auth Verification
    final effectiveUid = widget.userId.isNotEmpty
        ? widget.userId
        : (FirebaseAuth.instance.currentUser?.uid ?? widget.user?.uid ?? '');

    if (effectiveUid.isEmpty) {
      setState(() {
        _customErrorMessage = 'Authentication error. Please re-login.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _customErrorMessage = null;
    });

    try {
      final handleRef =
          FirebaseFirestore.instance.collection('profiles').doc(handle);
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(effectiveUid);

      // Security Gate 3: Atomic Multi-Document Transaction (Prevents TOCTOU & Orphaned Profiles)
      final isSuccess =
          await FirebaseFirestore.instance.runTransaction((transaction) async {
        final profileDoc = await transaction.get(handleRef);
        if (profileDoc.exists) {
          return false;
        }

        final userDoc = await transaction.get(userRef);
        // If user document already has a handle, preserve safety
        if (userDoc.exists && userDoc.data()?.containsKey('handle') == true) {
          final existing = userDoc.data()?['handle'];
          if (existing != null && existing.toString().isNotEmpty) {
            // Already claimed
            return true;
          }
        }

        // 1. Create Public Profile
        transaction.set(handleRef, {
          'handle': handle,
          'ownerUid': effectiveUid,
          'friendCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 2. Create/Update Private User Document atomically
        transaction.set(
          userRef,
          {
            'handle': handle,
            'phoneNumber': widget.phoneNumber,
            'uid': effectiveUid,
            'userId': effectiveUid,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return true;
      });

      if (!isSuccess) {
        _availabilityCache[handle] = false;
        setState(() {
          _state = UsernameState.taken;
          _isSubmitting = false;
        });
        return;
      }

      // Save locally in SecureStorage and SharedPreferences
      await AuthService.instance.saveUserHandle(handle);

      // If user selected a profile image, upload and sync
      if (_pickedProfileImage != null) {
        try {
          final uploadedUrl = await TelegramStorageService.uploadImage(_pickedProfileImage!);
          if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
            await AuthService.instance.updateUserProfileImage(uploadedUrl);
          }
        } catch (e) {
          debugPrint('Profile photo upload warning during onboarding: $e');
        }
      }

      widget.repository.currentUserHandle = handle;
      PresenceService.instance.init(handle);

      if (!mounted) return;

      // Onboarding transition
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PermissionRequestScreen(
            onComplete: (permContext) async {
              final p = await SharedPreferences.getInstance();
              await p.setString('perms_done', 'true');
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
      if (mounted) {
        setState(() {
          _customErrorMessage =
              'Failed to create username: ${e.toString().replaceAll('Exception:', '').trim()}';
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Setup?'),
        content: const Text(
            'If you leave now, your account setup won\'t be completed and you will be signed out.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.instance.signOut();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => PhoneLoginScreen(repository: widget.repository),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isButtonActive =
        _state == UsernameState.available && !_isSubmitting;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleSignOut();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Color(0xFF64748B),
              size: 22,
            ),
            tooltip: 'Cancel & Sign Out',
            onPressed: _handleSignOut,
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        const SizedBox(height: 16),

                        // App Logo (Two overlapping geometric circles)
                        _buildLogo(),

                        const SizedBox(height: 32),

                        // Title
                        const Text(
                          'Choose your\nusername',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                            letterSpacing: -0.5,
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Subtitle
                        const Text(
                          'Your username is how people will find\nand recognize you in the app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF64748B),
                            height: 1.4,
                            fontWeight: FontWeight.w400,
                          ),
                        ),

                        const SizedBox(height: 36),

                        // Username Input Field Box
                        _buildInputField(),

                        const SizedBox(height: 10),

                        // Status & Helper Message below input
                        _buildStatusHelper(),

                        const Spacer(),

                        const SizedBox(height: 24),

                        // Continue Button
                        _buildContinueButton(isButtonActive),

                        const SizedBox(height: 16),

                        // Footer note
                        const Text(
                          'You can change your username later.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w400,
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return GestureDetector(
      onTap: _showPhotoPickerSheet,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 96,
            height: 96,
            padding: EdgeInsets.all(_pickedProfileImage != null ? 3.0 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _pickedProfileImage != null ? UserAvatar.instagramGradient : null,
              color: _pickedProfileImage == null ? const Color(0xFFF8FAFC) : null,
              border: _pickedProfileImage == null
                  ? Border.all(color: const Color(0xFFE2E8F0), width: 2)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF64748B).withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Container(
              padding: _pickedProfileImage != null ? const EdgeInsets.all(2.5) : EdgeInsets.zero,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: _pickedProfileImage != null
                    ? Image.file(
                        _pickedProfileImage!,
                        width: 86,
                        height: 86,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                      )
                    : Center(
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                top: 2,
                                left: 6,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF3B82F6),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 2,
                                right: 6,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    Color borderColor;
    Color fillColor;
    List<BoxShadow> shadows = [];

    switch (_state) {
      case UsernameState.empty:
        borderColor = _focusNode.hasFocus
            ? const Color(0xFF3B82F6)
            : const Color(0xFFE2E8F0);
        fillColor = Colors.white;
        if (_focusNode.hasFocus) {
          shadows = [
            BoxShadow(
              color: const Color(0xFF3B82F6).withOpacity(0.12),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ];
        }
        break;
      case UsernameState.focused:
        borderColor = const Color(0xFF3B82F6);
        fillColor = Colors.white;
        shadows = [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.12),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ];
        break;
      case UsernameState.checking:
        borderColor = const Color(0xFFE2E8F0);
        fillColor = Colors.white;
        break;
      case UsernameState.available:
        borderColor = const Color(0xFF3B82F6);
        fillColor = Colors.white;
        shadows = [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.14),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ];
        break;
      case UsernameState.taken:
      case UsernameState.invalid:
      case UsernameState.reserved:
        borderColor = const Color(0xFFF87171);
        fillColor = const Color(0xFFFEF2F2);
        break;
    }

    return AnimatedContainer(
      duration: AppMotion.durationMicro,
      curve: AppMotion.interactiveCurve,
      height: 60,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: (_state == UsernameState.available ||
                  _state == UsernameState.focused ||
                  (_state == UsernameState.empty && _focusNode.hasFocus))
              ? 2.0
              : 1.5,
        ),
        boxShadow: shadows,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 18, right: 8),
            child: Text(
              '@',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _handleController,
              focusNode: _focusNode,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                TextInputFormatter.withFunction((oldVal, newVal) {
                  return newVal.copyWith(
                    text: newVal.text.toLowerCase(),
                  );
                }),
              ],
              onChanged: _onTextChanged,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
                letterSpacing: 0.2,
              ),
              decoration: const InputDecoration(
                hintText: 'username',
                hintStyle: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (_state == UsernameState.checking)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                ),
              ),
            )
          else
            const SizedBox(width: 18),
        ],
      ),
    );
  }

  Widget _buildStatusHelper() {
    switch (_state) {
      case UsernameState.empty:
      case UsernameState.focused:
        return const SizedBox(
          width: double.infinity,
          child: Padding(
            padding: EdgeInsets.only(left: 4, top: 4),
            child: Text(
              '3–20 characters • lowercase letters and numbers',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        );

      case UsernameState.checking:
        return const SizedBox(
          width: double.infinity,
          child: Padding(
            padding: EdgeInsets.only(left: 4, top: 4),
            child: Text(
              'Checking availability...',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );

      case UsernameState.available:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 4),
              child: Row(
                children: const [
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Color(0xFF16A34A),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Username available',
                    style: TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                '3–20 characters • lowercase letters and numbers',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        );

      case UsernameState.taken:
        return Padding(
          padding: const EdgeInsets.only(left: 2, top: 4),
          child: Row(
            children: const [
              Icon(
                Icons.cancel,
                size: 18,
                color: Color(0xFFEF4444),
              ),
              SizedBox(width: 6),
              Text(
                'Username is already taken',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );

      case UsernameState.invalid:
      case UsernameState.reserved:
        return Padding(
          padding: const EdgeInsets.only(left: 2, top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.cancel,
                  size: 18,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _customErrorMessage ??
                      'Username must be 3–20 characters using lowercase letters and numbers.',
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildContinueButton(bool isButtonActive) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isButtonActive
            ? [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isButtonActive
              ? const Color(0xFF3B82F6)
              : const Color(0xFF93C5FD).withOpacity(0.6),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: isButtonActive ? _createHandle : null,
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
              )
            : const Text(
                'Continue',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}
