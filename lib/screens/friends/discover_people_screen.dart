import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/user_avatar.dart';
import '../../services/friend_repository.dart';
import '../../services/post_repository.dart';
import '../profile/other_user_profile_sheet.dart';

class DiscoverPeopleScreen extends StatefulWidget {
  final FriendRepository repository;
  final String currentUserHandle;

  const DiscoverPeopleScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<DiscoverPeopleScreen> createState() => _DiscoverPeopleScreenState();
}

class _DiscoverPeopleScreenState extends State<DiscoverPeopleScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  List<Map<String, dynamic>> _people = [];
  bool _isLoading = true;
  final Set<String> _loadingHandles = {};

  @override
  void initState() {
    super.initState();
    final clean = widget.currentUserHandle.replaceAll('@', '').trim();
    if (clean.isNotEmpty) {
      widget.repository.currentUserHandle = clean;
    }
    _loadPeople();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPeople({String query = ''}) async {
    setState(() => _isLoading = true);
    try {
      final results = await widget.repository.discoverPeople(query: query);
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
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _loadPeople(query: val.trim());
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
              ? 'You and @$handle are now friends! 🎉'
              : 'Friend request sent to @$handle',
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
        _showToast(message: 'You and @$handle are now friends! 🎉', isSuccess: true);
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
            color: const Color(0xFF0E525B),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: isSuccess ? const Color(0xFF14B8A6) : const Color(0xFF90B4B6),
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
      // Refresh current discover list after returning from profile sheet
      _loadPeople(query: _searchController.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Discover People',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Connect with Vadodara neighbors',
              style: TextStyle(
                color: Color(0xFF90B4B6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Search Input ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF072E33),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF0E4B52)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: const Color(0xFF14B8A6),
                decoration: InputDecoration(
                  hintText: 'Search people by name or @handle...',
                  hintStyle: const TextStyle(color: Color(0xFF90B4B6), fontSize: 13.5),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF90B4B6), size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF90B4B6), size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _loadPeople();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // ── People List ──
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF14B8A6),
              backgroundColor: const Color(0xFF072E33),
              onRefresh: () => _loadPeople(query: _searchController.text.trim()),
              child: _buildBody(),
            ),
          ),
        ],
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
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF072E33),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0E4B52)),
                  ),
                  child: Icon(
                    isSearching ? Icons.person_search_rounded : Icons.people_outline_rounded,
                    color: const Color(0xFF14B8A6),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isSearching ? 'No neighbors found' : 'No suggestions available',
                  style: const TextStyle(
                    color: Colors.white,
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
                        : 'New community members will appear here as they join.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF90B4B6),
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
        color: const Color(0xFF072E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0E4B52)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          UserAvatar(
            handle: handle,
            photoUrl: person['avatarUrl'] as String?,
            size: 50,
            fontSize: 18,
            onTap: () => _openUserProfile(handle),
          ),
          const SizedBox(width: 12),

          // User Info
          Expanded(
            child: GestureDetector(
              onTap: () => _openUserProfile(handle),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName.isNotEmpty ? displayName : handle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@$handle',
                    style: const TextStyle(
                      color: Color(0xFF14B8A6),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      bio,
                      style: const TextStyle(
                        color: Color(0xFF90B4B6),
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

          // Action Button
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
          color: const Color(0xFF0E525B),
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF14B8A6),
          ),
        ),
      );
    }

    switch (relationship) {
      case 'friends':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF0E525B).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.check_rounded, color: Color(0xFF14B8A6), size: 14),
              SizedBox(width: 4),
              Text(
                'Friends',
                style: TextStyle(
                  color: Color(0xFF14B8A6),
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
            side: const BorderSide(color: Color(0xFF0E525B)),
            shape: const StadiumBorder(),
          ),
          onPressed: () => _handleFriendAction(person),
          child: const Text(
            'Requested',
            style: TextStyle(
              color: Color(0xFF90B4B6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

      case 'requestReceivedByMe':
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
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
            backgroundColor: const Color(0xFF14B8A6),
            foregroundColor: Colors.black,
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
          color: const Color(0xFF072E33).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF0E4B52).withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}
