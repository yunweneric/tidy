import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';

/// Confirmation dialog for uninstalling an app.
class UninstallConfirmDialog extends StatelessWidget {
  const UninstallConfirmDialog({
    super.key,
    required this.app,
    required this.onConfirm,
  });

  final MacApp app;
  final VoidCallback onConfirm;

  static Future<bool?> show(BuildContext context, MacApp app, VoidCallback onConfirm) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => UninstallConfirmDialog(app: app, onConfirm: onConfirm),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceCard,
      title: Text(
        'Uninstall "${app.name}"?',
        style: AppTheme.bodyPrimary.copyWith(fontSize: 18),
      ),
      content: Text(
        'Are you sure you want to uninstall this application?',
        style: AppTheme.bodySecondary,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentRed,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            onConfirm();
            Navigator.of(context).pop(true);
          },
          child: const Text('Uninstall'),
        ),
      ],
    );
  }
}
