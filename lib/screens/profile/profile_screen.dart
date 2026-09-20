import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/widgets/post_image_view.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/instagram_avatar_cropper.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../../services/auth_service.dart';
import '../../services/telegram_storage_service.dart';
import '../../services/avatar_cache_service.dart';
import '../auth/phone_login_screen.dart';
import '../detail/post_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const ProfileScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  List<Post> _userPosts = [];
  bool _isLoading = true;
  bool _isSavingBio = false;
  bool _isUploadingPhoto = false;
  late TextEditingController _bioController;
  // Keep at state level so it's never disposed while dialog animation is running
  final TextEditingController _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bioController = TextEditingController();
    _loadProfileData();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final storedUserId = await AuthService.instance.getUserId();
      final effectiveUid = storedUserId ?? user?.uid;
      final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();

      Map<String, dynamic> data = {};
      if (effectiveUid != null && effectiveUid.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(effectiveUid)
            .get();
        if (doc.exists && doc.data() != null) {
          data = doc.data()!;
        }
      }

      // If document wasn't found by UID, check profiles or query users collection
      if (data.isEmpty && cleanHandle.isNotEmpty) {
        final pdoc = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(cleanHandle)
            .get();
        if (pdoc.exists && pdoc.data() != null) {
          data = pdoc.data()!;
        } else {
          final uq = await FirebaseFirestore.instance
              .collection('users')
              .where('handle', isEqualTo: cleanHandle)
              .limit(1)
              .get();
          if (uq.docs.isNotEmpty) {
            data = uq.docs.first.data();
          }
        }
      }

      final resolvedHandle = (data['handle'] ?? data['userHandle'] ?? widget.currentUserHandle).toString().trim();
      String? photoUrl = (data['photoUrl'] as String?)?.trim();
      if (photoUrl == null || photoUrl.isEmpty) {
        photoUrl = user?.photoURL;
      }
      if (photoUrl == null || photoUrl.isEmpty) {
        photoUrl = AvatarCacheService.instance.getCachedUrl(cleanHandle);
      }
      _userData = {
        'handle': resolvedHandle,
        'email': data['email'] ?? user?.email ?? '',
        'bio': (data['bio'] as String?)?.trim() ?? '',
        'photoUrl': photoUrl,
        'createdAt': data['createdAt'],
      };
      if (photoUrl != null && photoUrl.isNotEmpty) {
        AvatarCacheService.instance.setCachedUrl(cleanHandle, photoUrl);
      }
      _bioController.text = _userData!['bio'] as String;

      int waited = 0;
      while (widget.repository.isLoading && waited < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        waited++;
      }

      _userPosts =
          await widget.repository.fetchPostsByUser(widget.currentUserHandle);
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showChangeProfilePhotoSheet() {
    final handle = _userData?['handle'] ?? widget.currentUserHandle;
    final currentPhoto = (_userData?['photoUrl'] as String?) ?? FirebaseAuth.instance.currentUser?.photoURL;
    final hasPhoto = currentPhoto != null && currentPhoto.trim().isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Change Profile Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F3FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF8B5CF6), size: 22),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: const Text('Select a photo from your photo library', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadPhoto(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF3B82F6), size: 22),
                ),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: const Text('Open camera to snap a new photo', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadPhoto(ImageSource.camera);
                },
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0FDF4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.visibility_outlined, color: Color(0xFF16A34A), size: 22),
                  ),
                  title: const Text('View Profile Picture', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  subtitle: const Text('See full size profile photo', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                  onTap: () {
                    Navigator.pop(ctx);
                    UserAvatar.showFullAvatar(context, handle: handle, photoUrl: currentPhoto);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEF2F2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
                  ),
                  title: const Text('Remove Current Picture', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFFEF4444))),
                  subtitle: const Text('Revert back to your initials avatar', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeProfilePhoto();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    final handle = _userData?['handle'] ?? widget.currentUserHandle;
    final previousPhotoUrl = _userData?['photoUrl'];

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (picked == null) return;

      final rawFile = File(picked.path);

      if (!mounted) return;

      // Open Instagram Move and Scale interactive cropper
      final croppedFile = await InstagramAvatarCropper.cropImage(
        context,
        imageFile: rawFile,
      );

      if (croppedFile == null) return; // User cancelled cropping

      // ⚡ Optimistic UI: Immediately render the new cropped photo locally with 0ms lag
      setState(() {
        _isUploadingPhoto = true;
        _userData?['photoUrl'] = croppedFile.path;
      });
      AvatarCacheService.instance.setCachedUrl(handle, croppedFile.path);

      // Fast background network upload
      final uploadedUrl = await TelegramStorageService.uploadImage(croppedFile);

      if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
        await AuthService.instance.updateUserProfileImage(uploadedUrl);
        AvatarCacheService.instance.setCachedUrl(handle, uploadedUrl);
        await AvatarCacheService.instance.saveMyPhotoUrlLocally(uploadedUrl);

        if (mounted) {
          setState(() {
            _userData?['photoUrl'] = uploadedUrl;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              content: Text('Profile photo updated successfully!'),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _userData?['photoUrl'] = previousPhotoUrl;
          });
          AvatarCacheService.instance.setCachedUrl(handle, previousPhotoUrl);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to upload image. Please check your network and try again.'),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userData?['photoUrl'] = previousPhotoUrl;
        });
        AvatarCacheService.instance.setCachedUrl(handle, previousPhotoUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading profile photo: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _removeProfilePhoto() async {
    try {
      setState(() => _isUploadingPhoto = true);
      await AuthService.instance.removeUserProfileImage();
      if (mounted) {
        setState(() {
          _userData?['photoUrl'] = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            content: Text('Profile photo removed.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove profile photo: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _saveBio() async {
    setState(() => _isSavingBio = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'bio': _bioController.text.trim(),
        });
        setState(() {
          _userData!['bio'] = _bioController.text.trim();
        });
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              content: Text('Bio saved successfully!'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save bio: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingBio = false);
    }
  }

  void _showEditBioDialog() {
    _bioController.text = _userData?['bio'] ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Bio',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: TextField(
          controller: _bioController,
          maxLines: 4,
          maxLength: 200,
          style: const TextStyle(color: Color(0xFF1E293B), fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Tell neighbors about yourself...',
            hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
                width: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
              foregroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _isSavingBio ? null : _saveBio,
            child: _isSavingBio
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.black
                          : Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Sign Out?',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'You will be returned to the login screen.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await AuthService.instance.signOut();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => PhoneLoginScreen(repository: widget.repository),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign out failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    // Step 1: First warning dialog
    final step1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 26),
            SizedBox(width: 10),
            Text(
              'Delete Account?',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: const Text(
          'This will permanently delete your account, all your posts, friendships, and profile data.\n\nThis action cannot be undone.',
          style: TextStyle(color: Color(0xFF475569), fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (step1 != true || !mounted) return;

    // Step 2: Type "DELETE" confirmation
    // Use state-level controller so it's never disposed while the dialog exit-animates
    _confirmController.clear();
    final step2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Final Confirmation',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Type DELETE below to permanently remove your account:',
                  style: TextStyle(color: Color(0xFF475569), fontSize: 13.5, height: 1.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  autofocus: true,
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'DELETE',
                    hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
                    filled: true,
                    fillColor: const Color(0xFFFEF2F2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFECACA)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                    ),
                  ),
                  onChanged: (_) => setS(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _confirmController.text.trim() == 'DELETE'
                    ? const Color(0xFFEF4444)
                    : const Color(0xFFCBD5E1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _confirmController.text.trim() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete Forever'),
            ),
          ],
        ),
      ),
    );

    if (step2 != true || !mounted) return;

    // Show loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      final handle = _userData?['handle'] ?? widget.currentUserHandle;
      final db = FirebaseFirestore.instance;

      // 1. Primary: Call Backend Admin Endpoint (deletes all Firestore data & Firebase Auth user without client limitations)
      final serverResult = await AuthService.instance.deleteAccount();

      // 2. Best-effort client cleanup (in case of offline/direct writes)
      if (handle.isNotEmpty) {
        try {
          final postsSnap = await db
              .collection('posts')
              .where('authorHandle', isEqualTo: handle)
              .get();
          for (final doc in postsSnap.docs) {
            await doc.reference.delete();
          }
        } catch (_) {}

        try {
          await db.collection('profiles').doc(handle).delete();
        } catch (_) {}
      }

      if (uid != null && uid.isNotEmpty) {
        try {
          final sentReqs = await db
              .collection('friend_requests')
              .where('senderUid', isEqualTo: uid)
              .get();
          for (final doc in sentReqs.docs) {
            await doc.reference.delete();
          }
        } catch (_) {}

        try {
          final recvReqs = await db
              .collection('friend_requests')
              .where('receiverUid', isEqualTo: uid)
              .get();
          for (final doc in recvReqs.docs) {
            await doc.reference.delete();
          }
        } catch (_) {}

        try {
          final friendships = await db
              .collection('friendships')
              .where('usersUids', arrayContains: uid)
              .get();
          for (final doc in friendships.docs) {
            await doc.reference.delete();
          }
        } catch (_) {}

        try {
          final blocks = await db
              .collection('blocks')
              .where('blockerUid', isEqualTo: uid)
              .get();
          for (final doc in blocks.docs) {
            await doc.reference.delete();
          }
        } catch (_) {}

        try {
          await db.collection('users').doc(uid).delete();
        } catch (_) {}
      }

      // 3. Try client user delete (ignore if already deleted by server admin SDK)
      try {
        await user?.delete();
      } catch (_) {}

      // 4. Clear all local storage & sign out
      await AuthService.instance.signOut();

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading

      // If server reported failure and user was not signed out properly, show note
      if (serverResult['success'] != true && serverResult['error'] != null) {
        debugPrint('[DeleteAccount] Server deletion note: ${serverResult['error']}');
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => PhoneLoginScreen(repository: widget.repository),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // close loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _getJoinedYear() {
    final raw = _userData?['createdAt'];
    if (raw is Timestamp) {
      return '${raw.toDate().year}';
    }
    return '${DateTime.now().year}';
  }

  int _getTotalUpvotes() {
    int total = 0;
    final Set<String> seenIds = {};
    for (final p in _userPosts) {
      final live = widget.repository.getPostById(p.id) ?? p;
      seenIds.add(p.id);
      total += (live.upvotes > 0 ? live.upvotes : 0);
    }
    final repoPosts = widget.repository.allPosts
        .where((p) => p.authorHandle == widget.currentUserHandle);
    for (final p in repoPosts) {
      if (!seenIds.contains(p.id)) {
        seenIds.add(p.id);
        total += (p.upvotes > 0 ? p.upvotes : 0);
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
        ),
      );
    }

    final handle = _userData?['handle'] ?? widget.currentUserHandle;
    final email = _userData?['email'] ?? '';
    final bio = _userData?['bio'] ?? '';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF141414) : Colors.white;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          'Profile',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          // Sign Out with soft reddish circular container
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFFEF2F2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: 'Sign Out',
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFC2402D),
                size: 20,
              ),
              onPressed: _signOut,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfileData,
        color: isDark ? Colors.white : Colors.black,
        child: ListenableBuilder(
          listenable: widget.repository,
          builder: (context, _) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              // 1. Profile Avatar with Clean Ring and Camera Edit Badge
              Stack(
                alignment: Alignment.center,
                children: [
                  UserAvatar(
                    handle: handle,
                    photoUrl: _userData?['photoUrl'] as String?,
                    size: 96,
                    showRing: true,
                    ringGradient: LinearGradient(
                      colors: isDark
                          ? const [Colors.white, Colors.white70]
                          : const [Colors.black, Color(0xFF4B5563)],
                    ),
                    ringWidth: 2.5,
                    ringGap: 3.0,
                    fontSize: 28,
                    onTap: _isUploadingPhoto ? null : _showChangeProfilePhotoSheet,
                    editBadge: GestureDetector(
                      onTap: _isUploadingPhoto ? null : _showChangeProfilePhotoSheet,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                  if (_isUploadingPhoto)
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // 2. Handle & Subtitle
              Text(
                '@$handle',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Nearhood member',
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF808080) : const Color(0xFF94A3B8),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // 3. Stats Card (Posts | Upvotes | Joined)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('${_userPosts.length}', 'Posts', isDark),
                    Container(
                      height: 30,
                      width: 1,
                      color: borderColor,
                    ),
                    _buildStatItem('${_getTotalUpvotes()}', 'Upvotes', isDark),
                    Container(
                      height: 30,
                      width: 1,
                      color: borderColor,
                    ),
                    _buildStatItem(_getJoinedYear(), 'Joined', isDark),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 4. Action Buttons Row (Edit Bio | Share)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white : Colors.black,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text(
                        'Edit Bio',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      onPressed: _showEditBioDialog,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: cardBg,
                        foregroundColor: isDark ? Colors.white : Colors.black,
                        side: BorderSide(color: borderColor, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.share_outlined, size: 16),
                      label: const Text(
                        'Share',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      onPressed: () {
                        Share.share(
                          'Connect with @$handle on Nearhood — the local community app for Vadodara!',
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 5. About Me Section Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'About Me',
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        GestureDetector(
                          onTap: _showEditBioDialog,
                          child: Text(
                            'Edit',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      bio.trim().isEmpty
                          ? 'No bio added yet. Tap edit to write something about yourself.'
                          : bio,
                      style: TextStyle(
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
                        fontSize: 13.5,
                        height: 1.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 6. Nearhood Community Section
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nearhood community',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Local community member',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 7. My Posts Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Posts',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    '${_userPosts.length} ${_userPosts.length == 1 ? "post" : "posts"}',
                    style: TextStyle(
                      color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (_userPosts.isEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: const [
                      Icon(Icons.post_add_rounded,
                          size: 40, color: Color(0xFF94A3B8)),
                      SizedBox(height: 10),
                      Text(
                        'No posts published yet',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Your shared posts will appear here.',
                        style:
                            TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                ..._userPosts.map((post) => _buildUserPostCard(post)),
              ],

              const SizedBox(height: 32),

              // Danger Zone Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFECACA), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.warning_amber_rounded,
                            size: 18, color: Color(0xFFEF4444)),
                        SizedBox(width: 8),
                        Text(
                          'Danger Zone',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Permanently delete your account and all associated data. This cannot be undone.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(
                              color: Color(0xFFEF4444), width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.delete_forever_rounded, size: 18),
                        label: const Text(
                          'Delete My Account',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        onPressed: _deleteAccount,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildStatItem(String count, String label, bool isDark) {
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildUserPostCard(Post rawPost) {
    final post = widget.repository.getPostById(rawPost.id) ?? rawPost;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF141414) : Colors.white;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PostDetailScreen(
                  post: post,
                  repository: widget.repository,
                  currentUserHandle: widget.currentUserHandle,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category Pill & Date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: post.isEmergency
                            ? const Color(0xFFFEF2F2)
                            : (isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF4F4F4)),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: post.isEmergency
                              ? const Color(0xFFFECACA)
                              : borderColor,
                        ),
                      ),
                      child: Text(
                        post.category.label,
                        style: TextStyle(
                          color: post.isEmergency
                              ? const Color(0xFFEF4444)
                              : (isDark ? Colors.white70 : const Color(0xFF4B5563)),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${post.createdAt.day} ${_getMonthName(post.createdAt.month)}',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Content
                Text(
                  post.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),

                if ((post.imageUrl != null && post.imageUrl!.isNotEmpty) || post.mediaUrls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  PostImageView(
                    imageUrl: (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                        ? post.imageUrl!
                        : post.mediaUrls.first,
                    allImages: post.mediaUrls.isNotEmpty
                        ? post.mediaUrls
                        : [post.imageUrl!],
                    height: 180,
                    borderRadius: BorderRadius.circular(14),
                    heroTagPrefix: 'profile_post_${post.id}',
                    caption: post.content,
                  ),
                ],

                const SizedBox(height: 12),

                // Footer (Upvotes & Location)
                Row(
                  children: [
                    Icon(
                      Icons.arrow_upward_rounded,
                      size: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.upvotes}',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_downward_rounded,
                      size: 14,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${post.downvotes}',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6E6E6E),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.location_on_rounded,
                      size: 13,
                      color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      post.areaName ?? 'Vadodara',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[(month - 1) % 12];
  }
}
