import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// Card showing storage usage with progress bar and optional action button.
class StorageCard extends StatelessWidget {
  const StorageCard({
    super.key,
    required this.usedLabel,
    required this.progress,
    this.buttonLabel = 'Upgrade Storage',
    this.onButtonPressed,
  });

  final String usedLabel;
  final double progress;
  final String? buttonLabel;
  final VoidCallback? onButtonPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Storage Status',
              style: AppTheme.sectionHeader.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(usedLabel, style: AppTheme.bodySecondary),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppTheme.borderSubtle,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
                minHeight: 6,
              ),
            ),
            if (buttonLabel != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onButtonPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(buttonLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
