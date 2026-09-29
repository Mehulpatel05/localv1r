// 🛡️ Centralized API Configuration & Network Endpoints
// Single Source of Truth for all Backend Network Calls across the entire App.

class ApiConstants {
  ApiConstants._();

  /// Primary Backend Base URL
  /// Can be overridden at build-time via `--dart-define=BACKEND_URL=https://...`
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://13.203.224.239/api/v1',
  );

  /// Root Host URL (without /api/v1)
  static String get rootUrl => baseUrl.replaceAll('/api/v1', '');

  /// Health Check Endpoint
  static String get healthUrl => '$rootUrl/health';

  /// Media & File Upload Endpoint
  static String get uploadUrl => '$baseUrl/storage/upload';
}
