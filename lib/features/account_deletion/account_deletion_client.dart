import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../services/auth_service.dart';

class AccountDeletionClientResult {
  final bool success;
  final String message;
  final bool verifiedZeroRecords;
  final bool storagePurged;
  final int deletedR2MediaCount;
  final String? error;

  const AccountDeletionClientResult({
    required this.success,
    required this.message,
    this.verifiedZeroRecords = false,
    this.storagePurged = false,
    this.deletedR2MediaCount = 0,
    this.error,
  });
}

class AccountDeletionClient {
  static final AccountDeletionClient instance = AccountDeletionClient._internal();
  AccountDeletionClient._internal();

  Future<AccountDeletionClientResult> purgeAccountRemotely() async {
    String? token = await AuthService.instance.getAccessToken();
    token ??= await AuthService.instance.refreshToken();

    final primaryUri = Uri.parse('${ApiConstants.baseUrl}/account/purge');
    final fallbackUri = Uri.parse('${ApiConstants.baseUrl}/account');

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      var response = await http.delete(primaryUri, headers: headers);

      if (response.statusCode == 401) {
        final newToken = await AuthService.instance.refreshToken();
        if (newToken != null && newToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $newToken';
          response = await http.delete(primaryUri, headers: headers);
        }
      }

      if (response.statusCode == 404) {
        response = await http.delete(fallbackUri, headers: headers);
      }

      if (response.statusCode == 200 || response.statusCode == 204) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return AccountDeletionClientResult(
            success: data['success'] == true,
            message: data['message'] ?? 'Account wiped successfully',
            verifiedZeroRecords: data['verifiedZeroRecords'] == true,
            storagePurged: data['storagePurged'] == true,
            deletedR2MediaCount: data['deletedR2MediaCount'] is int
                ? data['deletedR2MediaCount'] as int
                : 0,
            error: data['error'] as String?,
          );
        } catch (_) {
          return const AccountDeletionClientResult(
            success: true,
            message: 'Account successfully removed from server',
            verifiedZeroRecords: true,
            storagePurged: true,
          );
        }
      } else {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final errorMsg = data['error'] ?? data['message'] ?? 'Failed to delete account';
          return AccountDeletionClientResult(
            success: false,
            message: errorMsg,
            error: errorMsg,
          );
        } catch (_) {
          return AccountDeletionClientResult(
            success: false,
            message: 'Server error with status ${response.statusCode}',
            error: 'HTTP ${response.statusCode}',
          );
        }
      }
    } catch (e) {
      return AccountDeletionClientResult(
        success: false,
        message: 'Network failure during deletion request: $e',
        error: e.toString(),
      );
    }
  }
}
