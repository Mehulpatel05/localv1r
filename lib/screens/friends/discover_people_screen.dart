import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/friend_repository.dart';
import '../../services/post_repository.dart';
import '../profile/other_user_profile_sheet.dart';
import '../../core/widgets/verified_badge.dart';
import '../../core/services/name_cache_service.dart';
import '../../theme/app_colors.dart';

class DiscoverPeopleScreen extends StatefulWidget {
  final FriendRepository repository;
  final String currentUserHandle;
  final String? initialQuery;

  const DiscoverPeopleScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
    this.initialQuery,
  });

  @override
  State<DiscoverPeopleScreen> createState() => _DiscoverPeopleScreenState();
}

class _DiscoverPeopleScreenState extends State<DiscoverPeopleScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  List<Map<String, dynamic>> _people = [];
  bool _isLoading = false;
  final Set<String> _loadingHandles = {};

  @override
  void initState() {
    super.initState();
    final clean = widget.currentUserHandle.replaceAll('@', '').trim();
    if (clean.isNotEmpty) {
      widget.repository.currentUserHandle = clean;
    }
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _searchController.text = initial;
      _loadPeople(query: initial);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPeople({String query = ''}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      if (mounted) {
        setState(() {
          _people = [];
          _isLoading = false;
        });
      }
      return;
    }
    setState(() => _isLoading = true);
    try {
      final results = await widget.repository.discoverPeople(query: cleanQuery);
      if (mounted) {
        setState(() {
          _people = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[DiscoverPeopleScreen] Error loading people: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _people = [];
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _loadPeople(query: trimmed);
    });
  }

  Future<void> _handleFriendAction(Map<String, dynamic> person) async {
    final handle = (person['handle'] as String? ?? '').replaceAll('@', '').trim();
    if (handle.isEmpty || _loadingHandles.contains(handle)) return;

    final currentRel = person['relationship'] as String? ?? 'none';

    setState(() => _loadingHandles.add(handle));

    try {
      if (currentRel == 'none') {
        final newRel = await widget.repository.sendFriendRequest(handle);
        setState(() {
          person['relationship'] = newRel == RelationshipStatus.friends
              ? 'friends'
              : 'requestSentByMe';
        });
        _showToast(
          message: newRel == RelationshipStatus.friends
              ? 'You and ${getDisplayName(handle)} are now friends! 🎉'
              : 'Friend request sent to ${getDisplayName(handle)}',
          isSuccess: true,
        );
      } else if (currentRel == 'requestSentByMe') {
        await widget.repository.cancelFriendRequest(handle);
        setState(() {
          person['relationship'] = 'none';
        });
        _showToast(message: 'Request cancelled', isSuccess: false);
      } else if (currentRel == 'requestReceivedByMe') {
        await widget.repository.acceptFriendRequest(handle);
        setState(() {
          person['relationship'] = 'friends';
        });
        _showToast(message: 'You and ${getDisplayName(handle)} are now friends! 🎉', isSuccess: true);
      }
      widget.repository.refreshAll().catchError((_) {});
    } catch (e) {
      _showToast(message: 'Action failed: $e', isSuccess: false);
    } finally {
      if (mounted) setState(() => _loadingHandles.remove(handle));
    }
  }

  void _showToast({required String message, required bool isSuccess}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: isSuccess ? AppColors.primary : AppColors.error,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openUserProfile(String handle) {
    showOtherUserProfileSheet(
      context,
      partnerHandle: handle,
      currentUserHandle: widget.currentUserHandle,
      repository: context.read<PostRepository>(),
    ).then((_) {
      if (_searchController.text.trim().isNotEmpty) {
        _loadPeople(query: _searchController.text.trim());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _searchController.text.isEmpty && !_searchFocusNode.hasFocus,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _searchController.clear();
        _searchFocusNode.unfocus();
        setState(() {
          _people = [];
          _isLoading = false;
        });
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () {
              if (_searchController.text.isNotEmpty || _searchFocusNode.hasFocus) {
                _searchController.clear();
                _searchFocusNode.unfocus();
                setState(() {
                  _people = [];
                  _isLoading = false;
                });
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Discover People',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Connect with Vadodara neighbors',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    hintText: 'Search people by name or @handle...',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _searchFocusNode.unfocus();
                              setState(() {
                                _people = [];
                                _isLoading = false;
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.surface,
                onRefresh: () async {
                  if (_searchController.text.trim().isNotEmpty) {
                    await _loadPeople(query: _searchController.text.trim());
                  }
                },
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildSkeletonLoader();
    }

    if (_people.isEmpty) {
      final isSearching = _searchController.text.trim().isNotEmpty;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.18),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Icon(
                    isSearching ? Icons.person_search_rounded : Icons.search_rounded,
                    color: AppColors.primary,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isSearching ? 'No neighbors found' : 'Search for neighbors',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    isSearching
                        ? 'Try searching with a different name or @handle'
                        : 'Type a name or @handle above to find and connect with people in your neighborhood.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
      itemCount: _people.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final person = _people[index];
        return _buildPersonCard(person);
      },
    );
  }

  Widget _buildPersonCard(Map<String, dynamic> person) {
    final handle = (person['handle'] as String? ?? '').replaceAll('@', '').trim();
    final displayName = (person['displayName'] as String? ?? handle).trim();
    final bio = (person['bio'] as String? ?? '').trim();
    final relationship = (person['relationship'] as String? ?? 'none');
    final isLoadingAction = _loadingHandles.contains(handle);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          UserAvatar(
            handle: handle,
            photoUrl: person['avatarUrl'] as String?,
            size: 50,
            fontSize: 18,
            onTap: () => _openUserProfile(handle),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: GestureDetector(
              onTap: () => _openUserProfile(handle),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          getDisplayName(handle, fallback: displayName),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      VerifiedBadge(
                        handle: handle,
                        isVerified: person['isVerified'] == true || person['is_verified'] == 1,
                        badgeText: (person['authorBadge'] ?? person['badge']) as String?,
                        size: 14,
                      ),
                    ],
                  ),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      bio,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          _buildActionButton(person, relationship, isLoadingAction),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    Map<String, dynamic> person,
    String relationship,
    bool isLoading,
  ) {
    if (isLoading) {
      return Container(
        width: 90,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.chipBg,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }

    switch (relationship) {
      case 'friends':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, color: AppColors.primaryText, size: 14),
              SizedBox(width: 4),
              Text(
                'Friends',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );

      case 'requestSentByMe':
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 36),
            side: const BorderSide(color: AppColors.divider),
            shape: const StadiumBorder(),
          ),
          onPressed: () => _handleFriendAction(person),
          child: const Text(
            'Requested',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

      case 'requestReceivedByMe':
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            minimumSize: const Size(0, 36),
            shape: const StadiumBorder(),
          ),
          onPressed: () => _handleFriendAction(person),
          child: const Text(
            'Accept',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

      default:
        return ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: const Size(0, 36),
            shape: const StadiumBorder(),
          ),
          icon: const Icon(Icons.person_add_rounded, size: 14),
          label: const Text(
            'Add Friend',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          onPressed: () => _handleFriendAction(person),
        );
    }
  }

  Widget _buildSkeletonLoader() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Container(
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.chipBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
      ),
    );
  }
}
