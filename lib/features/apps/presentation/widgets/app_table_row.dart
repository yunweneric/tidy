import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/presentation/widgets/app_icon.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

/// Single selectable table row for a [MacApp].
///
/// System apps (under /System/Applications) are listed for context but can be
/// neither selected nor removed — macOS will not allow it.
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
    final removable = !app.isSystem;

    return Material(
      color: selected ? AppTheme.accentBlue.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: removable ? () => onSelectionChanged(!selected) : null,
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
                  onChanged: removable ? (_) => onSelectionChanged(!selected) : null,
                  fillColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected)
                        ? AppTheme.accentBlue
                        : Colors.transparent,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  app.name,
                                  style: AppTheme.bodyPrimary,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (app.isSystem) ...[
                                const SizedBox(width: 8),
                                const _SystemBadge(),
                              ],
                            ],
                          ),
                          Text(
                            app.bundleId.isEmpty ? app.path : app.bundleId,
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textMuted,
                              fontSize: 10,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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
                child: Text(app.lastUsedLabel, style: AppTheme.bodySecondary),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  app.sizeBytes > 0 ? formatBytes(app.sizeBytes) : '—',
                  style: AppTheme.bodySecondary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppTheme.accentRed,
                tooltip: removable ? 'Uninstall ${app.name}' : 'Protected by macOS',
                onPressed: removable ? onUninstall : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemBadge extends StatelessWidget {
  const _SystemBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'SYSTEM',
        style: AppTheme.labelSmall.copyWith(fontSize: 9, color: AppTheme.textMuted),
      ),
    );
  }
}
