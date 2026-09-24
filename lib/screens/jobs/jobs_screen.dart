import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/location/location_service.dart';
import '../../core/location/location_chip.dart';
import '../../core/constants/areas_and_categories.dart';
import '../../models/post_model.dart';
import '../../services/post_repository.dart';
import 'job_detail_screen.dart';
import 'jobs_post_screen.dart';
import 'widgets/job_card_widget.dart';

class JobsScreen extends StatefulWidget {
  final PostRepository repository;
  final String currentUserHandle;

  const JobsScreen({
    super.key,
    required this.repository,
    required this.currentUserHandle,
  });

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  late final PostRepository _localRepo;
  final TextEditingController _searchController = TextEditingController();
  
  String _searchQuery = '';
  String _selectedQuickFilter = 'Nearby'; // 'Nearby', 'Remote', 'Internship', 'Full-time'
  String _selectedEmploymentFilter = 'All'; // 'All', 'Full-time', 'Part-time', 'Freelance', 'Internship', 'Referral', 'Hiring'

  final List<String> _quickFilters = ['Nearby', 'Remote', 'Internship', 'Full-time'];
  final List<String> _employmentFilters = [
    'All',
    'Full-time',
    'Part-time',
    'Freelance',
    'Internship',
    'Referral',
    'Hiring',
  ];

  @override
  void initState() {
    super.initState();
    _localRepo = PostRepository(context.read<LocationService>());
    _localRepo.setCategory(PostCategory.jobs);
    _localRepo.addListener(_onRepoChanged);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _localRepo.removeListener(_onRepoChanged);
    _localRepo.dispose();
    super.dispose();
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  List<Post> _getFilteredPosts(List<Post> posts) {
    return posts.where((post) {
      final title = (post.jobTitle ?? '').toLowerCase();
      final company = (post.jobCompany ?? '').toLowerCase();
      final content = post.content.toLowerCase();
      final location = (post.jobLocation ?? '').toLowerCase();
      final type = (post.jobType ?? '').toLowerCase();

      // 1. Search Query Filter
      if (_searchQuery.isNotEmpty) {
        final matches = title.contains(_searchQuery) ||
            company.contains(_searchQuery) ||
            content.contains(_searchQuery) ||
            location.contains(_searchQuery);
        if (!matches) return false;
      }

      // 2. Quick Setup Filter
      if (_selectedQuickFilter == 'Remote') {
        if (!location.contains('remote') && !title.contains('remote')) return false;
      } else if (_selectedQuickFilter == 'Internship') {
        if (!type.contains('intern') && !title.contains('intern')) return false;
      } else if (_selectedQuickFilter == 'Full-time') {
        if (!type.contains('full')) return false;
      }

      // 3. Employment Type Filter
      if (_selectedEmploymentFilter != 'All') {
        final emp = _selectedEmploymentFilter.toLowerCase();
        if (!type.contains(emp) && !title.contains(emp)) return false;
      }

      return true;
    }).toList();
  }

  void _openPostJob() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobsPostScreen(
          repository: _localRepo,
          authorHandle: widget.currentUserHandle,
        ),
      ),
    );
    _localRepo.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allPosts = _localRepo.allPosts;
    final filteredPosts = _getFilteredPosts(allPosts);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Jobs & Hiring',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          const Center(child: LocationChip()),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.sync_rounded, color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B), size: 22),
            onPressed: () => _localRepo.refresh(),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark ? Colors.white : Colors.black,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: 'Post a Job',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.add_rounded, color: isDark ? Colors.black : Colors.white, size: 22),
              onPressed: _openPostJob,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _localRepo.refresh,
        color: isDark ? Colors.white : Colors.black,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Hero Headline & Intro (Image 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Find your next\nopportunity.',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        height: 1.15,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Discover jobs, internships, referrals and local hiring opportunities around you.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Search Bar (Image 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(fontSize: 14.5, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'Search jobs, skills or companies',
                      hintStyle: TextStyle(color: isDark ? const Color(0xFF6E6E6E) : const Color(0xFF94A3B8), fontSize: 14),
                      prefixIcon: Icon(Icons.search_rounded, color: isDark ? const Color(0xFF6E6E6E) : const Color(0xFF94A3B8), size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded, color: isDark ? const Color(0xFF6E6E6E) : const Color(0xFF94A3B8), size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Quick Filter Pills Row (Image 1)
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _quickFilters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = _quickFilters[index];
                    final isSelected = _selectedQuickFilter == filter;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedQuickFilter = isSelected ? 'Nearby' : filter;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4)),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isSelected
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          filter,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? (isDark ? Colors.black : Colors.white)
                                : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF475569)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              // Employment Filter Pills Row (Image 1 & 4)
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _employmentFilters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final emp = _employmentFilters[index];
                    final isSelected = _selectedEmploymentFilter == emp;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedEmploymentFilter = emp),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4)),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isSelected
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          emp,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? (isDark ? Colors.black : Colors.white)
                                : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF475569)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Section Title: Recommended for you (Image 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recommended for you',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (filteredPosts.isNotEmpty)
                      Text(
                        '${filteredPosts.length} available',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Body: Loading Skeleton, Empty State, or Job Cards List
              if (_localRepo.isLoading) ...[
                _buildSkeletonLoading(),
              ] else if (filteredPosts.isEmpty) ...[
                _buildEmptyState(),
              ] else ...[
                ...filteredPosts.map((post) {
                  return JobCardWidget(
                    post: post,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => JobDetailScreen(
                            post: post,
                            repository: _localRepo,
                            currentUserHandle: widget.currentUserHandle,
                          ),
                        ),
                      );
                    },
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 1. Loading Skeleton State (Image 4 Group 4)
  Widget _buildSkeletonLoading() {
    return Column(
      children: List.generate(3, (index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 160,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 100,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 220,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // 2. Empty State (Image 4 Group 5)
  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141414) : const Color(0xFFF4F4F4),
                shape: BoxShape.circle,
                border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6)),
              ),
              child: Icon(
                Icons.work_outline_rounded,
                size: 36,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No opportunities here yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Be the first to share a job, internship, hiring requirement or referral.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: isDark ? const Color(0xFF9A9A9A) : const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: const StadiumBorder(),
              ),
              onPressed: _openPostJob,
              child: const Text(
                'Post a Job',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
