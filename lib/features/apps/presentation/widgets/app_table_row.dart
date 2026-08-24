import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/presentation/widgets/app_icon.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

/// Column geometry, shared by the header and every row.
///
/// Header and rows previously each declared their own flex values, which is how
/// a table ends up with labels that do not sit above their data. One spec, used
/// by both, makes that impossible.
@immutable
class AppTableLayout {
  const AppTableLayout._();

  static const double checkbox = 40;
  static const double actions = 44;

  /// Fixed rather than flexed: version strings and sizes are short and
  /// predictable, and letting them flex pushes the columns around as the list
  /// filters.
  static const double version = 100;
  static const double size = 96;

  static const int appFlex = 4;
  static const int developerFlex = 2;
  static const int lastOpenedFlex = 2;

  static const double rowHeight = 54;
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
  );
}

/// One selectable row for a [MacApp].
///
/// System apps (under /System/Applications) are listed for context but can be
/// neither selected nor removed — SIP will not allow it, and hiding them makes
/// the disk total look wrong.
class AppTableRow extends StatefulWidget {
  const AppTableRow({
    super.key,
    required this.app,
    required this.selected,
    required this.onSelectionChanged,
    required this.onUninstall,
    this.isLast = false,
  });

  final MacApp app;
  final bool selected;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onUninstall;

  /// Suppresses the divider so the table meets its rounded bottom edge cleanly.
  final bool isLast;

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

    final background =
        widget.selected
            ? colors.accentMuted
            : (_hovered ? colors.surfaceHover : Colors.transparent);

    return MouseRegion(
      cursor: removable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap:
            removable
                ? () => widget.onSelectionChanged(!widget.selected)
                : null,
        child: AnimatedContainer(
          duration: context.motion.fast,
          height: AppTableLayout.rowHeight,
          padding: AppTableLayout.rowPadding,
          decoration: BoxDecoration(
            color: background,
            border:
                widget.isLast
                    ? null
                    : Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: AppTableLayout.checkbox,
                child: Checkbox(
                  value: widget.selected,
                  onChanged:
                      removable
                          ? (_) => widget.onSelectionChanged(!widget.selected)
                          : null,
                ),
              ),
              Expanded(
                flex: AppTableLayout.appFlex,
                child: _identity(context, app),
              ),
              Expanded(
                flex: AppTableLayout.developerFlex,
                child: Text(
                  app.developer ?? '—',
                  style: context.text.bodyM,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: AppTableLayout.version,
                child: Text(
                  app.version.isEmpty ? '—' : app.version,
                  style: context.text.bodyM,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: AppTableLayout.lastOpenedFlex,
                child: Text(
                  app.lastUsedLabel,
                  style: context.text.bodyM.copyWith(
                    // "Never" is the signal that matters on this screen.
                    color:
                        app.lastUsed == null
                            ? colors.textMuted
                            : colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: AppTableLayout.size,
                child: Text(
                  app.sizeBytes > 0 ? formatBytes(app.sizeBytes) : '—',
                  textAlign: TextAlign.right,
                  style: context.text.bodyM.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: AppTableLayout.actions,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _trailing(context, removable),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The delete affordance only appears on hover — a red glyph on every row
  /// turns a list of your own apps into a wall of warnings.
  Widget? _trailing(BuildContext context, bool removable) {
    final colors = context.colors;

    if (!removable) {
      return Tooltip(
        message: 'Protected by macOS',
        child: Icon(AppIcons.locked, size: 14, color: colors.textMuted),
      );
    }
    if (!_hovered) return null;

    return IconButton(
      icon: const Icon(AppIcons.delete, size: 17),
      color: colors.risky,
      tooltip: 'Uninstall ${widget.app.name}',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      onPressed: widget.onUninstall,
    );
  }

  Widget _identity(BuildContext context, MacApp app) {
    final colors = context.colors;

    return Row(
      children: [
        AppIcon(app: app, size: 30),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      app.name,
                      style: context.text.titleS,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (app.isSystem) ...[
                    const SizedBox(width: AppSpacing.sm),
                    StatusChip(label: 'System', color: colors.textMuted),
                  ],
                ],
              ),
              const SizedBox(height: 1),
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
