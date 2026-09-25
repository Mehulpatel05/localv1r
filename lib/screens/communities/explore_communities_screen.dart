import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/community_model.dart';
import '../../services/community_repository.dart';
import 'community_chat_screen.dart';
import 'community_info_screen.dart';

class ExploreCommunitiesScreen extends StatefulWidget {
  final CommunityRepository repository;

  const ExploreCommunitiesScreen({super.key, required this.repository});

  @override
  State<ExploreCommunitiesScreen> createState() => _ExploreCommunitiesScreenState();
}

class _ExploreCommunitiesScreenState extends State<ExploreCommunitiesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  String _searchQuery = '';
  int _selectedFilter = 0; // 0: All, 1: Channels, 2: Groups
  bool _isLoading = false;

  List<CommunityModel> _publicCommunities = [];
  final Set<String> _joiningIds = {};

  @override
  void initState() {
    super.initState();
    widget.repository.fetchUserCommunities();
    _loadDirectory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory() async {
    setState(() => _isLoading = true);
    String? typeFilter;
    if (_selectedFilter == 1) typeFilter = 'channel';
    if (_selectedFilter == 2) typeFilter = 'group';

    final results = await widget.repository.fetchDiscoverCommunities(
      query: _searchQuery.isNotEmpty ? _searchQuery : null,
      type: typeFilter,
    );

    if (mounted) {
      setState(() {
        _publicCommunities = results;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final clean = query.trim();
      setState(() {
        _searchQuery = clean;
      });
      _loadDirectory();
    });
  }

  String _formatMemberCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Explore Public Channels',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: 19,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Search & Filter Header ──
          Container(
            color: cardBg,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              children: [
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF94A3B8),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search public channels & groups...',
                            hintStyle: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w400,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF94A3B8),
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Filter Chips (All, Channels, Groups) ──
                Row(
                  children: [
                    _buildFilterChip(0, 'All'),
                    const SizedBox(width: 8),
                    _buildFilterChip(1, 'Channels'),
                    const SizedBox(width: 8),
                    _buildFilterChip(2, 'Groups'),
                  ],
                ),
              ],
            ),
          ),

          // ── Results List ──
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _publicCommunities.isEmpty
                    ? _buildEmptyState(isDark)
                    : StreamBuilder<Set<String>>(
                        stream: widget.repository.getJoinedCommunityIds(),
                        initialData: widget.repository.joinedCommunityIds,
                        builder: (context, joinedSnapshot) {
                          final joinedIds = joinedSnapshot.data ?? {};
                          return ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            itemCount: _publicCommunities.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                              indent: 76,
                            ),
                            itemBuilder: (context, index) {
                              final comm = _publicCommunities[index];
                              final isJoined = joinedIds.contains(comm.id) || widget.repository.isMemberCached(comm.id);
                              return _buildPublicCommunityTile(comm, isJoined, isDark);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedFilter == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = index;
        });
        _loadDirectory();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF3B82F6)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildPublicCommunityTile(CommunityModel comm, bool isJoined, bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final isJoining = _joiningIds.contains(comm.id);

    return InkWell(
      onTap: () async {
        if (isJoined) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CommunityChatScreen(
                community: comm,
                repository: widget.repository,
              ),
            ),
          );
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CommunityInfoScreen(
                community: comm,
                repository: widget.repository,
              ),
            ),
          );
        }
        if (mounted) {
          setState(() {});
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _buildCustomGlyph(comm, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          comm.name,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: comm.isChannel ? const Color(0xFFDBEAFE) : const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          comm.isChannel ? 'CHANNEL' : 'GROUP',
                          style: TextStyle(
                            color: comm.isChannel ? const Color(0xFF1D4ED8) : const Color(0xFF15803D),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comm.description.isNotEmpty
                        ? comm.description
                        : '${_formatMemberCount(comm.memberCount)} ${comm.isChannel ? 'subscribers' : 'members'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // ── Join / View Button ──
            if (isJoined)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  minimumSize: const Size(64, 32),
                  side: const BorderSide(color: Color(0xFF3B82F6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommunityChatScreen(
                        community: comm,
                        repository: widget.repository,
                      ),
                    ),
                  );
                  if (mounted) {
                    setState(() {});
                  }
                },
                child: const Text('View', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF3B82F6))),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  minimumSize: const Size(64, 32),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: isJoining
                    ? null
                    : () async {
                        setState(() => _joiningIds.add(comm.id));
                        try {
                          final res = await widget.repository.joinCommunity(comm.id);
                          if (mounted) {
                            if (res.status == JoinStatus.pending) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Join request submitted for review!')),
                              );
                            } else if (res.status == JoinStatus.joined) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Joined ${comm.name}!')),
                              );
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CommunityChatScreen(
                                    community: comm,
                                    repository: widget.repository,
                                  ),
                                ),
                              );
                              if (mounted) {
                                _loadDirectory();
                              }
                            } else if (res.status == JoinStatus.error) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(res.message.isNotEmpty ? res.message : 'Failed to join community')),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to join: $e')),
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _joiningIds.remove(comm.id));
                          }
                        }
                      },
                child: isJoining
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Join', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomGlyph(CommunityModel community, {double size = 52}) {
    final isChannel = community.isChannel;
    final bgColor = isChannel ? const Color(0xFFE0F2FE) : const Color(0xFFDCFCE7);
    final iconColor = isChannel ? const Color(0xFF0284C7) : const Color(0xFF16A34A);
    final defaultIcon = isChannel ? Icons.campaign_rounded : Icons.group_rounded;

    if (community.imageUrl != null && community.imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          community.imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _buildFallbackBox(size, bgColor, defaultIcon, iconColor),
        ),
      );
    }

    return _buildFallbackBox(size, bgColor, defaultIcon, iconColor);
  }

  Widget _buildFallbackBox(double size, Color bgColor, IconData icon, Color iconColor) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        icon,
        color: iconColor,
        size: size * 0.52,
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.travel_explore_rounded,
              size: 56,
              color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 14),
            Text(
              _searchQuery.isNotEmpty ? 'No public channels or groups found' : 'Explore Public Channels',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try searching with different keywords.'
                  : 'Search across public channels and groups created by the community.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
