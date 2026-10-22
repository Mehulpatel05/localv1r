import 'package:flutter/material.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/founding_model.dart';
import '../../services/founding_service.dart';
import '../../theme/app_colors.dart';

class FoundingAdminScreen extends StatefulWidget {
  const FoundingAdminScreen({super.key});

  @override
  State<FoundingAdminScreen> createState() => _FoundingAdminScreenState();
}

class _FoundingAdminScreenState extends State<FoundingAdminScreen> {
  List<AdminFoundingCity> _cities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities() async {
    setState(() => _isLoading = true);
    final list = await FoundingService.instance.fetchAdminCities();
    if (mounted) {
      setState(() {
        _cities = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddCityDialog() async {
    final controller = TextEditingController();
    String selectedState = 'GJ';
    bool isSubmitting = false;

    final suggestions = [
      {'name': 'Surat', 'state': 'GJ'},
      {'name': 'Ahmedabad', 'state': 'GJ'},
      {'name': 'Rajkot', 'state': 'GJ'},
      {'name': 'Mumbai', 'state': 'MH'},
      {'name': 'Pune', 'state': 'MH'},
      {'name': 'Delhi', 'state': 'DL'},
      {'name': 'Bangalore', 'state': 'KA'},
      {'name': 'Hyderabad', 'state': 'TS'},
      {'name': 'Jaipur', 'state': 'RJ'},
      {'name': 'Indore', 'state': 'MP'},
      {'name': 'Lucknow', 'state': 'UP'},
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.location_city_rounded, color: Color(0xFF3A0F34), size: 24),
                SizedBox(width: 8),
                Text(
                  'Add City & Areas',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF16243A)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Localities and pin codes will be automatically generated and linked.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Popular Suggestions',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: suggestions.map((s) {
                      final isSelected = controller.text.toLowerCase() == s['name']!.toLowerCase();
                      return ChoiceChip(
                        label: Text(s['name']!),
                        selected: isSelected,
                        selectedColor: const Color(0xFFF7EAF5),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSelected ? const Color(0xFF3A0F34) : const Color(0xFF334155),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (selected) {
                          setDialogState(() {
                            controller.text = s['name']!;
                            selectedState = s['state']!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: 'City Name',
                      hintText: 'e.g. Surat, Mumbai, Pune',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3A0F34), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'State Code',
                      hintText: 'e.g. GJ, MH, DL, KA',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3A0F34), width: 1.5)),
                    ),
                    controller: TextEditingController(text: selectedState)..selection = TextSelection.collapsed(offset: selectedState.length),
                    onChanged: (val) => selectedState = val.toUpperCase().trim(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A0F34),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final name = controller.text.trim();
                        if (name.isEmpty) return;
                        final navigator = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);
                        setDialogState(() => isSubmitting = true);
                        final res = await FoundingService.instance.addCity(name, stateId: selectedState);
                        setDialogState(() => isSubmitting = false);
                        if (!mounted) return;
                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(res['message'] ?? (res['success'] == true ? 'City added!' : 'Failed')),
                            backgroundColor: res['success'] == true ? const Color(0xFF3A0F34) : Colors.red,
                          ),
                        );
                        if (res['success'] == true) {
                          _loadCities();
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Add City', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF16243A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Founding Badges · Admin',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF16243A),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_rounded, color: Color(0xFF3A0F34)),
            tooltip: 'Add City',
            onPressed: _showAddCityDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF3A0F34)),
            onPressed: _loadCities,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3A0F34)))
          : _cities.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadCities,
                  color: const Color(0xFF3A0F34),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _cities.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final city = _cities[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminFoundingRequestsScreen(
                                areaId: city.cityId,
                                areaName: city.name,
                              ),
                            ),
                          ).then((_) => _loadCities());
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: city.pendingCount > 0 ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.location_city_rounded,
                                  color: city.pendingCount > 0 ? const Color(0xFFD97706) : const Color(0xFF64748B),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      city.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF16243A),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Text(
                                          'Pending: ${city.pendingCount}',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: city.pendingCount > 0 ? const Color(0xFFD97706) : const Color(0xFF64748B),
                                          ),
                                        ),
                                        const Text(' · ', style: TextStyle(color: Color(0xFF94A3B8))),
                                        Text(
                                          'Approved: ${city.approvedCount}/100',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF3A0F34),
                                          ),
                                        ),
                                        const Text(' · ', style: TextStyle(color: Color(0xFF94A3B8))),
                                        Text(
                                          '${(100 - city.approvedCount).clamp(0, 100)} left',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: (100 - city.approvedCount) > 0 ? const Color(0xFF3A0F34) : const Color(0xFFE11D48),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (city.pendingCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                                  ),
                                  child: Text(
                                    '${city.pendingCount} new',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 22),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_off_rounded, size: 48, color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          const Text(
            'No cities configured',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF16243A)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loadCities,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class AdminFoundingAreasScreen extends StatefulWidget {
  final String cityId;
  final String cityName;

  const AdminFoundingAreasScreen({
    super.key,
    required this.cityId,
    required this.cityName,
  });

  @override
  State<AdminFoundingAreasScreen> createState() => _AdminFoundingAreasScreenState();
}

class _AdminFoundingAreasScreenState extends State<AdminFoundingAreasScreen> {
  List<AdminFoundingArea> _areas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    setState(() => _isLoading = true);
    final list = await FoundingService.instance.fetchAdminAreas(widget.cityId);
    if (mounted) {
      setState(() {
        _areas = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF16243A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text(
              'Areas',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF16243A),
              ),
            ),
            Text(
              widget.cityName,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF3A0F34)),
            onPressed: _loadAreas,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3A0F34)))
          : _areas.isEmpty
              ? const Center(child: Text('No areas found for this city.'))
              : RefreshIndicator(
                  onRefresh: _loadAreas,
                  color: const Color(0xFF3A0F34),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _areas.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final area = _areas[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminFoundingRequestsScreen(
                                areaId: area.areaId,
                                areaName: area.name,
                              ),
                            ),
                          ).then((_) => _loadAreas());
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      area.name,
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF16243A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Pending: ${area.pendingCount} · Approved: ${area.approvedCount}/100',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: area.pendingCount > 0 ? const Color(0xFFD97706) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (area.pendingCount > 0) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${area.pendingCount} pending',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class AdminFoundingRequestsScreen extends StatefulWidget {
  final String areaId;
  final String areaName;

  const AdminFoundingRequestsScreen({
    super.key,
    required this.areaId,
    required this.areaName,
  });

  @override
  State<AdminFoundingRequestsScreen> createState() => _AdminFoundingRequestsScreenState();
}

class _AdminFoundingRequestsScreenState extends State<AdminFoundingRequestsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AdminFoundingRequestItem> _pendingRequests = [];
  List<AdminFounderItem> _founders = [];
  List<AdminFoundingRequestItem> _rejectedRequests = [];
  int _approvedCount = 0;
  int _spotsLeft = 100;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final reqRes = await FoundingService.instance.fetchAdminRequests(widget.areaId);
    final foundersList = await FoundingService.instance.fetchAdminFounders(widget.areaId);
    final rejectedRes = await FoundingService.instance.fetchAdminRequests(widget.areaId, status: 'rejected');

    if (mounted) {
      setState(() {
        _pendingRequests = (reqRes['requests'] as List<AdminFoundingRequestItem>?) ?? [];
        _rejectedRequests = (rejectedRes['requests'] as List<AdminFoundingRequestItem>?) ?? [];
        _approvedCount = (reqRes['approvedCount'] as int?) ?? foundersList.length;
        _spotsLeft = (reqRes['spotsLeft'] as int?) ?? (100 - _approvedCount);
        _founders = foundersList;
        _isLoading = false;
      });
    }
  }

  Future<void> _approveOldest() async {
    if (_pendingRequests.isEmpty) return;
    final oldest = _pendingRequests.first;
    await _handleApprove(oldest, isOldest: true);
  }

  Future<void> _handleApprove(AdminFoundingRequestItem item, {bool isOldest = false}) async {
    if (_approvedCount >= 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot approve: All 100 spots are full!'), backgroundColor: AppColors.error),
      );
      return;
    }

    if (!isOldest && item.queueNumber > 1) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Skip earlier requests?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Text('You are approving #${item.queueNumber} (@${item.userId}) while earlier requests are still pending in the queue. Continue?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A0F34), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Approve anyway'),
            ),
          ],
        ),
      );
      if (shouldContinue != true) return;
    }

    final res = await FoundingService.instance.approveRequest(item.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Approved'),
          backgroundColor: res['success'] == true ? const Color(0xFF3A0F34) : AppColors.error,
        ),
      );
      _loadData();
    }
  }

  Future<void> _handleReject(AdminFoundingRequestItem item) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reject @${item.userId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter rejection reason (required):', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. Account not active in area, suspicious activity...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48), foregroundColor: Colors.white),
            onPressed: () {
              if (reasonController.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Reject Request'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final res = await FoundingService.instance.rejectRequest(item.id, reasonController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Rejected'),
            backgroundColor: res['success'] == true ? const Color(0xFFE11D48) : AppColors.error,
          ),
        );
        _loadData();
      }
    }
  }

  Future<void> _handleRemoveFounder(AdminFounderItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Founding Badge #${item.seq}?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to revoke the Founding Neighbour badge for @${item.userId}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove Badge'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final res = await FoundingService.instance.removeFounder(item.userId, widget.areaId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Badge removed'),
            backgroundColor: res['success'] == true ? const Color(0xFF3A0F34) : AppColors.error,
          ),
        );
        _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF16243A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              widget.areaName,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF16243A),
              ),
            ),
            Text(
              'Approved: $_approvedCount/100 · $_spotsLeft spots left',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _spotsLeft > 0 ? const Color(0xFF3A0F34) : const Color(0xFFE11D48),
              ),
            ),
          ],
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF3A0F34),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF3A0F34),
          tabs: [
            Tab(text: 'Pending (${_pendingRequests.length})'),
            Tab(text: 'Approved (${_founders.length})'),
            Tab(text: 'Revoked (${_rejectedRequests.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3A0F34)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPendingTab(),
                _buildFoundersTab(),
                _buildRejectedTab(),
              ],
            ),
    );
  }

  Widget _buildPendingTab() {
    if (_pendingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mark_email_read_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            const Text(
              'No pending requests for this area',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF16243A)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    final isSpotsFull = _approvedCount >= 100;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF3A0F34),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_pendingRequests.isNotEmpty && !isSpotsFull) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flash_on_rounded, color: Color(0xFFD97706), size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'First Come First Serve',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF78350F)),
                        ),
                        Text(
                          'Approve the oldest pending request in queue',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3A0F34),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: _approveOldest,
                    child: const Text('Approve Oldest', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (isSpotsFull) ...[
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECDD3), width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.block_rounded, color: Color(0xFFE11D48), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Spots full (100/100 reached). Cannot approve more requests.',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF9F1239)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          for (final item in _pendingRequests) ...[
            _buildRequestCard(item, isSpotsFull),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildRequestCard(AdminFoundingRequestItem item, bool isSpotsFull) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: item.queueNumber == 1 ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '#${item.queueNumber}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: item.queueNumber == 1 ? const Color(0xFFB45309) : const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              UserAvatar(
                handle: item.userId,
                photoUrl: item.avatarUrl,
                size: 38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF16243A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.areaName != null && item.areaName!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.areaName!,
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '@${item.userId}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Text(
                '${item.createdAt.day}/${item.createdAt.month} ${item.createdAt.hour}:${item.createdAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.article_outlined, size: 14, color: Color(0xFF64748B)),
                    SizedBox(width: 4),
                    Text(
                      'First Area Post Preview',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.firstPostPreview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE11D48),
                    side: const BorderSide(color: Color(0xFFFECDD3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => _handleReject(item),
                  child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSpotsFull ? const Color(0xFF94A3B8) : const Color(0xFF3A0F34),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: isSpotsFull ? null : () => _handleApprove(item, isOldest: item.queueNumber == 1),
                  child: Text(
                    isSpotsFull ? 'Spots Full' : (item.queueNumber == 1 ? 'Approve (#1)' : 'Approve'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFoundersTab() {
    if (_founders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.workspace_premium_outlined, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            const Text(
              'No approved founders yet',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF16243A)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF3A0F34),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _founders.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final founder = _founders[index];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '#${founder.seq}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                UserAvatar(
                  handle: founder.userId,
                  photoUrl: founder.avatarUrl,
                  size: 38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              founder.displayName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF16243A)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (founder.areaName != null && founder.areaName!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                founder.areaName!,
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '@${founder.userId}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove badge',
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE11D48), size: 20),
                  onPressed: () => _handleRemoveFounder(founder),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRejectedTab() {
    if (_rejectedRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            const Text(
              'No revoked or rejected requests',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF16243A)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    final isSpotsFull = _approvedCount >= 100;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF3A0F34),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _rejectedRequests.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _rejectedRequests[index];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFECDD3), width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECDD3), width: 0.8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cancel_outlined, size: 12, color: Color(0xFFE11D48)),
                          SizedBox(width: 4),
                          Text(
                            'Revoked / Rejected',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFE11D48)),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${item.createdAt.day}/${item.createdAt.month} ${item.createdAt.hour}:${item.createdAt.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    UserAvatar(
                      handle: item.userId,
                      photoUrl: item.avatarUrl,
                      size: 38,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF16243A)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (item.areaName != null && item.areaName!.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item.areaName!,
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '@${item.userId}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (item.reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Reason: ${item.reason}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9F1239), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSpotsFull ? const Color(0xFF94A3B8) : const Color(0xFF3A0F34),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: isSpotsFull ? null : () => _handleApprove(item),
                    child: Text(
                      isSpotsFull ? 'Spots Full' : 'Re-Approve & Restore Badge',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
