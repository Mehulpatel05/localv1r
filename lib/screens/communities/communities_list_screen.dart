import 'package:flutter/material.dart';
import '../../services/community_repository.dart';
import '../../models/community_model.dart';
import 'community_chat_screen.dart';
import 'create_community_screen.dart';
import 'discover_communities_screen.dart';

class CommunitiesListScreen extends StatefulWidget {
  final CommunityRepository repository;

  const CommunitiesListScreen({super.key, required this.repository});

  @override
  State<CommunitiesListScreen> createState() => _CommunitiesListScreenState();
}

class _CommunitiesListScreenState extends State<CommunitiesListScreen> {
  final Map<String, int> _unreadCounts = {};
  final TextEditingController _discoverSearchController = TextEditingController();
  String _discoverSearchQuery = '';
  int _discoverFilterIndex = 0; // 0: All, 1: Groups, 2: Channels, 3: Popular
  final Set<String> _joiningCommunityIds = {};

  @override
  void dispose() {
    _discoverSearchController.dispose();
    super.dispose();
  }

  Color _getCommunityColor(bool isChannel, String id) {
    if (isChannel) {
      return const Color(0xFF0F172A); // Sleek Charcoal Black for channels
    }
    final colors = [
      const Color(0xFF0F172A), // Charcoal Black
      const Color(0xFF1E293B), // Deep Slate
      const Color(0xFF334155), // Graphite
      const Color(0xFF18181B), // Zinc Black
      const Color(0xFF27272A), // Carbon
    ];
    final hash = id.codeUnits.fold(0, (prev, elem) => prev + elem);
    return colors[hash % colors.length];
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'C';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  String _formatMemberCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M members';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K members';
    } else {
      return '$count members';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: isDark ? Colors.black : Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Communities',
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: -0.4,
            ),
          ),
          bottom: TabBar(
            indicatorColor: isDark ? Colors.white : const Color(0xFF0F172A),
            labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
            unselectedLabelColor: const Color(0xFF64748B),
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Joined'),
              Tab(text: 'Discover'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildMyCommunitiesTab(),
            _buildDiscoverTab(),
          ],
        ),
        floatingActionButton: _buildFloatingCreateButton(),
      ),
    );
  }

  // ── MY COMMUNITIES TAB ──
  Widget _buildMyCommunitiesTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StreamBuilder<List<CommunityModel>>(
      stream: widget.repository.getUserCommunities(),
      builder: (context, snapshot) {
        // 1. Loading State (Image 3 - Panel 2)
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingSkeleton();
        }

        // 2. Error / Offline State (Image 3 - Panel 3)
        if (snapshot.hasError) {
          return _buildErrorState();
        }

        final communities = snapshot.data ?? [];

        // 3. Empty State (Image 3 - Panel 1)
        if (communities.isEmpty) {
          return _buildEmptyMyCommunitiesState();
        }

        // 4. Loaded List (Image 1)
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          color: isDark ? Colors.white : Colors.black,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(top: 12, bottom: 84, left: 16, right: 16),
            itemCount: communities.length,
            itemBuilder: (context, index) {
              return _buildMyCommunityCard(communities[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildMyCommunityCard(CommunityModel community) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarColor = _getCommunityColor(community.isChannel, community.id);
    final initials = _getInitials(community.name);
    final typeLabel = community.isChannel ? 'CHANNEL' : 'GROUP';

    // Fetch unread count asynchronously if not cached
    if (!_unreadCounts.containsKey(community.id)) {
      widget.repository.getUnreadCount(community.id).then((count) {
        if (mounted && count > 0) {
          setState(() {
            _unreadCounts[community.id] = count;
          });
        }
      });
    }

    final unread = _unreadCounts[community.id] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            setState(() {
              _unreadCounts[community.id] = 0;
            });
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CommunityChatScreen(
                  community: community,
                  repository: widget.repository,
                ),
              ),
            );
            if (mounted) setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                // Avatar initials circle
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: avatarColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + Type Badge
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              community.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                               color: isDark ? const Color(0xFF334155) : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              typeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),

                      // Member Count line
                      Text(
                        '$typeLabel • ${_formatMemberCount(community.memberCount)}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),

                      // Description Snippet
                      if (community.description.isNotEmpty)
                        Text(
                          community.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Unread Badge and Trailing Chevron
                if (unread > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF3B82F6),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── STATES: SKELETON, EMPTY, ERROR (Image 3) ──

  // Panel 2: Loading State Skeleton
  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 90,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Panel 1: Empty State (My Communities)
  Widget _buildEmptyMyCommunitiesState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Sleek monochrome circular illustration
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_rounded,
                    size: 52,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  Positioned(
                    right: 36,
                    top: 36,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.people_alt_rounded,
                        size: 18,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No communities yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Join a community or create your own.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 28),

            // Button 1: Discover Communities
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DiscoverCommunitiesScreen(
                        repository: widget.repository,
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Discover Communities',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Button 2: Create Community
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => _showCreateOptions(context),
                child: const Text(
                  'Create Community',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DISCOVER TAB ──
  Widget _buildDiscoverTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // Search & Filter Header
        Container(
          color: isDark ? Colors.black : Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              // Search Bar
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141414) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF94A3B8),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _discoverSearchController,
                        onChanged: (val) {
                          setState(() {
                            _discoverSearchQuery = val.trim().toLowerCase();
                          });
                        },
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search channels & groups...',
                          hintStyle: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (_discoverSearchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF94A3B8),
                          size: 18,
                        ),
                        onPressed: () {
                          _discoverSearchController.clear();
                          setState(() {
                            _discoverSearchQuery = '';
                          });
                        },
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Filter Pills Row (All, Groups, Channels, Popular)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildDiscoverFilterPill(0, 'All'),
                    const SizedBox(width: 8),
                    _buildDiscoverFilterPill(1, 'Groups'),
                    const SizedBox(width: 8),
                    _buildDiscoverFilterPill(2, 'Channels'),
                    const SizedBox(width: 8),
                    _buildDiscoverFilterPill(3, 'Popular'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Discover List Stream
        Expanded(
          child: StreamBuilder<Set<String>>(
            stream: widget.repository.getJoinedCommunityIds(),
            builder: (context, joinedSnap) {
              final joinedIds = joinedSnap.data ?? {};

              return StreamBuilder<List<CommunityModel>>(
                stream: widget.repository.getAllCommunities(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildLoadingSkeleton();
                  }

                  if (snapshot.hasError) {
                    return _buildErrorState();
                  }

                  var communities = (snapshot.data ?? [])
                      .where((c) => !joinedIds.contains(c.id))
                      .toList();

                  // Apply search query
                  if (_discoverSearchQuery.isNotEmpty) {
                    communities = communities.where((c) {
                      return c.name.toLowerCase().contains(_discoverSearchQuery) ||
                          c.description.toLowerCase().contains(_discoverSearchQuery);
                    }).toList();
                  }

                  // Apply filter pills
                  if (_discoverFilterIndex == 1) {
                    communities =
                        communities.where((c) => !c.isChannel).toList();
                  } else if (_discoverFilterIndex == 2) {
                    communities =
                        communities.where((c) => c.isChannel).toList();
                  } else if (_discoverFilterIndex == 3) {
                    communities.sort((a, b) =>
                        b.memberCount.compareTo(a.memberCount));
                  }

                  if (communities.isEmpty) {
                    final allJoined =
                        (snapshot.data ?? []).isNotEmpty && joinedIds.isNotEmpty;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              allJoined && _discoverSearchQuery.isEmpty
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.search_off_rounded,
                              size: 48,
                              color: allJoined && _discoverSearchQuery.isEmpty
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _discoverSearchQuery.isNotEmpty
                                  ? 'No matches for "$_discoverSearchQuery"'
                                  : (allJoined
                                      ? 'All Caught Up!'
                                      : 'No communities to discover'),
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _discoverSearchQuery.isNotEmpty
                                  ? 'Try searching for something else or create your own!'
                                  : (allJoined
                                      ? "You've joined all available communities in Vadodara!"
                                      : 'Create your own channel or group to connect with neighbors!'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.only(
                      top: 12,
                      bottom: 84,
                      left: 16,
                      right: 16,
                    ),
                    itemCount: communities.length,
                    itemBuilder: (context, index) {
                      final community = communities[index];
                      final isJoined = joinedIds.contains(community.id);
                      return _buildDiscoverCard(community, isJoined);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoverFilterPill(int index, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _discoverFilterIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _discoverFilterIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : const Color(0xFF0F172A))
              : (isDark ? const Color(0xFF141414) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                : (isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? (isDark ? Colors.black : Colors.white)
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoverCard(CommunityModel community, bool isJoined) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarColor = _getCommunityColor(community.isChannel, community.id);
    final initials = _getInitials(community.name);
    final typeLabel = community.isChannel ? 'CHANNEL' : 'GROUP';
    final isJoining = _joiningCommunityIds.contains(community.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row (Avatar + Title + Badge + Members)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: avatarColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          community.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                typeLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatMemberCount(community.memberCount),
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (community.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            community.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Bottom Full-Width Action Button (Join / Joined)
              SizedBox(
                width: double.infinity,
                height: 40,
                child: isJoined
                    ? OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CommunityChatScreen(
                                community: community,
                                repository: widget.repository,
                              ),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_rounded, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Joined',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.white : Colors.black,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          elevation: 0,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: isJoining
                            ? null
                            : () async {
                                setState(() {
                                  _joiningCommunityIds.add(community.id);
                                });
                                try {
                                  await widget.repository.joinCommunity(community.id);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(0xFF10B981),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        content: Text(
                                          'Joined "${community.name}"! Added to Joined tab.',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(0xFFEF4444),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        content: Text(
                                          'Failed to join: ${e.toString().replaceAll("Exception:", "").trim()}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _joiningCommunityIds.remove(community.id);
                                    });
                                  }
                                }
                              },
                        child: isJoining
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Join',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFEF2F2),
              ),
              child: const Center(
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 48,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Couldn't load communities",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 180,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Retry',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                onPressed: () {
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PANEL 4: CREATE COMMUNITY BOTTOM SHEET (Image 3) ──
  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Grabber
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'What do you want to create?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 16),

              // Option 1: GROUP
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final created = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreateCommunityScreen(
                            repository: widget.repository,
                            isChannel: false,
                          ),
                        ),
                      );
                      if (created == true && mounted) {
                        setState(() {});
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.people_alt_rounded,
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'GROUP',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Everyone can send messages',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF94A3B8),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Option 2: CHANNEL
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final created = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreateCommunityScreen(
                            repository: widget.repository,
                            isChannel: true,
                          ),
                        ),
                      );
                      if (created == true && mounted) {
                        setState(() {});
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.campaign_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'CHANNEL',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Only admins can broadcast',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF94A3B8),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingCreateButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        icon: const Icon(Icons.add, size: 20, color: Colors.white),
        label: const Text(
          'Create',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
        onPressed: () => _showCreateOptions(context),
      ),
    );
  }
}