import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/presentation/widgets/app_icon.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

/// One selectable row for a [MacApp].
///
/// System apps (under /System/Applications) are listed for context but can be
/// neither selected nor removed — SIP will not allow it, and hiding them makes
/// the total disk figure look wrong.
class AppTableRow extends StatefulWidget {
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
  State<AppTableRow> createState() => _AppTableRowState();
}

class _AppTableRowState extends State<AppTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final app = widget.app;
    final removable = !app.isSystem;

    final background = widget.selected
        ? colors.accentMuted
        : (_hovered ? colors.surfaceHover : Colors.transparent);

    return MouseRegion(
      cursor: removable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: removable
            ? () => widget.onSelectionChanged(!widget.selected)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  value: widget.selected,
                  onChanged: removable
                      ? (_) => widget.onSelectionChanged(!widget.selected)
                      : null,
                ),
              ),
              Expanded(flex: 3, child: _identity(context, app)),
              Expanded(
                flex: 2,
                child: Text(
                  app.developer ?? '—',
                  style: context.text.bodyM,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 1,
                child: app.version.isEmpty
                    ? Text('—', style: context.text.bodyM)
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: VersionBadge(version: app.version),
                      ),
              ),
              Expanded(
                flex: 2,
                child: Text(app.lastUsedLabel, style: context.text.bodyM),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  app.sizeBytes > 0 ? formatBytes(app.sizeBytes) : '—',
                  style: context.text.bodyM.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: removable && _hovered
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        color: colors.risky,
                        tooltip: 'Uninstall ${app.name}',
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onUninstall,
                      )
                    : (app.isSystem
                          ? Tooltip(
                              message: 'Protected by macOS',
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 14,
                                color: colors.textMuted,
                              ),
                            )
                          : null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _identity(BuildContext context, MacApp app) {
    final colors = context.colors;

    return Row(
      children: [
        AppIcon(app: app),
        const SizedBox(width: AppSpacing.md),
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
                      style: context.text.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (app.isSystem) ...[
                    const SizedBox(width: AppSpacing.sm),
                    StatusChip(label: 'System', color: colors.textMuted),
                  ],
                ],
              ),
              Text(
                app.bundleId.isEmpty ? app.path : app.bundleId,
                style: context.text.caption,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
