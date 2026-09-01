import 'device_info_service.dart';

/// Service to provide a stable installation identifier that survives app uninstall & reinstall.
class DeviceService {
  /// Returns a stable installation identifier.
  static Future<String> getInstallationId() {
    return DeviceInfoService.getInstallationId();
  }
}

