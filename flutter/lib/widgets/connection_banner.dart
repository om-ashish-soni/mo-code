import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// A banner shown when the app is disconnected from the daemon.
/// Displays reconnection status and a manual retry button.
class ConnectionBanner extends StatelessWidget {
  final bool isReconnecting;
  final int? attemptNumber;
  final VoidCallback onRetry;

  const ConnectionBanner({
    super.key,
    required this.isReconnecting,
    this.attemptNumber,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.red.withAlpha(20),
        border: Border(
          bottom: BorderSide(color: AppColors.red.withAlpha(60)),
        ),
      ),
      child: Row(
        children: [
          if (isReconnecting) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.amber,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                attemptNumber != null
                    ? 'Reconnecting... (attempt $attemptNumber)'
                    : 'Reconnecting...',
                style: const TextStyle(color: AppColors.amber, fontSize: 12),
              ),
            ),
          ] else ...[
            const Icon(Icons.cloud_off, color: AppColors.red, size: 14),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Disconnected from daemon',
                style: TextStyle(color: AppColors.red, fontSize: 12),
              ),
            ),
          ],
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple error state widget with icon, message, and retry button.
class ErrorStateWidget extends StatelessWidget {
  final String message;
  final String? detail;
  final VoidCallback? onRetry;
  final IconData icon;

  const ErrorStateWidget({
    super.key,
    required this.message,
    this.detail,
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
