import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/presentation/widgets/app_icon.dart';

/// Single selectable table row for a [MacApp] with checkbox, icon, name, developer, version, last opened, size, delete.
class AppTableRow extends StatelessWidget {
  const AppTableRow({
    super.key,
    required this.app,
    required this.selected,
    required this.onSelectionChanged,
    required this.onUninstall,
  });

  final MacApp app;
  final bool selected;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.accentBlue.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: () => onSelectionChanged(!selected),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onSelectionChanged(!selected),
                  fillColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? AppTheme.accentBlue : Colors.transparent,
                  ),
                  side: const BorderSide(color: AppTheme.borderLight),
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    AppIcon(app: app),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        app.name,
                        style: AppTheme.bodyPrimary,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  app.developer ?? '—',
                  style: AppTheme.bodySecondary,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 1,
                child: app.version.isNotEmpty
                    ? VersionBadge(version: app.version)
                    : Text('—', style: AppTheme.bodySecondary),
              ),
              Expanded(
                flex: 2,
                child: Text(app.lastOpened ?? '—', style: AppTheme.bodySecondary),
              ),
              Expanded(flex: 1, child: Text(app.size, style: AppTheme.bodySecondary)),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed, size: 20),
                onPressed: onUninstall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
