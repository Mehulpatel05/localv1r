import 'package:flutter/material.dart';
import '../../services/community_repository.dart';
import '../../models/community_model.dart';
import 'community_chat_screen.dart';

class CommunitiesListScreen extends StatefulWidget {
  final CommunityRepository repository;

  const CommunitiesListScreen({super.key, required this.repository});

  @override
  State<CommunitiesListScreen> createState() => _CommunitiesListScreenState();
}

class _CommunitiesListScreenState extends State<CommunitiesListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D30),
        title: const Text('Communities', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF3B82F6),
          labelColor: const Color(0xFF3B82F6),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'My Groups & Channels'),
            Tab(text: 'Discover'),
          ],
        ),
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
              "You haven't joined any communities yet.\\nGo to 'Discover' to find some!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        return ListView.builder(
          itemCount: communities.length,
          itemBuilder: (context, index) {
            return _buildCommunityTile(communities[index]);
          },
        );
      },
    );
  }

  Widget _buildDiscover() {
    return StreamBuilder<List<CommunityModel>>(
      stream: widget.repository.getAllCommunities(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final communities = snapshot.data ?? [];
        if (communities.isEmpty) {
          return const Center(
            child: Text(
              "No public communities yet.\\nCreate the first one!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        return ListView.builder(
          itemCount: communities.length,
          itemBuilder: (context, index) {
            return _buildCommunityTile(communities[index]);
          },
        );
      },
    );
  }

  Widget _buildCommunityTile(CommunityModel community) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: community.isChannel ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
        child: Icon(
          community.isChannel ? Icons.campaign : Icons.group,
          color: Colors.white,
        ),
      ),
      title: Text(community.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(
        community.description,
        style: const TextStyle(color: Colors.white54),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('${community.memberCount} members', style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
