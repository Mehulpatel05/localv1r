import 'package:flutter/material.dart';
import '../../services/post_repository.dart';
import '../feed/feed_screen.dart';
import '../chat/chat_list_screen.dart';
import '../profile/profile_screen.dart';
import '../communities/communities_list_screen.dart';
import '../../services/community_repository.dart';

class MainScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const MainScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late final List<Widget> _screens;
  late final CommunityRepository _communityRepository;

  @override
  void initState() {
    super.initState();
    _communityRepository = CommunityRepository()..currentUserHandle = widget.currentUserHandle;
    _screens = [
      FeedScreen(
        repository: widget.repository,
        currentUserHandle: widget.currentUserHandle,
      ),
      CommunitiesListScreen(repository: _communityRepository),
      ChatListScreen(
        currentUserHandle: widget.currentUserHandle,
      ),
      ProfileScreen(
        repository: widget.repository,
        currentUserHandle: widget.currentUserHandle,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: Colors.black12, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                _buildNavItem(index: 0, icon: Icons.home_rounded, label: 'Home'),
                _buildNavItem(index: 1, icon: Icons.group_rounded, label: 'Communities'),
                _buildNavItem(index: 2, icon: Icons.chat_bubble_rounded, label: 'Chats'),
                _buildNavItem(index: 3, icon: Icons.person_rounded, label: 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    final selectedColor = const Color(0xFF3B82F6);
    final unselectedColor = Colors.black38;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  icon,
                  size: 24,
                  color: isSelected ? selectedColor : unselectedColor,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isSelected ? selectedColor : unselectedColor,
                  fontSize: isSelected ? 11 : 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
