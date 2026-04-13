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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.red.withAlpha(12),
        border: Border(
          bottom: BorderSide(color: AppColors.red.withAlpha(30)),
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
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                attemptNumber != null
                    ? 'Reconnecting... (attempt $attemptNumber)'
                    : 'Reconnecting...',
                style: AppTheme.uiFont(fontSize: 12, color: AppColors.amber, fontWeight: FontWeight.w500),
              ),
            ),
          ] else ...[
            const Icon(Icons.cloud_off_rounded, color: AppColors.red, size: 14),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Disconnected from daemon',
                style: AppTheme.uiFont(fontSize: 12, color: AppColors.red, fontWeight: FontWeight.w500),
              ),
            ),
          ],
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Text(
                'Retry',
                style: AppTheme.uiFont(fontSize: 11, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
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
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.redDim,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Icon(icon, color: AppColors.red, size: 32),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              style: AppTheme.uiFont(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail!,
                style: AppTheme.uiFont(fontSize: 12, color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
