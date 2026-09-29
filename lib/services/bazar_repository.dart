import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/bazar/bazar_screen.dart';
import '../screens/bazar/shop_detail_screen.dart';
import 'auth_service.dart';

class BazarRepository extends ChangeNotifier {
  static final BazarRepository _instance = BazarRepository._internal();
  factory BazarRepository() => _instance;
  static BazarRepository get instance => _instance;

  BazarRepository._internal();

  static const String _kProductsKey = 'real_bazar_products_v1';
  static const String _kShopsKey = 'real_local_shops_v1';
  static const String _kSavedProductsKey = 'real_saved_product_ids_v1';
  static const String _kSavedShopsKey = 'real_saved_shop_ids_v1';

  List<BazarProduct> _products = [];
  List<LocalShop> _shops = [];
  Set<String> _savedProductIds = {};
  Set<String> _savedShopIds = {};
  bool _isInitialized = false;

  List<BazarProduct> get products => List.unmodifiable(_products);
  List<LocalShop> get shops => List.unmodifiable(_shops);
  Set<String> get savedProductIds => Set.unmodifiable(_savedProductIds);
  Set<String> get savedShopIds => Set.unmodifiable(_savedShopIds);

  Future<String> _getActiveHandle() async {
    final h = await AuthService.instance.getUserHandle();
    final clean = (h ?? '').replaceAll('@', '').trim().toLowerCase();
    return clean.isNotEmpty ? clean : 'default_user';
  }

  Future<void> init({bool forceRefresh = false}) async {
    if (_isInitialized && !forceRefresh) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeHandle = await _getActiveHandle();
      
      // Load real products
      final productsJsonStr = prefs.getString(_kProductsKey);
      if (productsJsonStr != null && productsJsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(productsJsonStr);
        _products = list
            .map((item) => BazarProduct.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      // Load real shops
      final shopsJsonStr = prefs.getString(_kShopsKey);
      if (shopsJsonStr != null && shopsJsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(shopsJsonStr);
        _shops = list
            .map((item) => LocalShop.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      // Load user-scoped saved IDs
      final savedProdList = prefs.getStringList('${_kSavedProductsKey}_$activeHandle') ?? [];
      _savedProductIds = savedProdList.toSet();

      final savedShopList = prefs.getStringList('${_kSavedShopsKey}_$activeHandle') ?? [];
      _savedShopIds = savedShopList.toSet();

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[BazarRepository] error initializing: $e');
    }
  }

  // --- PRODUCTS ---
  Future<void> addProduct(BazarProduct product) async {
    await init();
    _products.insert(0, product);
    await _persistProducts();
    notifyListeners();
  }

  Future<void> markProductAsSold(String productId) async {
    await init();
    final idx = _products.indexWhere((p) => p.id == productId);
    if (idx != -1) {
      _products[idx].isSold = true;
      await _persistProducts();
      notifyListeners();
    }
  }

  Future<void> deleteProduct(String productId) async {
    await init();
    _products.removeWhere((p) => p.id == productId);
    await _persistProducts();
    notifyListeners();
  }

  Future<void> _persistProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_products.map((p) => p.toJson()).toList());
      await prefs.setString(_kProductsKey, encoded);
    } catch (e) {
      debugPrint('[BazarRepository] error persisting products: $e');
    }
  }

  // --- SHOPS ---
  Future<void> registerShop(LocalShop shop) async {
    await init();
    final idx = _shops.indexWhere((s) => s.id == shop.id);
    if (idx != -1) {
      _shops[idx] = shop;
    } else {
      _shops.insert(0, shop);
    }
    await _persistShops();
    notifyListeners();
  }

  Future<void> deleteShop(String shopId) async {
    await init();
    _shops.removeWhere((s) => s.id == shopId);
    await _persistShops();
    notifyListeners();
  }

  Future<void> _persistShops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_shops.map((s) => s.toJson()).toList());
      await prefs.setString(_kShopsKey, encoded);
    } catch (e) {
      debugPrint('[BazarRepository] error persisting shops: $e');
    }
  }

  // --- SAVED ITEMS & SHOPS (USER ISOLATED) ---
  bool isProductSaved(String productId) => _savedProductIds.contains(productId);
  bool isShopSaved(String shopId) => _savedShopIds.contains(shopId);

  Future<void> toggleSaveProduct(String productId) async {
    await init();
    final activeHandle = await _getActiveHandle();
    if (_savedProductIds.contains(productId)) {
      _savedProductIds.remove(productId);
    } else {
      _savedProductIds.add(productId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('${_kSavedProductsKey}_$activeHandle', _savedProductIds.toList());
    notifyListeners();
  }

  Future<void> toggleSaveShop(String shopId) async {
    await init();
    final activeHandle = await _getActiveHandle();
    if (_savedShopIds.contains(shopId)) {
      _savedShopIds.remove(shopId);
    } else {
      _savedShopIds.add(shopId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('${_kSavedShopsKey}_$activeHandle', _savedShopIds.toList());
    notifyListeners();
  }
}
