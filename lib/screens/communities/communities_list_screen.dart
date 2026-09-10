import 'package:flutter/material.dart';
import '../../services/community_repository.dart';
import '../../models/community_model.dart';
import 'community_chat_screen.dart';
import 'create_community_screen.dart';

class CommunitiesListScreen extends StatefulWidget {
  final CommunityRepository repository;

  const CommunitiesListScreen({super.key, required this.repository});

  @override
  State<CommunitiesListScreen> createState() => _CommunitiesListScreenState();
}

class _CommunitiesListScreenState extends State<CommunitiesListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Communities',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF3B82F6),
          labelColor: const Color(0xFF3B82F6),
          unselectedLabelColor: Colors.black54,
          tabs: const [
            Tab(text: 'My Groups & Channels'),
            Tab(text: 'Discover'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF3B82F6),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Create', style: TextStyle(color: Colors.white)),
        onPressed: () => _showCreateOptions(context),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyCommunities(),
          _buildDiscover(),
        ],
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'What do you want to create?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF3B82F6),
                child: Icon(Icons.group, color: Colors.white),
              ),
              title: const Text('Group',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Everyone can send messages'),
              onTap: () async {
                Navigator.pop(context);
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateCommunityScreen(
                      repository: widget.repository,
                      isChannel: false,
                    ),
                  ),
                );
                // F7: Auto-switch to My Groups & Channels tab
                if (created == true && mounted) {
                  _tabController.animateTo(0);
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEF4444),
                child: Icon(Icons.campaign, color: Colors.white),
              ),
              title: const Text('Channel',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Only admins can broadcast'),
              onTap: () async {
                Navigator.pop(context);
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateCommunityScreen(
                      repository: widget.repository,
                      isChannel: true,
                    ),
                  ),
                );
                // F7: Auto-switch to My Groups & Channels tab
                if (created == true && mounted) {
                  _tabController.animateTo(0);
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMyCommunities() {
    return StreamBuilder<List<CommunityModel>>(
      stream: widget.repository.getUserCommunities(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        // F3: Error state — Firestore down ya permissions issue
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.black26),
                const SizedBox(height: 12),
                const Text('Could not load communities.',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final communities = snapshot.data ?? [];
        if (communities.isEmpty) {
          return const Center(
            child: Text(
              "You haven't joined any communities yet.\nGo to 'Discover' to find some!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: communities.length,
            itemBuilder: (context, index) {
              return _buildMyTile(communities[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildMyTile(CommunityModel community) {
    return FutureBuilder<int>(
      future: widget.repository.getUnreadCount(community.id),
      builder: (context, unreadSnap) {
        final unread = unreadSnap.data ?? 0;
        return ListTile(
          leading: _communityAvatar(community),
          title: Text(
            community.name,
            style: TextStyle(
              color: Colors.black87,
              fontWeight:
                  unread > 0 ? FontWeight.w800 : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            community.description,
            style: TextStyle(
              color: unread > 0 ? Colors.black87 : Colors.black54,
              fontWeight:
                  unread > 0 ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: unread > 0
              ? Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF3B82F6),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                )
              : Text(
                  '${community.memberCount} members',
                  style:
                      const TextStyle(color: Colors.black38, fontSize: 12),
                ),
          onTap: () {
            widget.repository.markAsRead(community.id);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CommunityChatScreen(
                  repository: widget.repository,
                  community: community,
                ),
              ),
            ).then((_) {
              if (mounted) setState(() {});
            });
          },
        );
      },
    );
  }

  Widget _buildDiscover() {
    return StreamBuilder<List<CommunityModel>>(
      stream: widget.repository.getDiscoverCommunities(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        // F3: Error state for Discover tab
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.black26),
                const SizedBox(height: 12),
                const Text('Could not load communities.',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final all = snapshot.data ?? [];
        final communities = _searchQuery.isEmpty
            ? all
            : all
                .where((c) =>
                    c.name
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()) ||
                    c.description
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()))
                .toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search communities...',
                  hintStyle: const TextStyle(color: Colors.black38),
                  prefixIcon:
                      const Icon(Icons.search, color: Colors.black38),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              color: Colors.black38),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),
            if (communities.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    "No communities found.\nTry a different search or create one!",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              )
            else
              Expanded(
                // F1: Pull to refresh in Discover tab
                child: RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: communities.length,
                    itemBuilder: (context, index) {
                      return _buildDiscoverTile(communities[index]);
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDiscoverTile(CommunityModel community) {
    final typeLabel = community.isChannel ? 'Channel' : 'Group';
    final memberText = community.memberCount == 1
        ? '1 member'
        : '${community.memberCount} members';

    return ListTile(
      // B4 fixed: use shared _communityAvatar so imageUrl shows in Discover too
      leading: _communityAvatar(community),
      title: Text(
        community.name,
        style: const TextStyle(
            color: Colors.black87, fontWeight: FontWeight.bold),
      ),
      // F2: Show type + member count + description
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: community.isChannel
                      ? const Color(0xFFFFEDE7)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    color: community.isChannel
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF3B82F6),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                memberText,
                style: const TextStyle(color: Colors.black45, fontSize: 11),
              ),
            ],
          ),
          if (community.description.isNotEmpty)
            Text(
              community.description,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      isThreeLine: community.description.isNotEmpty,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Join',
          style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold),
        ),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CommunityChatScreen(
              repository: widget.repository,
              community: community,
            ),
          ),
        );
      },
    );
  }

  Widget _communityAvatar(CommunityModel community) {
    final bg = community.isChannel ? const Color(0xFFEF4444) : const Color(0xFF3B82F6);
    if (community.imageUrl != null && community.imageUrl!.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: NetworkImage(community.imageUrl!),
        backgroundColor: bg,
      );
    }
    return CircleAvatar(
      backgroundColor: bg,
      child: Icon(
        community.isChannel ? Icons.campaign : Icons.group,
        color: Colors.white,
      ),
    );
  }
}