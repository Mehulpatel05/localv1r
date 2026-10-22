import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/instagram_avatar_cropper.dart';
import '../../core/models/user_profile.dart';
import '../../core/auth_repository.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import '../../services/auth_service.dart';
import '../../services/r2_storage_service.dart';
import '../../core/services/name_cache_service.dart';
import '../../core/services/badge_cache_service.dart';
import '../../features/settings/settings_page.dart';
import 'area_change_request_screen.dart';
import 'my_posts_screen.dart';
import '../bazar/bazar_screen.dart';
import '../bazar/shop_detail_screen.dart';
import '../shop/register_shop_screen.dart';
import '../shop/manage/my_shop_dashboard_screen.dart';
import '../../services/bazar_repository.dart';
import '../shop/widgets/shop_status_sheet.dart';
import '../../theme/app_colors.dart';
import '../../models/rewards_model.dart';
import '../../services/rewards_service.dart';
import '../../models/founding_model.dart';
import '../../services/founding_service.dart';
import '../rewards/rewards_hub_screen.dart';
import 'profile_header_asset.dart';

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
  bool _isRefreshing = false;
  late TextEditingController _bioController;
  late TextEditingController _nameController;
  late TextEditingController _handleController;
  LocalShop? _myRegisteredShop;

  @override
  void initState() {
    super.initState();
    RewardsService.instance.fetchSummary(forceRefresh: true);
    _bioController = TextEditingController();
    _nameController = TextEditingController();
    _handleController = TextEditingController();

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

    _userPosts = widget.repository.posts
        .where((p) => p.authorHandle.replaceAll('@', '').trim().toLowerCase() == cleanHandle.toLowerCase())
        .toList();
    _isLoading = _userPosts.isEmpty && cachedPhoto == null;

    final loc = widget.repository.locationService;
    final currentAreaId = loc.area?.id ?? loc.city.id;
    FoundingService.instance.fetchMyStatus(cityId: loc.city.id, areaId: currentAreaId);

    _loadProfileData();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _nameController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();

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
      final cloudProfile = await AuthService.instance.syncCloudProfile();

      String? photoUrl;
      if (cloudProfile != null) {
        final cloudPhoto = (cloudProfile['photoUrl'] as String?)?.trim();
        photoUrl = (cloudPhoto != null && cloudPhoto.isNotEmpty) ? cloudPhoto : null;
        AvatarCacheService.instance.setCachedUrl(cleanHandle, photoUrl);
        await AvatarCacheService.instance.saveMyPhotoUrlLocally(photoUrl ?? '');
      } else {
        photoUrl = AvatarCacheService.instance.getCachedUrl(cleanHandle);
        if (photoUrl == null || photoUrl.isEmpty) {
          photoUrl = await AvatarCacheService.instance.fetchAvatarUrl(cleanHandle);
        }
      }

      final rawPhone = cloudProfile?['phoneNumber'] ?? (await AuthService.instance.getPhoneNumber()) ?? '';
      final resolvedHandle = (cloudProfile?['handle'] ?? widget.currentUserHandle).toString().trim();
      final rawCloudName = (cloudProfile?['displayName'] ?? cloudProfile?['display_name'] ?? cloudProfile?['name'] ?? cloudProfile?['fullName'])?.toString().trim();
      final localSavedName = (await NameCacheService.instance.getMyNameLocally())?.trim();
      final resolvedName = (rawCloudName != null && rawCloudName.isNotEmpty && !NameCacheService.isPlaceholderName(rawCloudName))
          ? rawCloudName
          : ((localSavedName != null && localSavedName.isNotEmpty && !NameCacheService.isPlaceholderName(localSavedName))
              ? localSavedName
              : null);

      if (resolvedName != null && resolvedName.isNotEmpty && resolvedHandle.isNotEmpty) {
        NameCacheService.instance.setCachedName(resolvedHandle, resolvedName);
      }

      if (mounted) {
        setState(() {
          _userData = {
            ...?_userData,
            'handle': resolvedHandle,
            'displayName': resolvedName,
            'name': resolvedName,
            'phone': rawPhone,
            if (cloudProfile?['bio'] != null) 'bio': cloudProfile!['bio'],
            if (cloudProfile?['isVerified'] != null) 'isVerified': cloudProfile!['isVerified'],
            'photoUrl': (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
            if (cloudProfile?['reputation'] != null) 'reputation': cloudProfile!['reputation'],
            if (cloudProfile?['upvotes'] != null) 'upvotes': cloudProfile!['upvotes'],
            if (cloudProfile?['friendCount'] != null) 'friendCount': cloudProfile!['friendCount'],
            if (cloudProfile?['nameUpdatedAt'] != null) 'nameUpdatedAt': cloudProfile!['nameUpdatedAt'],
            if (cloudProfile?['name_updated_at'] != null) 'nameUpdatedAt': cloudProfile!['name_updated_at'],
            if (cloudProfile?['handleUpdatedAt'] != null) 'handleUpdatedAt': cloudProfile!['handleUpdatedAt'],
            if (cloudProfile?['handle_updated_at'] != null) 'handleUpdatedAt': cloudProfile!['handle_updated_at'],
            if (cloudProfile?['canChangeName'] != null) 'canChangeName': cloudProfile!['canChangeName'],
            if (cloudProfile?['can_change_name'] != null) 'canChangeName': cloudProfile!['can_change_name'],
            if (cloudProfile?['canChangeHandle'] != null) 'canChangeHandle': cloudProfile!['canChangeHandle'],
            if (cloudProfile?['can_change_handle'] != null) 'canChangeHandle': cloudProfile!['can_change_handle'],
            if (cloudProfile?['nameDaysRemaining'] != null) 'nameDaysRemaining': cloudProfile!['nameDaysRemaining'],
            if (cloudProfile?['name_days_remaining'] != null) 'nameDaysRemaining': cloudProfile!['name_days_remaining'],
            if (cloudProfile?['handleDaysRemaining'] != null) 'handleDaysRemaining': cloudProfile!['handleDaysRemaining'],
            if (cloudProfile?['handle_days_remaining'] != null) 'handleDaysRemaining': cloudProfile!['handle_days_remaining'],
            if (cloudProfile?['nextNameChangeAt'] != null) 'nextNameChangeAt': cloudProfile!['nextNameChangeAt'],
            if (cloudProfile?['next_name_change_at'] != null) 'nextNameChangeAt': cloudProfile!['next_name_change_at'],
            if (cloudProfile?['nextHandleChangeAt'] != null) 'nextHandleChangeAt': cloudProfile!['nextHandleChangeAt'],
            if (cloudProfile?['next_handle_change_at'] != null) 'nextHandleChangeAt': cloudProfile!['next_handle_change_at'],
          };
          if (!_isSavingBio && (_bioController.text.isEmpty || _bioController.text == _userData!['bio'])) {
            _bioController.text = (_userData!['bio'] as String?) ?? '';
          }
          if (_nameController.text.isEmpty && resolvedName != null && resolvedName.isNotEmpty) {
            _nameController.text = resolvedName;
          }
          if (_handleController.text.isEmpty && resolvedHandle.isNotEmpty) {
            _handleController.text = resolvedHandle.replaceAll('@', '').trim();
          }
        });
      }

      final loc = widget.repository.locationService;
      final currentAreaId = loc.area?.id ?? loc.city.id;
      final results = await Future.wait([
        widget.repository.fetchPostsByUser(widget.currentUserHandle),
        BazarRepository.instance.fetchMyShop(),
        FoundingService.instance.fetchMyStatus(cityId: loc.city.id, areaId: currentAreaId),
        if (RewardsService.isRewardsEnabled)
          RewardsService.instance.fetchSummary(forceRefresh: true)
        else
          Future.value(null),
      ]);
      final freshPosts = results[0] as List<Post>;
      final shop = results[1] as dynamic;

      if (mounted) {
        setState(() {
          _userPosts = freshPosts;
          _myRegisteredShop = shop;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshProfile() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await _loadProfileData();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
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
        color: AppColors.surface,
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
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Change Profile Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.primary, size: 22),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                subtitle: const Text('Select a photo from your photo library', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
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
                    color: AppColors.chipBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: AppColors.textPrimary, size: 22),
                ),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                subtitle: const Text('Open camera to snap a new photo', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
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
                      color: AppColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.visibility_outlined, color: AppColors.primary, size: 22),
                  ),
                  title: const Text('View Profile Picture', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                  subtitle: const Text('See full size profile photo', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
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
                      color: AppColors.errorSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 22),
                  ),
                  title: const Text('Remove Current Picture', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.error)),
                  subtitle: const Text('Revert back to your initials avatar', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
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

      final croppedFile = await InstagramAvatarCropper.cropImage(
        context,
        imageFile: rawFile,
      );

      if (croppedFile == null) return;

      setState(() {
        _isUploadingPhoto = true;
        _userData?['photoUrl'] = croppedFile.path;
      });
      AvatarCacheService.instance.setCachedUrl(handle, croppedFile.path);

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
              backgroundColor: AppColors.primary,
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
              backgroundColor: AppColors.error,
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
            backgroundColor: AppColors.error,
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
            backgroundColor: AppColors.primary,
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
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  String _formatDateShort(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  Future<void> _saveProfile({
    required String newName,
    required String newHandle,
    required String newBio,
    required Function(String? error) onError,
  }) async {
    final cleanName = newName.trim();
    final cleanHandle = newHandle.replaceAll('@', '').trim().toLowerCase();
    final cleanBio = newBio.trim();

    if (cleanHandle.isEmpty) {
      onError('Username cannot be empty');
      return;
    }

    if (!RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(cleanHandle)) {
      onError('Username must be 3-30 characters (letters, numbers, underscores only)');
      return;
    }

    setState(() => _isSavingBio = true);
    try {
      final token = await AuthService.instance.getAccessToken();
      if (token != null && token.isNotEmpty) {
        final uri = Uri.parse('${AuthService.baseUrl}/profile');
        final response = await http.put(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'handle': cleanHandle,
            'displayName': cleanName.isNotEmpty ? cleanName : cleanHandle,
            'bio': cleanBio,
          }),
        ).timeout(const Duration(seconds: 25));

        final body = jsonDecode(response.body);

        if (response.statusCode == 409) {
          onError(body['error'] ?? 'Username $cleanHandle is already taken. Please choose another.');
          return;
        }

        if (response.statusCode != 200) {
          final err = body['error'] ?? body['message'] ?? 'Failed to update profile';
          onError(err.toString());
          return;
        }

        final profileData = body['profile'] as Map<String, dynamic>?;
        if (profileData != null) {
          _userData?['canChangeName'] = profileData['canChangeName'] ?? profileData['can_change_name'];
          _userData?['canChangeHandle'] = profileData['canChangeHandle'] ?? profileData['can_change_handle'];
          _userData?['nameDaysRemaining'] = profileData['nameDaysRemaining'] ?? profileData['name_days_remaining'];
          _userData?['handleDaysRemaining'] = profileData['handleDaysRemaining'] ?? profileData['handle_days_remaining'];
          _userData?['nameUpdatedAt'] = profileData['nameUpdatedAt'] ?? profileData['name_updated_at'];
          _userData?['handleUpdatedAt'] = profileData['handleUpdatedAt'] ?? profileData['handle_updated_at'];
          _userData?['nextNameChangeAt'] = profileData['nextNameChangeAt'] ?? profileData['next_name_change_at'];
          _userData?['nextHandleChangeAt'] = profileData['nextHandleChangeAt'] ?? profileData['next_handle_change_at'];
        }
      }

      await AuthService.instance.updateLocalUserCredentials(
        handle: cleanHandle,
        displayName: cleanName.isNotEmpty ? cleanName : null,
      );

      if (cleanName.isNotEmpty) {
        NameCacheService.instance.setCachedName(cleanHandle, cleanName);
        await NameCacheService.instance.saveMyNameLocally(cleanName);
      }

      final isVer = _userData?['isVerified'] == true || _userData?['is_verified'] == 1;
      final badge = (_userData?['authorBadge'] ?? _userData?['badge']) as String?;
      BadgeCacheService.instance.setBadge(cleanHandle, isVerified: isVer, badgeText: badge);

      widget.repository.currentUserHandle = cleanHandle;
      widget.repository.refresh();

      setState(() {
        if (_userData != null) {
          _userData!['handle'] = cleanHandle;
          _userData!['displayName'] = cleanName.isNotEmpty ? cleanName : cleanHandle;
          _userData!['name'] = cleanName.isNotEmpty ? cleanName : cleanHandle;
          _userData!['bio'] = cleanBio;
        }
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            content: Text('Profile updated successfully!'),
          ),
        );
      }
    } on TimeoutException {
      onError('Network request timed out. Please check your connection and tap Save changes again.');
    } on SocketException {
      onError('Unable to reach server. Please check your internet connection and try again.');
    } catch (e) {
      onError('Failed to save profile: $e');
    } finally {
      if (mounted) setState(() => _isSavingBio = false);
    }
  }

  void _showEditProfileSheet() {
    final currentName = (_userData?['displayName'] ?? _userData?['name'] ?? NameCacheService.instance.getMyNameLocally()) as String?;
    if (currentName != null && currentName.isNotEmpty) {
      _nameController.text = currentName;
    }
    final currentHandle = (_userData?['handle'] ?? widget.currentUserHandle).toString().replaceAll('@', '').trim();
    if (currentHandle.isNotEmpty) {
      _handleController.text = currentHandle;
    }
    _bioController.text = _userData?['bio'] ?? '';

    final initialName = (currentName ?? '').trim();
    final initialHandle = currentHandle.trim().toLowerCase();

    final nameUpdatedAtStr = _userData?['nameUpdatedAt'] ?? _userData?['name_updated_at'];
    final DateTime? nameUpdatedAt = nameUpdatedAtStr != null ? DateTime.tryParse(nameUpdatedAtStr.toString()) : null;
    const nameCooldown = Duration(days: 14);
    final bool isNameOnCooldown;
    final int nameDaysRemaining;
    final DateTime? nextNameChangeDate;

    if (nameUpdatedAt != null) {
      final elapsed = DateTime.now().difference(nameUpdatedAt);
      if (elapsed < nameCooldown) {
        isNameOnCooldown = true;
        nameDaysRemaining = (nameCooldown.inDays - elapsed.inDays).clamp(1, 14);
        nextNameChangeDate = nameUpdatedAt.add(nameCooldown);
      } else {
        isNameOnCooldown = false;
        nameDaysRemaining = 0;
        nextNameChangeDate = null;
      }
    } else {
      final rawCanChangeName = _userData?['canChangeName'] ?? _userData?['can_change_name'];
      final rawDaysRemaining = _userData?['nameDaysRemaining'] ?? _userData?['name_days_remaining'] ?? 0;
      if (rawCanChangeName == false && rawDaysRemaining > 0) {
        isNameOnCooldown = true;
        nameDaysRemaining = (rawDaysRemaining as num).toInt();
        nextNameChangeDate = DateTime.now().add(Duration(days: nameDaysRemaining));
      } else {
        isNameOnCooldown = false;
        nameDaysRemaining = 0;
        nextNameChangeDate = null;
      }
    }

    final handleUpdatedAtStr = _userData?['handleUpdatedAt'] ?? _userData?['handle_updated_at'];
    final DateTime? handleUpdatedAt = handleUpdatedAtStr != null ? DateTime.tryParse(handleUpdatedAtStr.toString()) : null;
    const handleCooldown = Duration(days: 30);
    final bool isHandleOnCooldown;
    final int handleDaysRemaining;
    final DateTime? nextHandleChangeDate;

    if (handleUpdatedAt != null) {
      final elapsed = DateTime.now().difference(handleUpdatedAt);
      if (elapsed < handleCooldown) {
        isHandleOnCooldown = true;
        handleDaysRemaining = (handleCooldown.inDays - elapsed.inDays).clamp(1, 30);
        nextHandleChangeDate = handleUpdatedAt.add(handleCooldown);
      } else {
        isHandleOnCooldown = false;
        handleDaysRemaining = 0;
        nextHandleChangeDate = null;
      }
    } else {
      final rawCanChangeHandle = _userData?['canChangeHandle'] ?? _userData?['can_change_handle'];
      final rawDaysRemaining = _userData?['handleDaysRemaining'] ?? _userData?['handle_days_remaining'] ?? 0;
      if (rawCanChangeHandle == false && rawDaysRemaining > 0) {
        isHandleOnCooldown = true;
        handleDaysRemaining = (rawDaysRemaining as num).toInt();
        nextHandleChangeDate = DateTime.now().add(Duration(days: handleDaysRemaining));
      } else {
        isHandleOnCooldown = false;
        handleDaysRemaining = 0;
        nextHandleChangeDate = null;
      }
    }

    const quickBioTags = [
      '+ Friendly neighbour',
      '+ Shop owner',
      '+ New here',
      '+ Pet lover',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String? inlineError;

        return StatefulBuilder(
          builder: (modalContext, setSheetState) {
            final textLength = _bioController.text.length;
            final progressRatio = (textLength / 200).clamp(0.0, 1.0);
            final activeHandle = (_userData?['handle'] ?? widget.currentUserHandle).toString();
            final currentPhoto = _userData?['photoUrl'] as String?;

            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(color: AppColors.divider, width: 1.2),
                ),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit profile',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 22),
                          onPressed: () => Navigator.pop(modalContext),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Stack(
                        children: [
                          UserAvatar(
                            handle: activeHandle,
                            photoUrl: currentPhoto,
                            size: 76,
                            fontSize: 26,
                            onTap: () {
                              Navigator.pop(modalContext);
                              _showChangeProfilePhotoSheet();
                            },
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(modalContext);
                                _showChangeProfilePhotoSheet();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(modalContext);
                          _showChangeProfilePhotoSheet();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text(
                          'Change photo',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Full Name',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isNameOnCooldown)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.schedule_rounded, color: Color(0xFFB45309), size: 11),
                                const SizedBox(width: 4),
                                Text(
                                  '$nameDaysRemaining days left',
                                  style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: (inlineError != null && inlineError!.toLowerCase().contains('name'))
                              ? AppColors.error
                              : AppColors.divider,
                          width: 1.2,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      child: TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 50,
                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.person_outline_rounded, color: AppColors.textMuted, size: 20),
                          prefixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
                          hintText: 'Your name (e.g. Rajesh Varma)',
                          hintStyle: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                        onChanged: (val) {
                          final clean = val.trim();
                          if (isNameOnCooldown && clean.isNotEmpty && clean.toLowerCase() != initialName.toLowerCase()) {
                            setSheetState(() {
                              inlineError = 'Full name can only be changed once every 14 days. Next change in $nameDaysRemaining day(s).';
                            });
                          } else if (inlineError != null && inlineError!.toLowerCase().contains('name')) {
                            setSheetState(() => inlineError = null);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isNameOnCooldown)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          'Full name can only be changed once every 14 days. Available in $nameDaysRemaining day(s)${nextNameChangeDate != null ? ' (${_formatDateShort(nextNameChangeDate)})' : ''}.',
                          style: const TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Row(
                          children: const [
                            Icon(Icons.info_outline_rounded, color: AppColors.textMuted, size: 12),
                            SizedBox(width: 4),
                            Text(
                              'You can change your full name once every 14 days.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Username',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isHandleOnCooldown)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.schedule_rounded, color: Color(0xFFB45309), size: 11),
                                const SizedBox(width: 4),
                                Text(
                                  '$handleDaysRemaining days left',
                                  style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: (inlineError != null && inlineError!.toLowerCase().contains('username'))
                              ? AppColors.error
                              : AppColors.divider,
                          width: 1.2,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      child: TextField(
                        controller: _handleController,
                        keyboardType: TextInputType.text,
                        maxLength: 30,
                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.alternate_email_rounded, color: AppColors.primary, size: 20),
                          prefixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
                          hintText: 'username',
                          hintStyle: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        onChanged: (val) {
                          final clean = val.replaceAll('@', '').toLowerCase();
                          if (clean != val) {
                            _handleController.value = TextEditingValue(
                              text: clean,
                              selection: TextSelection.collapsed(offset: clean.length),
                            );
                          }
                          if (isHandleOnCooldown && clean.isNotEmpty && clean != initialHandle) {
                            setSheetState(() {
                              inlineError = 'Username can only be changed once every 30 days. Next change in $handleDaysRemaining day(s).';
                            });
                          } else if (inlineError != null && inlineError!.toLowerCase().contains('username')) {
                            setSheetState(() => inlineError = null);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isHandleOnCooldown)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          'Username can only be changed once every 30 days (1 month). Available in $handleDaysRemaining day(s)${nextHandleChangeDate != null ? ' (${_formatDateShort(nextHandleChangeDate)})' : ''}.',
                          style: const TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Row(
                          children: const [
                            Icon(Icons.info_outline_rounded, color: AppColors.textMuted, size: 12),
                            SizedBox(width: 4),
                            Text(
                              'You can change your username once every 30 days (1 month).',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Bio',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.divider,
                          width: 1.2,
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _bioController,
                            maxLines: 3,
                            maxLength: 200,
                            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14.5,
                              height: 1.4,
                              fontWeight: FontWeight.w400,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Apne pados ko batao aap kaun ho...',
                              hintStyle: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                              ),
                            ),
                            onChanged: (_) {
                              setSheetState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: SizedBox(
                                  width: 80,
                                  height: 3.5,
                                  child: LinearProgressIndicator(
                                    value: progressRatio,
                                    backgroundColor: AppColors.divider,
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                  ),
                                ),
                              ),
                              Text(
                                '$textLength/200',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: quickBioTags.map((tag) {
                        return GestureDetector(
                          onTap: () {
                            final cleanTag = tag.replaceFirst('+ ', '').trim();
                            final current = _bioController.text.trim();
                            if (current.isEmpty) {
                              _bioController.text = cleanTag;
                            } else if (!current.toLowerCase().contains(cleanTag.toLowerCase())) {
                              final candidate = '$current, $cleanTag';
                              _bioController.text = candidate.length > 200
                                  ? candidate.substring(0, 200)
                                  : candidate;
                            }
                            _bioController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _bioController.text.length),
                            );
                            setSheetState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.chipBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.divider,
                                width: 1.1,
                              ),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (inlineError != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFF87171).withValues(alpha: 0.6),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                inlineError!,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: AppColors.chipBg,
                                foregroundColor: AppColors.textPrimary,
                                side: const BorderSide(color: AppColors.divider, width: 1.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => Navigator.pop(modalContext),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _isSavingBio
                                  ? null
                                  : () async {
                                      final typedName = _nameController.text.trim();
                                      final typedHandle = _handleController.text.replaceAll('@', '').trim().toLowerCase();

                                      if (typedName.isNotEmpty && typedName.toLowerCase() != initialName.toLowerCase() && isNameOnCooldown) {
                                        setSheetState(() {
                                          inlineError = 'Full name can only be changed once every 14 days. You can change it again in $nameDaysRemaining day(s).';
                                        });
                                        return;
                                      }

                                      if (typedHandle.isNotEmpty && typedHandle != initialHandle && isHandleOnCooldown) {
                                        setSheetState(() {
                                          inlineError = 'Username can only be changed once every 30 days. You can change it again in $handleDaysRemaining day(s).';
                                        });
                                        return;
                                      }

                                      setSheetState(() => _isSavingBio = true);
                                      await _saveProfile(
                                        newName: _nameController.text,
                                        newHandle: _handleController.text,
                                        newBio: _bioController.text,
                                        onError: (err) {
                                          if (mounted) {
                                            setSheetState(() {
                                              inlineError = err;
                                              _isSavingBio = false;
                                            });
                                          }
                                        },
                                      );
                                      if (mounted) {
                                        setSheetState(() => _isSavingBio = false);
                                      }
                                    },
                              child: _isSavingBio
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Text(
                                      'Save changes',
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMyQrModal() {
    final handle = _userData?['handle'] ?? widget.currentUserHandle;
    final cleanHandle = handle.toString().replaceAll('@', '').trim();
    final profileUrl = 'https://nearhood.in/u/$cleanHandle';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD3E7E9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'My Nearhood QR',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF16243A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              getDisplayName(cleanHandle),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 180,
              height: 180,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD3E7E9), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9F3F4),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.qr_code_2_rounded,
                        size: 88,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Scan in Nearhood',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF16243A).withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD3E7E9), width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF16243A))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Share Link', style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        SharePlus.instance.share(
                          ShareParams(
                            text: 'Connect with ${getDisplayName(cleanHandle)} on Nearhood: $profileUrl',
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    final userHandle = (_userData?['handle'] as String?) ?? widget.currentUserHandle;
    final phone = _userData?['phone'] as String?;
    final userEmail = _userData?['email'] as String?;
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
    final clean = userHandle.replaceAll('@', '').trim();
    final profile = UserProfile(
      handle: clean,
      displayName: (_userData?['name'] ?? _userData?['displayName']) as String? ??
          NameCacheService.instance.getCachedName(clean),
      phone: (phone == null || phone.isEmpty) ? null : phone,
      email: (userEmail == null || userEmail.isEmpty) ? null : userEmail,
      joinedYear: joinedDate?.year ?? DateTime.now().year,
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
  }

  void _shareProfile() {
    final handle = _userData?['handle'] ?? widget.currentUserHandle;
    SharePlus.instance.share(
      ShareParams(
        text: 'Connect with ${getDisplayName(handle)} on Nearhood — the local community app for Vadodara!',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final handle = _userData?['handle'] ?? widget.currentUserHandle;
    final bio = _userData?['bio'] ?? '';

    final headerHeight = MediaQuery.of(context).padding.top + 195.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF11383D),
        body: ListenableBuilder(
          listenable: Listenable.merge([widget.repository, widget.repository.locationService]),
          builder: (context, _) {
            final areaLabel = widget.repository.locationService.displayLabel;
            final cleanHandle = handle.toString().replaceAll('@', '').trim();
            final rawName = (_userData?['name'] ?? _userData?['displayName'] ?? _userData?['fullName']) as String?;
            final cachedName = NameCacheService.instance.getCachedName(cleanHandle);
            final effectiveName = (rawName != null && rawName.trim().isNotEmpty && !NameCacheService.isPlaceholderName(rawName))
                ? rawName.trim()
                : ((cachedName != null && cachedName.trim().isNotEmpty && !NameCacheService.isPlaceholderName(cachedName))
                    ? cachedName.trim()
                    : null);

            final primaryTitle = effectiveName ?? (cleanHandle.isNotEmpty ? cleanHandle : 'Neighbour');
            final isVerified = _userData?['isVerified'] == true || _userData?['is_verified'] == 1;

            return RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: Colors.white,
              onRefresh: _refreshProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Stack(
                  children: [
                    SizedBox(
                      height: headerHeight,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/images/nearhood_profile_city_header.webp',
                            fit: BoxFit.cover,
                            alignment: Alignment.bottomCenter,
                            color: AppColors.primary,
                            colorBlendMode: BlendMode.color,
                            errorBuilder: (context, error, stackTrace) => Image.memory(
                              getProfileHeaderBytes(),
                              fit: BoxFit.cover,
                              alignment: Alignment.bottomCenter,
                            color: AppColors.primary,
                            colorBlendMode: BlendMode.color,
                              errorBuilder: (context, error, stackTrace) => Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF3A0F34), Color(0xFF240820)],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withValues(alpha: 0.35),
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.22),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: const [0.0, 0.45, 1.0],
                                ),
                              ),
                            ),
                          ),
                          SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (Navigator.canPop(context)) ...[
                                          GestureDetector(
                                            onTap: () => Navigator.pop(context),
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              margin: const EdgeInsets.only(right: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.25),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white.withValues(alpha: 0.28),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.arrow_back_rounded,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                        GestureDetector(
                                          onTap: () async {
                                            final updated = await Navigator.push<bool>(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => AreaChangeRequestScreen(
                                                  repository: widget.repository,
                                                ),
                                              ),
                                            );
                                            if (updated == true && mounted) {
                                              setState(() {});
                                              widget.repository.refresh();
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.22),
                                              borderRadius: BorderRadius.circular(22),
                                              border: Border.all(
                                                color: Colors.white.withValues(alpha: 0.30),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.location_on_rounded,
                                                  size: 15,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 6),
                                                ConstrainedBox(
                                                  constraints: const BoxConstraints(maxWidth: 170),
                                                  child: Text(
                                                    areaLabel.isNotEmpty ? areaLabel : 'Vadodara',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w700,
                                                      color: Colors.white,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: _shareProfile,
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.22),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white.withValues(alpha: 0.30),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.share_outlined,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: _openSettings,
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.22),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white.withValues(alpha: 0.30),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.settings_outlined,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: headerHeight - 28),
                      child: Container(
                        width: double.infinity,
                        constraints: BoxConstraints(
                          minHeight: MediaQuery.of(context).size.height - (headerHeight - 28),
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(28),
                            topRight: Radius.circular(28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x180F172A),
                              blurRadius: 18,
                              offset: Offset(0, -6),
                            ),
                          ],
                        ),
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 96 + MediaQuery.paddingOf(context).bottom),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.star_rounded,
                                        size: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    const Text(
                                      'NEARHOOD RESIDENT PASS',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                                ListenableBuilder(
                                  listenable: FoundingService.instance,
                                  builder: (context, _) {
                                    final foundingStatus = FoundingService.instance.myStatus;
                                    if (foundingStatus != null && foundingStatus.state == FoundingUserState.approved) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: const Color(0xFFF59E0B),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          '#${foundingStatus.seq ?? 1} FOUNDER',
                                          style: const TextStyle(
                                            color: Color(0xFFB45309),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      );
                                    }
                                    if (isVerified) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.primarySoft,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: AppColors.divider,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: const Text(
                                          'VERIFIED',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      );
                                    }
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFFE2E8F0),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: const Text(
                                        'ACTIVE MEMBER',
                                        style: TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 66,
                                  height: 66,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.center,
                                    children: [
                                      UserAvatar(
                                        handle: handle,
                                        photoUrl: _userData?['photoUrl'] as String?,
                                        size: 66,
                                        showRing: true,
                                        ringGradient: const LinearGradient(
                                          colors: [Color(0xFF3A0F34), Color(0xFF6B2562)],
                                        ),
                                        ringWidth: 2.2,
                                        ringGap: 1.2,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.08),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                        fontSize: 22,
                                        onTap: _isUploadingPhoto ? null : _showChangeProfilePhotoSheet,
                                      ),
                                      Positioned(
                                        bottom: -1,
                                        right: -1,
                                        child: GestureDetector(
                                          onTap: _isUploadingPhoto ? null : _showChangeProfilePhotoSheet,
                                          child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF59E0B),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 1.8,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.12),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt_rounded,
                                              color: Colors.white,
                                              size: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_isUploadingPhoto)
                                        Positioned.fill(
                                          child: ClipOval(
                                            child: Container(
                                              color: Colors.black54,
                                              child: const Center(
                                                child: SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    color: Colors.white,
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              primaryTitle,
                                              style: const TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF0F172A),
                                                letterSpacing: -0.3,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isVerified) ...[
                                            const SizedBox(width: 4),
                                            const Icon(
                                              Icons.verified_rounded,
                                              color: AppColors.primary,
                                              size: 16,
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (cleanHandle.isNotEmpty) ...[
                                        const SizedBox(height: 1.5),
                                        Text(
                                          '@$cleanHandle',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF64748B),
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 3),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: const BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              isVerified
                                                  ? 'Verified Citizen · ${widget.repository.locationService.city.name}'
                                                  : 'Resident · ${widget.repository.locationService.city.name}',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: Color(0xFF64748B),
                                                fontWeight: FontWeight.w500,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (bio.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                bio,
                                textAlign: TextAlign.left,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF475569),
                                  height: 1.3,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 42,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                      ),
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      label: const Text(
                                        'Edit profile',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      onPressed: _showEditProfileSheet,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SizedBox(
                                    height: 42,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: const Color(0xFF0F172A),
                                        side: const BorderSide(
                                          color: Color(0xFFE2E8F0),
                                          width: 1.2,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                      ),
                                      icon: const Icon(
                                        Icons.qr_code_2_rounded,
                                        size: 17,
                                        color: Color(0xFF0F172A),
                                      ),
                                      label: const Text(
                                        'My QR',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      onPressed: _showMyQrModal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Builder(
                        builder: (context) {
                                final bazarListings = BazarRepository.instance.getUserListingsCount(widget.currentUserHandle);
                                final postListings = _userPosts.where((p) =>
                                  p.category == PostCategory.shop ||
                                  p.category == PostCategory.rooms ||
                                  p.category == PostCategory.services ||
                                  p.category == PostCategory.events ||
                                  p.shopTitle != null ||
                                  p.roomTitle != null
                                ).length;
                                final listingsCount = bazarListings > 0 ? bazarListings : postListings;

                                return Row(
                                  children: [
                                    Expanded(
                                      child: _buildStatCard(
                                        count: '${_userPosts.length}',
                                        label: 'Posts',
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => MyPostsScreen(
                                                currentUserHandle: widget.currentUserHandle,
                                                repository: widget.repository,
                                              ),
                                            ),
                                          ).then((_) => _loadProfileData());
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildStatCard(
                                        count: '$listingsCount',
                                        label: 'Listings',
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => BazarScreen(
                                                initialShowMyListings: true,
                                                currentUserHandle: widget.currentUserHandle,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),

                                  ],
                                );
                              },
                            ),
                            if (RewardsService.isRewardsEnabled) ...[
                              const SizedBox(height: 12),
                              ListenableBuilder(
                                listenable: RewardsService.instance,
                                builder: (context, _) {
                                  final summary = RewardsService.instance.summary ?? const RewardsSummary();
                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => RewardsHubScreen(currentUserHandle: widget.currentUserHandle),
                                        ),
                                      ).then((_) => setState(() {}));
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: const Color(0xFFF59E0B), width: 1.0),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFF59E0B),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.star_rounded, color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Rewards',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF78350F),
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                Text(
                                                  '${summary.balance} pts · ${summary.streakCount}-day streak',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF92400E),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.chevron_right_rounded, color: Color(0xFFB45309), size: 18),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 12),
                            _buildFoundingCard(),
                            const SizedBox(height: 12),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildActionGridCard(
                                        icon: Icons.article_outlined,
                                        iconBgColor: const Color(0xFFF3E8FF),
                                        iconColor: const Color(0xFF9333EA),
                                        title: 'My posts',
                                        subtitle: '${_userPosts.length} ${_userPosts.length == 1 ? "post" : "posts"}',
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => MyPostsScreen(
                                                currentUserHandle: widget.currentUserHandle,
                                                repository: widget.repository,
                                              ),
                                            ),
                                          ).then((_) => _loadProfileData());
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildActionGridCard(
                                        icon: Icons.shopping_bag_outlined,
                                        iconBgColor: const Color(0xFFCCFBF1),
                                        iconColor: const Color(0xFF0D9488),
                                        title: 'My listings',
                                        subtitle: 'Manage your items',
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => BazarScreen(
                                                initialShowMyListings: true,
                                                currentUserHandle: widget.currentUserHandle,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildActionGridCard(
                                        icon: Icons.location_on_outlined,
                                        iconBgColor: const Color(0xFFFFF8E1),
                                        iconColor: const Color(0xFFD97706),
                                        title: 'Change area',
                                        subtitle: widget.repository.locationService.area?.name ?? widget.repository.locationService.city.name,
                                        onTap: () async {
                                          final updated = await Navigator.push<bool>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => AreaChangeRequestScreen(
                                                repository: widget.repository,
                                              ),
                                            ),
                                          );
                                          if (updated == true && mounted) {
                                            setState(() {});
                                            widget.repository.refresh();
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildDynamicShopCard(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String count,
    required String label,
    VoidCallback? onTap,
  }) {
    final card = Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            count,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }
    return card;
  }

  Widget _buildActionGridCard({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    Color? borderColor,
    double borderWidth = 1.2,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor ?? const Color(0xFFE2E8F0),
            width: borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 18,
              ),
            ),
            const SizedBox(height: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoundingCard() {
    final loc = widget.repository.locationService;

    return ListenableBuilder(
      listenable: FoundingService.instance,
      builder: (context, _) {
        final status = FoundingService.instance.myStatus;
        final resolvedCityName = loc.city.name.isNotEmpty
            ? loc.city.name
            : ((status?.cityName != null && status!.cityName!.isNotEmpty)
                ? status.cityName!
                : 'your city');
        final resolvedCityId = loc.city.id.isNotEmpty
            ? loc.city.id
            : ((status?.cityId != null && status!.cityId!.isNotEmpty)
                ? status.cityId!
                : 'GJ-VAD');
        final resolvedAreaId = loc.area?.id ??
            ((status?.areaId != null && status!.areaId!.isNotEmpty)
                ? status.areaId!
                : resolvedCityId);

        if (status == null) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    color: Color(0xFF94A3B8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Request Funding badge for $resolvedCityName',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Post once in $resolvedCityName to request · 0 posts',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20),
              ],
            ),
          );
        }

        if (status.state == FoundingUserState.approved) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Founding Neighbour #${status.seq ?? 1}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF78350F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$resolvedCityName · 1 of 100 city founders',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'PERMANENT',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        if (status.state == FoundingUserState.locked) {
          return GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Publish at least 1 post in $resolvedCityName to request the Founding Neighbour badge.'),
                  backgroundColor: AppColors.textPrimary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                      color: Color(0xFF94A3B8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Request Funding badge for $resolvedCityName',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Post once in $resolvedCityName to request · 0 posts',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20),
                ],
              ),
            ),
          );
        }

        if (status.state == FoundingUserState.pending) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    color: Color(0xFF64748B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request sent · $resolvedCityName',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Pending admin review · Queue active',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 20),
              ],
            ),
          );
        }

        if (status.state == FoundingUserState.rejected) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFECDD3), width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE11D48),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Founding request rejected',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF9F1239),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Reason: ${status.reason ?? "Requirements not met"}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFBE123C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: status.canReapply ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: status.canReapply
                        ? () => _submitFoundingRequest(resolvedCityId, resolvedAreaId, resolvedCityName)
                        : null,
                    child: Text(
                      status.canReapply ? 'Request again' : 'Request again in ${status.daysRemaining} days',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return GestureDetector(
          onTap: () => _submitFoundingRequest(resolvedCityId, resolvedAreaId, resolvedCityName),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    color: Color(0xFFD97706),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.stars_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request Founding badge for $resolvedCityName',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF78350F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'First come first serve · 100 spots in $resolvedCityName',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Request',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitFoundingRequest(String cityId, String? areaId, String cityName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Request Founding Badge', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5)),
        content: Text('Would you like to request the Founding Neighbour badge for $cityName? Only 100 Founding spots are available in $cityName.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final res = await FoundingService.instance.submitRequest(cityId: cityId, areaId: areaId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? ''),
            backgroundColor: res['success'] == true ? AppColors.primary : AppColors.error,
          ),
        );
        _loadProfileData();
      }
    }
  }

  Widget _buildDynamicShopCard() {
    final shop = _myRegisteredShop;
    final handle = (_userData?['handle'] as String?) ?? widget.currentUserHandle;

    if (shop == null) {
      return _buildActionGridCard(
        icon: Icons.storefront_rounded,
        iconBgColor: const Color(0xFFE6F2F3),
        iconColor: AppColors.primary,
        title: 'Register shop',
        subtitle: 'Start selling locally',
        borderColor: const Color(0xFFA1D1D5),
        borderWidth: 1.2,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegisterShopScreen()),
          ).then((_) => _loadProfileData());
        },
      );
    }

    if (shop.status == 'pending') {
      return _buildActionGridCard(
        icon: Icons.hourglass_top_rounded,
        iconBgColor: const Color(0xFFFEF3C7),
        iconColor: const Color(0xFFD97706),
        title: 'Shop under review',
        subtitle: shop.name.isNotEmpty ? shop.name : 'Under review',
        borderColor: const Color(0xFFF59E0B),
        borderWidth: 1.5,
        onTap: () {
          ShopStatusSheet.showUnderReview(
            context,
            shop: shop,
            userHandle: handle,
          );
        },
      );
    }

    if (shop.status == 'rejected') {
      return _buildActionGridCard(
        icon: Icons.highlight_off_rounded,
        iconBgColor: const Color(0xFFFEE2E2),
        iconColor: const Color(0xFFDC2626),
        title: 'Fix and resubmit',
        subtitle: shop.name.isNotEmpty ? shop.name : 'Action required',
        borderColor: const Color(0xFFEF4444),
        borderWidth: 1.5,
        onTap: () {
          ShopStatusSheet.showRejected(
            context,
            shop: shop,
            userHandle: handle,
            onReapplied: _loadProfileData,
          );
        },
      );
    }

    return _buildActionGridCard(
      icon: Icons.store_rounded,
      iconBgColor: const Color(0xFFE6F2F3),
      iconColor: AppColors.primary,
      title: 'My shop',
      subtitle: shop.name.isNotEmpty ? shop.name : 'Live in Bazar',
      borderColor: const Color(0xFFA1D1D5),
      borderWidth: 1.5,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MyShopDashboardScreen(
              initialShop: shop,
              currentUserHandle: widget.currentUserHandle,
            ),
          ),
        ).then((_) => _loadProfileData());
      },
    );
  }
}
