// 🛡️ Centralized API Configuration & Network Endpoints
// Single Source of Truth for all Backend Network Calls across the entire App.

class ApiConstants {
  ApiConstants._();

  /// Primary Backend Base URL
  /// Can be overridden at build-time via `--dart-define=BACKEND_URL=https://...`
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://3.109.213.23/api/v2',
  );

  /// Root Host URL (without /api/v2 or /api/v1)
  static String get rootUrl => baseUrl.replaceAll(RegExp(r'/api/v[12]/?$'), '');


  /// Health Check Endpoint
  static String get healthUrl => '$rootUrl/health';

  /// Media & File Upload Endpoint
  static String get uploadUrl => '$baseUrl/storage/upload';
}
