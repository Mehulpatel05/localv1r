import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/instagram_avatar_cropper.dart';
import '../../core/models/user_profile.dart';
import '../../core/auth_repository.dart';
import '../../core/theme.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../../services/auth_service.dart';
import '../../services/r2_storage_service.dart';
import '../../services/friend_repository.dart';
import '../../models/friendship_model.dart';
import '../friends/friends_screen.dart';
import '../../features/settings/settings_page.dart';
import '../../core/location/city_picker_screen.dart';
import '../bazar/bazar_screen.dart';
import '../shop/register_shop_screen.dart';
import '../saved/saved_screen.dart';

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
  late final FriendRepository _friendRepository;

  @override
  void initState() {
    super.initState();
    _bioController = TextEditingController();
    _friendRepository = FriendRepository()
      ..currentUserHandle = widget.currentUserHandle;

    // ⚡ Instant 0ms initial state from local cache
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();
    final cachedPhoto = AvatarCacheService.instance.getCachedUrl(cleanHandle);
    _userData = {
      'handle': widget.currentUserHandle,
      'phone': '',
      'email': '',
      'bio': '',
      'photoUrl': cachedPhoto,
      'reputation': 0,
      'upvotes': 0,
      'friendCount': 0,
      'createdAt': DateTime.now(),
    };

    // Pre-populate posts from in-memory repository cache
    _userPosts = widget.repository.posts
        .where((p) => p.authorHandle.replaceAll('@', '').trim().toLowerCase() == cleanHandle.toLowerCase())
        .toList();
    _isLoading = _userPosts.isEmpty && cachedPhoto == null;

    _loadProfileData();
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();

    // 1. Fast local check if photo was missing in memory cache
    if (_userData?['photoUrl'] == null) {
      final localPhoto = await AvatarCacheService.instance.getMyPhotoUrlLocally();
      if (localPhoto != null && localPhoto.isNotEmpty && mounted) {
        setState(() {
          _userData?['photoUrl'] = localPhoto;
        });
        AvatarCacheService.instance.setCachedUrl(cleanHandle, localPhoto);
      }
    }

    try {
      // 2. Background cloud profile sync
      final cloudProfile = await AuthService.instance.syncCloudProfile();

      String? photoUrl = cloudProfile?['photoUrl'] as String?;
      photoUrl ??= AvatarCacheService.instance.getCachedUrl(cleanHandle);
      if (photoUrl == null || photoUrl.isEmpty) {
        photoUrl = await AvatarCacheService.instance.fetchAvatarUrl(cleanHandle);
      }

      final rawPhone = cloudProfile?['phoneNumber'] ?? (await AuthService.instance.getPhoneNumber()) ?? '';
      final resolvedHandle = (cloudProfile?['handle'] ?? widget.currentUserHandle).toString().trim();

      if (mounted) {
        setState(() {
          // Merge-update: only update fields that have new values, never clear existing data
          _userData = {
            ...?_userData,
            'handle': resolvedHandle,
            'phone': rawPhone,
            if (cloudProfile?['bio'] != null) 'bio': cloudProfile!['bio'],
            if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
            if (cloudProfile?['reputation'] != null) 'reputation': cloudProfile!['reputation'],
            if (cloudProfile?['upvotes'] != null) 'upvotes': cloudProfile!['upvotes'],
            if (cloudProfile?['friendCount'] != null) 'friendCount': cloudProfile!['friendCount'],
          };
          if (!_isSavingBio && (_bioController.text.isEmpty || _bioController.text == _userData!['bio'])) {
            _bioController.text = (_userData!['bio'] as String?) ?? '';
          }
        });
      }

      if (photoUrl != null && photoUrl.isNotEmpty) {
        AvatarCacheService.instance.setCachedUrl(cleanHandle, photoUrl);
      }

      final freshPosts = await widget.repository.fetchPostsByUser(widget.currentUserHandle);
      if (mounted) {
        setState(() {
          _userPosts = freshPosts;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showChangeProfilePhotoSheet() {
    final handle = _userData?['handle'] ?? widget.currentUserHandle;
    final currentPhoto = _userData?['photoUrl'] as String?;
    final hasPhoto = currentPhoto != null && currentPhoto.trim().isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: const Color(0xFF072E33),
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
      final uploadedUrl = await R2StorageService.uploadImage(croppedFile);

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
      final bioText = _bioController.text.trim();
      setState(() {
        _userData!['bio'] = bioText;
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
        backgroundColor: const Color(0xFF072E33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Bio',
          style: TextStyle(
            color: Colors.white,
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

  String _getJoinedYear() {
    final raw = _userData?['createdAt'];
    if (raw is DateTime) {
      return '${raw.year}';
    } else if (raw is String) {
      final dt = DateTime.tryParse(raw);
      if (dt != null) return '${dt.year}';
    } else if (raw is int) {
      final dt = raw > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(raw)
          : DateTime.fromMillisecondsSinceEpoch(raw * 1000);
      return '${dt.year}';
    }
    return '${DateTime.now().year}';
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
    final cardBg = const Color(0xFF072E33);
    final borderColor = const Color(0xFF0E4B52);

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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Semantics(
              label: 'Settings',
              button: true,
              child: GestureDetector(
                onTap: () {
                  final handle = (_userData?['handle'] as String?) ??
                      widget.currentUserHandle;
                  final phone = _userData?['phone'] as String?;
                  final email = _userData?['email'] as String?;
                  DateTime? joinedDate;
                  final rawCreated = _userData?['createdAt'];
                  if (rawCreated is DateTime) {
                    joinedDate = rawCreated;
                  } else if (rawCreated is String) {
                    joinedDate = DateTime.tryParse(rawCreated);
                  } else if (rawCreated is int) {
                    joinedDate = rawCreated > 1000000000000
                        ? DateTime.fromMillisecondsSinceEpoch(rawCreated)
                        : DateTime.fromMillisecondsSinceEpoch(rawCreated * 1000);
                  }
                  final profile = UserProfile(
                    handle: handle.replaceAll('@', '').trim(),
                    phone: (phone == null || phone.isEmpty) ? null : phone,
                    email: (email == null || email.isEmpty) ? null : email,
                    joinedYear: joinedDate?.year ??
                        int.tryParse(_getJoinedYear()) ??
                        DateTime.now().year,
                    joinedDate: joinedDate,
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(
                        authRepository: BackendAuthRepository(),
                        profile: profile,
                      ),
                    ),
                  );
                },
                child: Builder(builder: (ctx) {
                  final c = ctx.nearhoodColors;
                  return Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.field,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.settings_outlined,
                      size: 20,
                      color: c.ink,
                    ),
                  );
                }),
              ),
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

              // 3. Stats Card (Posts | Listings | Neighbours)
              Builder(
                builder: (context) {
                  final listingsCount = _userPosts.where((p) =>
                    p.category == PostCategory.shop ||
                    p.category == PostCategory.rooms ||
                    p.category == PostCategory.services ||
                    p.category == PostCategory.events ||
                    p.shopTitle != null ||
                    p.roomTitle != null
                  ).length;

                  return Container(
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
                        _buildStatItem(
                          '$listingsCount',
                          'Listings',
                          isDark,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const BazarScreen(initialShowMyListings: true),
                              ),
                            );
                          },
                        ),
                        Container(
                          height: 30,
                          width: 1,
                          color: borderColor,
                        ),
                        StreamBuilder<List<Friendship>>(
                          stream: _friendRepository.getFriendsList(),
                          builder: (context, snapshot) {
                            final count = snapshot.hasData
                                ? snapshot.data!.length
                                : (_userData?['friendCount'] as int? ?? 0);
                            return _buildStatItem(
                              '$count',
                              'Neighbours',
                              isDark,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FriendsScreen(
                                      repository: _friendRepository,
                                      currentUserHandle: widget.currentUserHandle,
                                      initialTab: FriendsTab.friends,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
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
                        SharePlus.instance.share(
                          ShareParams(
                            text:
                                'Connect with @$handle on Nearhood — the local community app for Vadodara!',
                          ),
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

              // 6. Action Menu Items Card (My listings, Saved items, Change area, Register your shop)
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    // 1. My listings
                    _buildProfileMenuItem(
                      icon: Icons.shopping_bag_outlined,
                      title: 'My listings',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BazarScreen(initialShowMyListings: true),
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, color: borderColor),

                    // 2. Saved items
                    _buildProfileMenuItem(
                      icon: Icons.favorite_border_rounded,
                      title: 'Saved items',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SavedScreen(),
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, color: borderColor),

                    // 3. Change area
                    _buildProfileMenuItem(
                      icon: Icons.push_pin_outlined,
                      title: 'Change area',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CityPickerScreen()),
                        );
                      },
                    ),
                    Divider(height: 1, color: borderColor),

                    // 4. Register your shop
                    _buildProfileMenuItem(
                      icon: Icons.store_mall_directory_outlined,
                      title: 'Register your shop',
                      subtitle: 'For local businesses',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RegisterShopScreen()),
                        );
                      },
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

  Widget _buildStatItem(
    String count,
    String label,
    bool isDark, {
    VoidCallback? onTap,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
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

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }
    return content;
  }

  Widget _buildProfileMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF90B4B6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF90B4B6),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
