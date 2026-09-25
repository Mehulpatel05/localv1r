import 'package:flutter/material.dart';
import '../../services/community_repository.dart';
import '../../models/community_model.dart';
import 'community_chat_screen.dart';
import 'community_info_screen.dart';
import 'create_community_screen.dart';
import 'explore_communities_screen.dart';

class CommunitiesListScreen extends StatefulWidget {
  final CommunityRepository repository;

  const CommunitiesListScreen({super.key, required this.repository});

  @override
  State<CommunitiesListScreen> createState() => _CommunitiesListScreenState();
}

class _CommunitiesListScreenState extends State<CommunitiesListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  int _selectedFilter = 0; // 0: All, 1: Groups, 2: Channels
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    widget.repository.fetchUserCommunities();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim().toLowerCase();
    });
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $period';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}';
    }
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
        title: Text(
          'Communities',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.travel_explore_rounded),
            color: textColor,
            iconSize: 26,
            tooltip: 'Explore Public Channels & Groups',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExploreCommunitiesScreen(repository: widget.repository),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'create_community_fab',
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        tooltip: 'Create Group or Channel',
        onPressed: () async {
          final created = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateCommunityScreen(repository: widget.repository),
            ),
          );
          if (created == true && mounted) {
            widget.repository.fetchUserCommunities();
          }
        },
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: Column(
        children: [
          // ── Always Visible Persistent Search Bar for Joined Communities ──
          Container(
            color: cardBg,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
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
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search joined channels & groups',
                            hintStyle: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
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

                // ── Filter Chips (All, Groups, Channels) ──
                Row(
                  children: [
                    _buildFilterChip(0, 'All'),
                    const SizedBox(width: 8),
                    _buildFilterChip(1, 'Groups'),
                    const SizedBox(width: 8),
                    _buildFilterChip(2, 'Channels'),
                  ],
                ),
              ],
            ),
          ),

          // ── Main Content ──
          Expanded(
            child: _buildJoinedList(isDark),
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
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : const Color(0xFF0F172A))
              : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? (isDark ? Colors.black : Colors.white)
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ── Joined Communities Stream ──
  Widget _buildJoinedList(bool isDark) {
    return StreamBuilder<List<CommunityModel>>(
      stream: widget.repository.getUserCommunities(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allJoined = snapshot.data ?? [];

        // Filter by search query if user typed in joined search bar
        var filtered = allJoined;
        if (_searchQuery.isNotEmpty) {
          filtered = filtered.where((c) {
            final nameMatch = c.name.toLowerCase().contains(_searchQuery);
            final userMatch = c.username != null && c.username!.toLowerCase().contains(_searchQuery);
            final descMatch = c.description.toLowerCase().contains(_searchQuery);
            return nameMatch || userMatch || descMatch;
          }).toList();
        }

        // Filter by Groups / Channels chip
        if (_selectedFilter == 1) {
          filtered = filtered.where((c) => !c.isChannel).toList();
        } else if (_selectedFilter == 2) {
          filtered = filtered.where((c) => c.isChannel).toList();
        }

        final unarchived = filtered.where((c) => !c.isArchived).toList();
        final archived = filtered.where((c) => c.isArchived).toList();

        if (unarchived.isEmpty && archived.isEmpty) {
          if (_searchQuery.isNotEmpty) {
            return _buildSearchJoinedEmptyState(isDark);
          }
          return _buildEmptyState(isDark);
        }

        return RefreshIndicator(
          onRefresh: () async {
            await widget.repository.fetchUserCommunities();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ...unarchived.map((c) => _buildCommunityRow(c, isDark)),

              // ── Collapsed Archived Section ──
              if (archived.isNotEmpty) ...[
                const Divider(height: 24, thickness: 1, indent: 16, endIndent: 16),
                InkWell(
                  onTap: () {
                    setState(() {
                      _showArchived = !_showArchived;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.archive_outlined,
                          size: 20,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Archived (${archived.length})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showArchived ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: const Color(0xFF94A3B8),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showArchived)
                  ...archived.map((c) => _buildCommunityRow(c, isDark, isArchivedRow: true)),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Row Item Matching Image 2 ──
  Widget _buildCommunityRow(CommunityModel community, bool isDark, {bool isArchivedRow = false}) {
    final typeStr = community.isChannel ? 'Channel' : 'Group';
    final memberStr = '${_formatMemberCount(community.memberCount)} ${community.isChannel ? 'subscribers' : 'members'}';
    final visStr = community.isPrivate ? 'Private' : 'Public';
    final subtitle = '$typeStr · $memberStr · $visStr';

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CommunityChatScreen(
              community: community,
              repository: widget.repository,
            ),
          ),
        );
        widget.repository.fetchUserCommunities();
      },
      onLongPress: () => _showQuickActionsSheet(community),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // ── Rounded Square Avatar ──
            _buildCommunityLogo(community, size: 52),
            const SizedBox(width: 14),

            // ── Name & Subtitle ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          community.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (community.isPrivate) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.lock_rounded,
                          size: 14,
                          color: Color(0xFF94A3B8),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    community.lastMessage ?? subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: community.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                      color: community.unreadCount > 0
                          ? (isDark ? Colors.white : const Color(0xFF0F172A))
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // ── Right Indicators: Timestamp + Badge / Mute ──
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTimestamp(community.lastMessageAt ?? community.createdAt),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: community.unreadCount > 0
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (community.isMuted)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.notifications_off_rounded,
                          size: 15,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    if (community.unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          community.unreadCount > 99 ? '99+' : '${community.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Rounded Square Avatar Generator ──
  Widget _buildCommunityLogo(CommunityModel community, {double size = 52}) {
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

  // ── Search Joined Empty State ──
  Widget _buildSearchJoinedEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 14),
            Text(
              'No joined chats match "$_searchQuery"',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Looking for a new channel or group to join?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF3B82F6)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.travel_explore_rounded, color: Color(0xFF3B82F6), size: 18),
              label: const Text('Explore Public Directory', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExploreCommunitiesScreen(repository: widget.repository),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Long-Press Quick Actions Bottom Sheet ──
  void _showQuickActionsSheet(CommunityModel community) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _buildCommunityLogo(community, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          community.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Mark as Read
                ListTile(
                  leading: const Icon(Icons.mark_chat_read_outlined),
                  title: const Text('Mark as Read'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.repository.markAsRead(community.id);
                  },
                ),

                // Mute / Unmute
                ListTile(
                  leading: Icon(community.isMuted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined),
                  title: Text(community.isMuted ? 'Unmute Notifications' : 'Mute Notifications'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (community.isMuted) {
                      widget.repository.muteCommunity(community.id, 0);
                    } else {
                      _showMuteDurationDialog(community);
                    }
                  },
                ),

                // Archive / Unarchive
                ListTile(
                  leading: Icon(community.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined),
                  title: Text(community.isArchived ? 'Unarchive' : 'Archive'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.repository.archiveCommunity(community.id, !community.isArchived);
                  },
                ),

                // Community Info
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Community Info'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommunityInfoScreen(
                          community: community,
                          repository: widget.repository,
                        ),
                      ),
                    );
                  },
                ),

                // Leave Community
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.red),
                  title: const Text('Leave Community', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmLeaveCommunity(community);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMuteDurationDialog(CommunityModel community) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Mute notifications for...'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              widget.repository.muteCommunity(community.id, now + 3600); // 1h
            },
            child: const Text('1 Hour'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              widget.repository.muteCommunity(community.id, now + 28800); // 8h
            },
            child: const Text('8 Hours'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              widget.repository.muteCommunity(community.id, now + 604800); // 1 week
            },
            child: const Text('1 Week'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              widget.repository.muteCommunity(community.id, -1); // Always
            },
            child: const Text('Always'),
          ),
        ],
      ),
    );
  }

  void _confirmLeaveCommunity(CommunityModel community) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave ${community.name}?'),
        content: Text(
          community.isOwner && community.memberCount > 1
              ? 'You are the owner of this community. You must transfer ownership to another member before leaving.'
              : 'Are you sure you want to leave this ${community.isChannel ? 'channel' : 'group'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (community.isOwner && community.memberCount > 1)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CommunityInfoScreen(
                      community: community,
                      repository: widget.repository,
                    ),
                  ),
                );
              },
              child: const Text('Transfer Ownership', style: TextStyle(color: Colors.white)),
            )
          else
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await widget.repository.leaveCommunity(community.id);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$e')),
                    );
                  }
                }
              },
              child: const Text('Leave'),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.groups_3_rounded,
                size: 48,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No communities joined yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search for public groups and channels or create your own!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () async {
                final created = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateCommunityScreen(repository: widget.repository),
                  ),
                );
                if (created == true && mounted) {
                  widget.repository.fetchUserCommunities();
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Community', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}