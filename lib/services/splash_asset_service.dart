import 'package:flutter/material.dart';
import 'app_asset_service.dart';

class SplashAssetService {
  SplashAssetService._();
  static final SplashAssetService instance = SplashAssetService._();

  ValueNotifier<int> get revisionNotifier => AppAssetService.instance.revisionNotifier;

  Future<void> init() => AppAssetService.instance.init();

  ImageProvider getSplashImageProvider() => AppAssetService.instance.getSplashImageProvider();

  Future<void> syncFromServer() => AppAssetService.instance.syncAllFromServer();
}
