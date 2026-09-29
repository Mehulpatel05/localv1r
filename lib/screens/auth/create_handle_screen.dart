import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/motion.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/content_filter.dart';
import '../../services/post_repository.dart';
import '../../services/presence_service.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/r2_storage_service.dart';
import '../../core/splash_controller.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/instagram_avatar_cropper.dart';
import '../../core/theme.dart';
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
  final dynamic user;

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
    final colors = context.nearhoodColors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: colors.field,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            color: colors.field,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: colors.line, width: 1.5),
            ),
          ),
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
                    color: colors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Add Profile Picture',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.field2,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF38BDF8), size: 22),
                ),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
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
                  decoration: BoxDecoration(
                    color: colors.field2,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFFA78BFA), size: 22),
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
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
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
                  ),
                  title: const Text(
                    'Remove Photo',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFFEF4444),
                    ),
                  ),
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
    if (widget.userId.isEmpty) {
      final loggedIn = await AuthService.instance.isLoggedIn();
      if (!loggedIn) {
        setState(() {
          _state = UsernameState.invalid;
          _customErrorMessage = 'Session expired. Please sign in again.';
        });
        return;
      }
    }

    try {
      final isAvailable = await AuthService.instance.checkHandleAvailable(handle);

      // Guard if user has changed text while query was in-flight
      if (!mounted || _handleController.text.trim().toLowerCase() != handle) {
        return;
      }

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
        : (await AuthService.instance.getUserId() ?? '');

    setState(() {
      _isSubmitting = true;
      _customErrorMessage = null;
    });

    try {
      debugPrint('[CreateHandleScreen] Submitting handle "$handle" for uid: $effectiveUid');
      final result = await AuthService.instance.saveUserHandle(
        handle,
        userId: effectiveUid,
        phone: widget.phoneNumber,
      );

      if (result['success'] != true) {
        final isTaken = result['isTaken'] == true;
        final errorMsg = result['error'] as String? ?? 'Failed to update username.';
        
        if (isTaken) {
          _availabilityCache[handle] = false;
        }

        setState(() {
          _state = isTaken ? UsernameState.taken : UsernameState.available;
          _isSubmitting = false;
          _customErrorMessage = errorMsg;
        });
        return;
      }

      // If user selected a profile image, upload and sync
      if (_pickedProfileImage != null) {
        try {
          final uploadedUrl = await R2StorageService.uploadImage(_pickedProfileImage!);
          if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
            await AuthService.instance.updateUserProfileImage(uploadedUrl);
          }
        } catch (e) {
          debugPrint('Profile photo upload warning during onboarding: $e');
        }
      }

      widget.repository.currentUserHandle = handle;
      NotificationService().initialize();
      NotificationService().startListening(handle);
      PresenceService.instance.init(handle);

      // ⚡ Instant Cache Preloading (Chats, Communities, Feeds, Preferences)
      SplashController.instance.warmFetchOnLogin(
        uid: effectiveUid,
        handle: handle,
        cityId: 'surat_gujarat',
        postRepo: widget.repository,
      );

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
    final colors = context.nearhoodColors;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.field,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.line, width: 1.5),
        ),
        title: Text(
          'Cancel Setup?',
          style: TextStyle(color: colors.ink, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'If you leave now, your account setup won\'t be completed and you will be signed out.',
          style: TextStyle(color: colors.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Stay', style: TextStyle(color: colors.muted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w700)),
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
    final colors = context.nearhoodColors;
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
        backgroundColor: colors.bg,
        appBar: AppBar(
          backgroundColor: colors.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: colors.muted,
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

                        // App Logo / Profile Avatar
                        _buildLogo(colors),

                        const SizedBox(height: 32),

                        // Title
                        Text(
                          'Choose your\nusername',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                            letterSpacing: -0.5,
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Subtitle
                        Text(
                          'Your username is how people will find\nand recognize you in the app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.muted,
                            height: 1.4,
                            fontWeight: FontWeight.w400,
                          ),
                        ),

                        const SizedBox(height: 36),

                        // Username Input Field Box
                        _buildInputField(colors),

                        const SizedBox(height: 10),

                        // Status & Helper Message below input
                        _buildStatusHelper(colors),

                        const Spacer(),

                        const SizedBox(height: 24),

                        // Continue Button
                        _buildContinueButton(colors, isButtonActive),

                        const SizedBox(height: 16),

                        // Footer note
                        Text(
                          'You can change your username later.',
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.muted.withValues(alpha: 0.7),
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

  Widget _buildLogo(NearhoodColors colors) {
    return GestureDetector(
      onTap: _showPhotoPickerSheet,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 104,
            height: 104,
            padding: EdgeInsets.all(_pickedProfileImage != null ? 3.0 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _pickedProfileImage != null ? UserAvatar.instagramGradient : null,
              color: _pickedProfileImage == null ? colors.field : null,
              border: _pickedProfileImage == null
                  ? Border.all(color: colors.line, width: 2)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Container(
              padding: _pickedProfileImage != null ? const EdgeInsets.all(2.5) : const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.field,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: _pickedProfileImage != null
                    ? Image.file(
                        _pickedProfileImage!,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                      )
                    : Image.asset(
                        'assets/images/nearhood_logo.png',
                        width: 64,
                        height: 64,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.person_rounded,
                            size: 44,
                            color: colors.muted,
                          );
                        },
                      ),
              ),
            ),
          ),
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.field2,
                shape: BoxShape.circle,
                border: Border.all(color: colors.bg, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 17,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(NearhoodColors colors) {
    Color borderColor;
    Color fillColor = colors.field;
    List<BoxShadow> shadows = [];

    switch (_state) {
      case UsernameState.empty:
        borderColor = _focusNode.hasFocus
            ? const Color(0xFF2DD4BF)
            : colors.line;
        if (_focusNode.hasFocus) {
          shadows = [
            BoxShadow(
              color: const Color(0xFF2DD4BF).withValues(alpha: 0.15),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ];
        }
        break;
      case UsernameState.focused:
        borderColor = const Color(0xFF2DD4BF);
        shadows = [
          BoxShadow(
            color: const Color(0xFF2DD4BF).withValues(alpha: 0.15),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ];
        break;
      case UsernameState.checking:
        borderColor = colors.line;
        break;
      case UsernameState.available:
        borderColor = const Color(0xFF4ADE80);
        shadows = [
          BoxShadow(
            color: const Color(0xFF4ADE80).withValues(alpha: 0.2),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ];
        break;
      case UsernameState.taken:
      case UsernameState.invalid:
      case UsernameState.reserved:
        borderColor = const Color(0xFFEF4444);
        fillColor = const Color(0xFFEF4444).withValues(alpha: 0.12);
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
          Padding(
            padding: const EdgeInsets.only(left: 18, right: 8),
            child: Text(
              '@',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.ink,
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
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.ink,
                letterSpacing: 0.2,
              ),
              decoration: InputDecoration(
                hintText: 'username',
                hintStyle: TextStyle(
                  color: colors.muted.withValues(alpha: 0.5),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2DD4BF)),
                ),
              ),
            )
          else
            const SizedBox(width: 18),
        ],
      ),
    );
  }

  Widget _buildStatusHelper(NearhoodColors colors) {
    switch (_state) {
      case UsernameState.empty:
      case UsernameState.focused:
        return SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              '3–20 characters • lowercase letters and numbers',
              style: TextStyle(
                color: colors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        );

      case UsernameState.checking:
        return SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              'Checking availability...',
              style: TextStyle(
                color: colors.muted,
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
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Color(0xFF4ADE80),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Username available',
                    style: TextStyle(
                      color: Color(0xFF4ADE80),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '3–20 characters • lowercase letters and numbers',
                style: TextStyle(
                  color: colors.muted,
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
                Icons.cancel_rounded,
                size: 18,
                color: Color(0xFFEF4444),
              ),
              SizedBox(width: 6),
              Text(
                'Username is already taken',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
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
                  Icons.cancel_rounded,
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
                    color: Color(0xFFEF4444),
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

  Widget _buildContinueButton(NearhoodColors colors, bool isButtonActive) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isButtonActive
            ? [
                BoxShadow(
                  color: colors.field2.withValues(alpha: 0.5),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isButtonActive
              ? colors.field2
              : colors.field,
          foregroundColor: isButtonActive
              ? Colors.white
              : colors.muted.withValues(alpha: 0.4),
          elevation: 0,
          side: BorderSide(
            color: isButtonActive ? const Color(0xFF2DD4BF) : colors.line,
            width: 1.5,
          ),
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
