import 'package:flutter/material.dart';
import '../../core/auth_repository.dart';
import '../../features/auth/login_flow_page.dart';
import '../../services/post_repository.dart';
import '../../theme/app_colors.dart';
import 'account_deletion_dialog.dart';
import 'account_deletion_client.dart';
import 'client_purge_registry.dart';

class AccountDeletionCoordinator {
  AccountDeletionCoordinator._();

  static Future<void> startDeletionFlow(
    BuildContext context, {
    AuthRepository? authRepository,
  }) async {
    final confirmed = await AccountDeletionDialog.show(context);
    if (confirmed != true) return;

    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.error),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'Permanently wiping account...',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final result = await AccountDeletionClient.instance.purgeAccountRemotely();

    if (result.success) {
      await ClientPurgeRegistry.instance.purgeAllClientState();

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();

        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => LoginFlowPage(
              authRepository: authRepository ?? BackendAuthRepository(),
              postRepository: PostRepository.instance,
            ),
          ),
          (route) => false,
        );

        final wipeMessage = result.storagePurged
            ? 'Your account and all associated data have been permanently wiped.'
            : 'Your account was wiped, but some files could not be purged from storage.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryText,
            content: Text(
              wipeMessage,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        );
      }
    } else {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();

        showDialog<void>(
          context: context,
          builder: (errCtx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Account Deletion Failed',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
            content: Text(
              result.message.isNotEmpty
                ? result.message
                : 'Unable to complete deletion request. Please check your connection and try again.',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(errCtx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
}
