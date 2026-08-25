import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/preview/preview_chrome.dart';
import 'package:tidy/landing/preview/preview_mac.dart';

/// Uninstall apps completely, and clean up after old ones.
///
/// Expanding a row shows the leftovers *before* anything is touched, which is
/// the whole difference between this and dragging an app to the Trash.
class PreviewApplicationsPane extends StatefulWidget {
  const PreviewApplicationsPane({
    super.key,
    required this.mac,
    this.onNavigate,
  });

  final PreviewMac mac;
  final ValueChanged<PreviewScreen>? onNavigate;

  @override
  State<PreviewApplicationsPane> createState() =>
      _PreviewApplicationsPaneState();
}

class _PreviewApplicationsPaneState extends State<PreviewApplicationsPane> {
  String? _expanded;
  int _filter = 0;

  static const List<String> _filters = ['All apps', 'Unused', 'Large'];

  List<PreviewApp> get _rows {
    final apps = widget.mac.visibleApps;
    return switch (_filter) {
      1 => apps.where((app) => app.unused).toList(),
      2 => apps.where((app) => app.bytes > 1024 * 1024 * 1024).toList(),
      _ => apps,
    };
  }

  @override
  Widget build(BuildContext context) {
    final mac = widget.mac;
    final rows = _rows;

    return ModuleScaffold(
      title: PreviewScreen.applications.label,
      subtitle: PreviewScreen.applications.blurb,
      actions: [
        SizedBox(
          width: 220,
          child: AppSearchField(
            hintText: 'Filter apps…',
            onChanged: mac.setAppQuery,
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SegmentedTabs(
                labels: _filters,
                selectedIndex: _filter,
                onChanged: (index) => setState(() => _filter = index),
              ),
              const Spacer(),
              Text(
                '${mac.appCount} apps · ${formatBytes(mac.appBytes)} on disk',
                style: context.text.caption,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          PreviewTable(
            header: const PreviewTableHeader(
              cells: [
                (5, 'Application'),
                (4, 'Developer'),
                (2, 'Version'),
                (3, 'Last opened'),
                (2, 'Size'),
                (2, ''),
              ],
            ),
            rows: [
              for (var i = 0; i < rows.length; i++) ...[
                _AppRow(
                  app: rows[i],
                  expanded: _expanded == rows[i].name,
                  last: i == rows.length - 1 && _expanded != rows[i].name,
                  onTap:
                      () => setState(
                        () =>
                            _expanded =
                                _expanded == rows[i].name ? null : rows[i].name,
                      ),
                ),
                if (_expanded == rows[i].name)
                  _Leftovers(
                    app: rows[i],
                    onUninstall: () {
                      setState(() => _expanded = null);
                      mac.uninstall(rows[i]);
                      widget.onNavigate?.call(PreviewScreen.recycleBin);
                    },
                  ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Showing ${rows.length} of ${mac.appCount}. Sizes are what each '
            'app occupies on disk, not its logical length — on APFS a sparse '
            'file reports far more than it uses.',
            style: context.text.caption,
          ),
        ],
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.expanded,
    required this.last,
    required this.onTap,
  });

  final PreviewApp app;
  final bool expanded;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return PreviewRow(
      onTap: onTap,
      last: last,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Icon(
                  expanded ? AppIcons.expand : AppIcons.collapse,
                  size: 14,
                  color: colors.textMuted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    app.name,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleS,
                  ),
                ),
                if (app.unused) ...[
                  const SizedBox(width: AppSpacing.sm),
                  StatusChip(
                    label: 'Unused',
                    color: colors.review,
                    icon: AppIcons.review,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              app.developer,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyM,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(app.version, style: context.text.bodyM),
          ),
          Expanded(
            flex: 3,
            child: Text(app.lastOpened, style: context.text.bodyM),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatBytes(app.bytes),
              style: context.text.titleS.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                expanded ? 'Hide leftovers' : 'Show leftovers',
                style: context.text.caption.copyWith(color: colors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Leftovers extends StatelessWidget {
  const _Leftovers({required this.app, required this.onUninstall});

  final PreviewApp app;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${app.leftovers.length} leftovers · '
                '${formatBytes(app.leftoverBytes)}',
                style: context.text.titleS,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  // The rule that keeps a cleaner from deleting ~/Library/Mail
                  // because an app was called "Mail".
                  'Matched by bundle id and exact display name — never by '
                  'substring.',
                  style: context.text.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final leftover in app.leftovers)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(AppIcons.folder, size: 14, color: colors.textMuted),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      leftover.path,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.mono,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  StatusChip.safety(leftover.safety, context),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 74,
                    child: Text(
                      formatBytes(leftover.bytes),
                      textAlign: TextAlign.right,
                      style: context.text.caption.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              GradientButton(
                label: 'Move ${app.name} and its leftovers to Trash',
                icon: AppIcons.trash,
                onPressed: onUninstall,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'Recoverable — Put Back works.',
                style: context.text.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
