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

  // Bug #5 fixed: TabController dispose
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
      // Feature #12: FAB to create community
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
              title: const Text('Group', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Everyone can send messages'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateCommunityScreen(
                      repository: widget.repository,
                      isChannel: false,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEF4444),
                child: Icon(Icons.campaign, color: Colors.white),
              ),
              title: const Text('Channel', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Only admins can broadcast'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateCommunityScreen(
                      repository: widget.repository,
                      isChannel: true,
                    ),
                  ),
                );
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
        final communities = snapshot.data ?? [];
        if (communities.isEmpty) {
          return const Center(
            child: Text(
              // Bug #1 fixed: actual newline
              "You haven't joined any communities yet.\nGo to 'Discover' to find some!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          );
        }
        // Feature #16: Pull to refresh
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {}); // triggers stream rebuild
          },
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

  // Feature #13: Unread badge tile for My Communities
  Widget _buildMyTile(CommunityModel community) {
    return FutureBuilder<int>(
      future: widget.repository.getUnreadCount(community.id),
      builder: (context, unreadSnap) {
        final unread = unreadSnap.data ?? 0;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: community.isChannel
                ? const Color(0xFFEF4444)
                : const Color(0xFF3B82F6),
            child: Icon(
              community.isChannel ? Icons.campaign : Icons.group,
              color: Colors.white,
            ),
          ),
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
          onTap: () async {
            await widget.repository.markAsRead(community.id);
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityChatScreen(
                    repository: widget.repository,
                    community: community,
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildDiscover() {
    // Bug #4 fixed: getDiscoverCommunities filters already-joined ones
    return StreamBuilder<List<CommunityModel>>(
      stream: widget.repository.getDiscoverCommunities(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data ?? [];

        // Feature #8: Filter by search query
        final communities = _searchQuery.isEmpty
            ? all
            : all
                .where((c) =>
                    c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                    c.description
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()))
                .toList();

        return Column(
          children: [
            // Feature #8: Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search communities...',
                  hintStyle: const TextStyle(color: Colors.black38),
                  prefixIcon: const Icon(Icons.search, color: Colors.black38),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon:
                              const Icon(Icons.clear, color: Colors.black38),
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
                child: ListView.builder(
                  itemCount: communities.length,
                  itemBuilder: (context, index) {
                    return _buildCommunityTile(communities[index],
                        showJoinBadge: true);
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCommunityTile(CommunityModel community,
      {bool showJoinBadge = false}) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: community.isChannel
            ? const Color(0xFFEF4444)
            : const Color(0xFF3B82F6),
        child: Icon(
          community.isChannel ? Icons.campaign : Icons.group,
          color: Colors.white,
        ),
      ),
      title: Text(
        community.name,
        style: const TextStyle(
            color: Colors.black87, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        community.description,
        style: const TextStyle(color: Colors.black54),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: showJoinBadge
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            )
          : Text(
              '${community.memberCount} members',
              style: const TextStyle(color: Colors.black38, fontSize: 12),
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
}