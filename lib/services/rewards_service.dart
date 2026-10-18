import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/api_constants.dart';
import '../models/rewards_model.dart';
import 'auth_service.dart';

class RewardsService extends ChangeNotifier {
  static final RewardsService _instance = RewardsService._internal();
  factory RewardsService() => _instance;
  static RewardsService get instance => _instance;

  RewardsService._internal() {
    _loadCachedSummary();
  }

  Future<void> _loadCachedSummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_rewards_summary');
      if (raw != null && raw.isNotEmpty && _summary == null) {
        final data = jsonDecode(raw);
        if (data is Map<String, dynamic>) {
          _summary = RewardsSummary.fromJson(data);
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveCachedSummary(RewardsSummary summary) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {
        'balance': summary.balance,
        'lifetimePoints': summary.lifetimePoints,
        'weeklyPoints': summary.weeklyPoints,
        'streakCount': summary.streakCount,
        'streakAwarded': summary.streakAwarded,
        'dailyPointsToday': summary.dailyPointsToday,
        'dailyCap': summary.dailyCap,
        'isCapReached': summary.isCapReached,
        'referralCode': summary.referralCode,
        'highestHelpfulBadge': summary.highestHelpfulBadge,
        'progress': {
          'helpfulVotes': summary.helpfulVotes,
          'soldCount': summary.soldCount,
          'nextGoalPoints': summary.nextGoalPoints,
          'pointsToNextGoal': summary.pointsToNextGoal,
        },
        'dailyProgress': {
          'posts': {
            'current': summary.dailyPostsCount,
            'max': summary.dailyPostsMax,
            'points': summary.postsProgress.points,
            'isLimitReached': summary.postsProgress.isLimitReached,
          },
          'replies': {
            'current': summary.dailyRepliesCount,
            'max': summary.dailyRepliesMax,
            'points': summary.repliesProgress.points,
            'isLimitReached': summary.repliesProgress.isLimitReached,
          },
          'votes': {
            'current': summary.dailyVotesCount,
            'max': summary.dailyVotesMax,
            'points': summary.votesProgress.points,
            'isLimitReached': summary.votesProgress.isLimitReached,
          },
          'listings': {
            'current': summary.dailyListingsCount,
            'max': summary.dailyListingsMax,
            'points': summary.listingsProgress.points,
            'isLimitReached': summary.listingsProgress.isLimitReached,
          },
          'dailyCap': summary.dailyCap,
          'dailyPointsUsed': summary.dailyPointsToday,
          'isCapReached': summary.isCapReached,
        },
      };
      await prefs.setString('cached_rewards_summary', jsonEncode(map));
    } catch (_) {}
  }

  RewardsSummary? _summary;
  List<UserBadgeItem> _badges = [];
  bool _isLoading = false;
  DateTime? _lastFetchTime;

  RewardsSummary? get summary => _summary;
  List<UserBadgeItem> get badges => List.unmodifiable(_badges);
  bool get isLoading => _isLoading;

  void addPoints(int delta, {int? newBalance}) {
    if (delta == 0 && newBalance == null) return;
    final current = _summary ?? const RewardsSummary();
    final updatedBalance = newBalance ?? (current.balance + delta);
    final updatedLifetime = delta > 0 ? (current.lifetimePoints + delta) : current.lifetimePoints;
    final updatedWeekly = delta > 0 ? (current.weeklyPoints + delta) : current.weeklyPoints;
    final updatedDaily = delta > 0 ? (current.dailyPointsToday + delta) : current.dailyPointsToday;
    final updatedPointsToGoal = (current.nextGoalPoints - updatedBalance).clamp(0, current.nextGoalPoints);

    _summary = current.copyWith(
      balance: updatedBalance,
      lifetimePoints: updatedLifetime,
      weeklyPoints: updatedWeekly,
      dailyPointsToday: updatedDaily,
      pointsToNextGoal: updatedPointsToGoal,
    );
    unawaited(_saveCachedSummary(_summary!));
    notifyListeners();
    unawaited(fetchSummary(forceRefresh: true));
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('app_device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${(100000 + (DateTime.now().microsecond % 900000))}';
      await prefs.setString('app_device_id', deviceId);
    }
    return deviceId;
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await AuthService.instance.getAccessToken();
    final deviceId = await _getDeviceId();
    return {
      'Content-Type': 'application/json',
      'x-device-id': deviceId,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<RewardsSummary?> fetchSummary({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final isCacheFresh = _summary != null &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!).inSeconds < 15 &&
        _summary!.referralCode.isNotEmpty;

    if (isCacheFresh && !forceRefresh) return _summary;

    try {
      _isLoading = true;
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/me');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['data'] != null) {
          _summary = RewardsSummary.fromJson(decoded['data']);
          _lastFetchTime = DateTime.now();
          unawaited(_saveCachedSummary(_summary!));
          notifyListeners();
          return _summary;
        }
      }
    } catch (e) {
      debugPrint('[RewardsService] Error fetching summary: $e');
    } finally {
      _isLoading = false;
    }

    _summary ??= const RewardsSummary();
    return _summary;
  }

  void clearCache() {
    _summary = null;
    _lastFetchTime = null;
    _badges = [];
    unawaited(_removeCachedSummary());
    notifyListeners();
  }

  Future<void> _removeCachedSummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_rewards_summary');
    } catch (_) {}
  }

  Future<List<PointsLedgerEntry>> fetchHistory({String filter = 'all'}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/history?filter=$filter');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['history'] is List) {
          return (decoded['history'] as List)
              .whereType<Map<String, dynamic>>()
              .map((m) => PointsLedgerEntry.fromJson(m))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[RewardsService] Error fetching history: $e');
    }
    return [];
  }

  Future<List<UserBadgeItem>> fetchBadges() async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/badges');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['badges'] is List) {
          _badges = (decoded['badges'] as List)
              .whereType<Map<String, dynamic>>()
              .map((m) => UserBadgeItem.fromJson(m))
              .toList();
          notifyListeners();
          return _badges;
        }
      }
    } catch (e) {
      debugPrint('[RewardsService] Error fetching badges: $e');
    }
    return _badges;
  }

  Future<Map<String, dynamic>> fetchLeaderboard({String areaId = 'GJ-VAD'}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/leaderboard?area_id=$areaId');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['leaderboard'] is List) {
          final items = (decoded['leaderboard'] as List)
              .whereType<Map<String, dynamic>>()
              .map((m) => LeaderboardItem.fromJson(m))
              .toList();
          return {
            'leaderboard': items,
            'currentUserRank': decoded['currentUserRank'] ?? -1,
          };
        }
      }
    } catch (e) {
      debugPrint('[RewardsService] Error fetching leaderboard: $e');
    }
    return {'leaderboard': <LeaderboardItem>[], 'currentUserRank': -1};
  }

  Future<ReferralInfo?> fetchReferrals() async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/referrals/me');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          return ReferralInfo.fromJson(decoded);
        }
      }
    } catch (e) {
      debugPrint('[RewardsService] Error fetching referrals: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> applyReferralCode(String code, {String? deviceId}) async {
    try {
      final devId = deviceId ?? await _getDeviceId();
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/referrals/apply');
      final headers = await _getHeaders();
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'code': code,
          'deviceId': devId,
        }),
      ).timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);
      return {
        'success': decoded['success'] == true,
        'message': decoded['message'] ?? decoded['error'] ?? 'Failed to apply referral code',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> boostListing(String listingId, {String areaId = 'GJ-VAD'}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/boost');
      final headers = await _getHeaders();
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'listingId': listingId,
          'areaId': areaId,
        }),
      ).timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);
      if (decoded['success'] == true) {
        addPoints(-300);
        return {
          'success': true,
          'message': decoded['message'] ?? 'Listing boosted for 24 hours!',
          'endsAt': decoded['endsAt'],
        };
      } else {
        return {
          'success': false,
          'message': decoded['error'] ?? 'Failed to boost listing',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  static const List<ShopPerkItem> defaultShopPerks = [
    ShopPerkItem(
      id: 'perk_chai_10off',
      shopId: 'shop_apna_chai',
      shopName: 'Apna Chai & Cafe',
      category: 'Food & Cafe',
      logoUrl: '',
      title: '10% OFF on Hot Beverages & Snacks',
      description: 'Get 10% off on hot teas, coffees & quick bites at counter.',
      costPoints: 50,
      dailyLimit: 10,
      codePrefix: 'CHAI10',
    ),
    ShopPerkItem(
      id: 'perk_bakery_50off',
      shopId: 'shop_royal_bakery',
      shopName: 'Royal Bakeries & Confectionery',
      category: 'Food & Cafe',
      logoUrl: '',
      title: '₹50 OFF on Cakes & Pastries (Min ₹200)',
      description: 'Flat ₹50 discount on fresh cakes, pastries, and baked goods.',
      costPoints: 100,
      dailyLimit: 10,
      codePrefix: 'BAKE50',
    ),
    ShopPerkItem(
      id: 'perk_grocery_100off',
      shopId: 'shop_aone_mart',
      shopName: 'A-One Daily Mart & Groceries',
      category: 'Groceries',
      logoUrl: '',
      title: '₹100 OFF on Daily Groceries (Min ₹500)',
      description: 'Save flat ₹100 on your daily grocery basket of ₹500 or more.',
      costPoints: 150,
      dailyLimit: 10,
      codePrefix: 'GROC100',
    ),
    ShopPerkItem(
      id: 'perk_delivery_free',
      shopId: 'shop_nh_delivery',
      shopName: 'Nearhood Express Delivery',
      category: 'Services',
      logoUrl: '',
      title: 'Free Home Delivery Voucher',
      description: 'Enjoy 100% free doorstep delivery on any local Bazar shop order.',
      costPoints: 40,
      dailyLimit: 15,
      codePrefix: 'FREEDEL',
    ),
    ShopPerkItem(
      id: 'perk_salon_100off',
      shopId: 'shop_glamour_salon',
      shopName: 'Glamour Unisex Salon & Spa',
      category: 'Services',
      logoUrl: '',
      title: 'Flat ₹100 OFF on Salon Services',
      description: 'Get flat ₹100 off on haircut, facial, grooming, or spa services.',
      costPoints: 180,
      dailyLimit: 10,
      codePrefix: 'GLAM100',
    ),
    ShopPerkItem(
      id: 'perk_pharmacy_15off',
      shopId: 'shop_city_pharmacy',
      shopName: 'City Care Medicos & Pharmacy',
      category: 'Healthcare',
      logoUrl: '',
      title: '15% OFF on Wellness & Healthcare',
      description: 'Flat 15% discount on general wellness essentials & medicines.',
      costPoints: 120,
      dailyLimit: 10,
      codePrefix: 'MED15',
    ),
    ShopPerkItem(
      id: 'perk_dining_150off',
      shopId: 'shop_taste_punjab',
      shopName: 'Taste of Punjab Family Restaurant',
      category: 'Food & Cafe',
      logoUrl: '',
      title: '₹150 OFF on Family Dinner (Min ₹750)',
      description: 'Flat ₹150 off on total food bill of ₹750 or more (Dine-in / Takeaway).',
      costPoints: 250,
      dailyLimit: 5,
      codePrefix: 'DINE150',
    ),
    ShopPerkItem(
      id: 'perk_bazar_boost',
      shopId: 'shop_nh_bazar',
      shopName: 'Nearhood Community Bazar',
      category: 'Bazar Boost',
      logoUrl: '',
      title: '24-Hour Listing Boost in Bazar',
      description: 'Pin your product or service listing to the top of Bazaar for 24 hours.',
      costPoints: 300,
      dailyLimit: 5,
      codePrefix: 'BOOST24',
    ),
  ];

  Future<List<ShopPerkItem>> fetchShopPerks() async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/perks');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['perks'] is List) {
          final serverPerks = (decoded['perks'] as List)
              .whereType<Map<String, dynamic>>()
              .map((m) => ShopPerkItem.fromJson(m))
              .toList();
          if (serverPerks.isNotEmpty) {
            return serverPerks;
          }
        }
      }
    } catch (e) {
      debugPrint('[RewardsService] Error fetching shop perks: $e');
    }
    return defaultShopPerks;
  }

  Future<List<UnlockedCouponItem>> fetchMyCoupons() async {
    final localCoupons = await loadCachedUnlockedCoupons();
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/my-coupons');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['coupons'] is List) {
          final serverList = (decoded['coupons'] as List)
              .whereType<Map<String, dynamic>>()
              .map((m) => UnlockedCouponItem.fromJson(m))
              .toList();
          final mergedMap = <String, UnlockedCouponItem>{};
          for (final c in localCoupons) {
            mergedMap[c.id] = c;
          }
          for (final c in serverList) {
            mergedMap[c.id] = c;
          }
          final combined = mergedMap.values.toList();
          await saveAllUnlockedCouponsLocally(combined);
          return combined;
        }
      }
    } catch (_) {}
    return localCoupons;
  }

  Future<List<UnlockedCouponItem>> loadCachedUnlockedCoupons() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_unlocked_coupons');
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          return list
              .whereType<Map<String, dynamic>>()
              .map((m) => UnlockedCouponItem.fromJson(m))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveAllUnlockedCouponsLocally(List<UnlockedCouponItem> coupons) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = coupons.map((c) => c.toJson()).toList();
      await prefs.setString('cached_unlocked_coupons', jsonEncode(jsonList));
    } catch (_) {}
  }

  Future<void> saveUnlockedCouponLocally(UnlockedCouponItem coupon) async {
    final current = await loadCachedUnlockedCoupons();
    current.removeWhere((c) => c.id == coupon.id);
    current.insert(0, coupon);
    await saveAllUnlockedCouponsLocally(current);
  }

  Future<UnlockedCouponItem?> unlockCoupon(String couponId) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/coupons/unlock');
      final headers = await _getHeaders();
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({'couponId': couponId}),
      ).timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);
      if (decoded['success'] == true && decoded['coupon'] != null) {
        await fetchSummary(forceRefresh: true);
        final item = UnlockedCouponItem.fromJson(decoded['coupon']);
        await saveUnlockedCouponLocally(item);
        return item;
      }
    } catch (e) {
      debugPrint('[RewardsService] Error unlocking coupon: $e');
    }

    final matched = defaultShopPerks.where((p) => p.id == couponId).firstOrNull;
    if (matched != null && (_summary?.balance ?? 0) >= matched.costPoints) {
      addPoints(-matched.costPoints);
      final randomSuffix = (1000 + DateTime.now().millisecondsSinceEpoch % 9000).toString();
      final item = UnlockedCouponItem(
        id: 'uc_${DateTime.now().millisecondsSinceEpoch}',
        code: 'NH-${matched.codePrefix}-$randomSuffix',
        title: matched.title,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await saveUnlockedCouponLocally(item);
      return item;
    }

    return null;
  }

  Future<Map<String, dynamic>> toggleCommentLike(String replyId) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/comments/$replyId/like');
      final headers = await _getHeaders();
      var response = await http.post(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) {
        final fallbackUri = Uri.parse('${ApiConstants.baseUrl}/rewards/replies/$replyId/like');
        response = await http.post(fallbackUri, headers: headers).timeout(const Duration(seconds: 10));
      }
      if (response.statusCode == 404) {
        final fallbackUri2 = Uri.parse('${ApiConstants.baseUrl}/rewards/replies/$replyId/helpful');
        response = await http.post(fallbackUri2, headers: headers).timeout(const Duration(seconds: 10));
      }

      final decoded = jsonDecode(response.body);
      final isSuccess = decoded['success'] == true;
      if (isSuccess) {
        unawaited(fetchSummary(forceRefresh: true));
      }
      final isLiked = decoded['liked_by_me'] ??
          decoded['likedByMe'] ??
          decoded['isLiked'] ??
          (decoded['action'] == 'liked' || decoded['action'] == 'voted');
      return {
        'success': isSuccess,
        'action': decoded['action'] ?? (isLiked == true ? 'liked' : 'unliked'),
        'isLiked': isLiked == true,
        'liked_by_me': isLiked == true,
        'likedByMe': isLiked == true,
        'likeCount': (decoded['likeCount'] ?? decoded['like_count']) as int?,
        'message': decoded['message'] ?? decoded['error'] ?? '',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  Future<Map<String, dynamic>> toggleHelpfulVote(String replyId) => toggleCommentLike(replyId);

  Future<Map<String, dynamic>> claimBazaarListingReward(String listingId) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/rewards/bazaar/$listingId/claim');
      final headers = await _getHeaders();
      final response = await http.post(uri, headers: headers).timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);
      final isSuccess = decoded['success'] == true;
      if (isSuccess) {
        final pts = (decoded['pointsAwarded'] as num?)?.toInt() ?? 10;
        final newBal = (decoded['newBalance'] as num?)?.toInt();
        addPoints(pts, newBalance: newBal);
      }
      return {
        'success': isSuccess,
        'pointsAwarded': decoded['pointsAwarded'] ?? 0,
        'message': decoded['message'] ?? decoded['error'] ?? '',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }
}
