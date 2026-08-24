import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/features/apps/data/models/leftover_item.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/data/services/leftover_scanner.dart';
import 'package:mac_uninstaller/core/widgets/status_chip.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

/// What the user approved in the preview.
class UninstallPlan {
  const UninstallPlan({
    required this.apps,
    required this.paths,
    required this.totalBytes,
    required this.toTrash,
  });

  final List<MacApp> apps;
  final List<String> paths;
  final int totalBytes;
  final bool toTrash;
}

/// Safe-preview dialog: scans for everything an uninstall would remove, lets
/// the user deselect individual items, and only then reports a plan back.
///
/// Nothing is deleted here — the dialog returns an [UninstallPlan] and the
/// caller dispatches it.
class UninstallConfirmDialog extends StatefulWidget {
  const UninstallConfirmDialog({super.key, required this.apps, this.scanner});

  final List<MacApp> apps;
  final LeftoverScanner? scanner;

  /// Returns the approved plan, or null if the user cancelled.
  static Future<UninstallPlan?> show(BuildContext context, List<MacApp> apps) {
    final removable = apps.where((app) => !app.isSystem).toList();
    if (removable.isEmpty) return Future.value(null);

    return showDialog<UninstallPlan>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UninstallConfirmDialog(apps: removable),
    );
  }

  @override
  State<UninstallConfirmDialog> createState() => _UninstallConfirmDialogState();
}

class _UninstallConfirmDialogState extends State<UninstallConfirmDialog> {
  late final LeftoverScanner _scanner = widget.scanner ?? LeftoverScanner();

  /// Leftovers per app, in the order the apps were passed in.
  final Map<String, List<LeftoverItem>> _leftovers = {};
  final Set<String> _deselected = {};

  bool _scanning = true;
  bool _toTrash = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    for (final app in widget.apps) {
      final items = await _scanner.scan(app);
      if (!mounted) return;
      setState(() => _leftovers[app.path] = items);
    }
    if (mounted) setState(() => _scanning = false);
  }

  bool _isSelected(String path) => !_deselected.contains(path);

  void _toggle(String path, bool selected) {
    setState(() {
      if (selected) {
        _deselected.remove(path);
      } else {
        _deselected.add(path);
      }
    });
  }

  /// Bundle paths are always included — an uninstall that leaves the app in
  /// place is not an uninstall.
  List<String> get _selectedPaths => [
    for (final app in widget.apps) app.path,
    for (final entry in _leftovers.entries)
      for (final item in entry.value)
        if (_isSelected(item.path)) item.path,
  ];

  int get _selectedBytes {
    var total = 0;
    for (final app in widget.apps) {
      total += app.sizeBytes;
    }
    for (final items in _leftovers.values) {
      for (final item in items) {
        if (_isSelected(item.path)) total += item.sizeBytes;
      }
    }
    return total;
  }

  int get _leftoverCount =>
      _leftovers.values.fold<int>(0, (sum, items) => sum + items.length);

  @override
  Widget build(BuildContext context) {
    final multiple = widget.apps.length > 1;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      title: Text(
        multiple
            ? 'Uninstall ${widget.apps.length} applications?'
            : 'Uninstall “${widget.apps.first.name}”?',
        style: context.text.titleM,
      ),
      content: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _scanning
                  ? 'Scanning for leftover files…'
                  : _leftoverCount == 0
                  ? 'No leftover files were found.'
                  : 'Found $_leftoverCount leftover ${_leftoverCount == 1 ? 'item' : 'items'}. '
                        'Uncheck anything you want to keep.',
              style: context.text.bodyM,
            ),
            if (_scanning) ...[
              const SizedBox(height: AppSpacing.sm),
              const LinearProgressIndicator(minHeight: 3),
            ],
            const SizedBox(height: 16),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: SingleChildScrollView(child: _buildItemList()),
              ),
            ),
            const SizedBox(height: 16),
            _buildModeSelector(),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        Row(
          children: [
            Text.rich(
              TextSpan(
                text: _toTrash ? 'Moves ' : 'Removes ',
                style: context.text.bodyM,
                children: [
                  TextSpan(
                    text: formatBytes(_selectedBytes),
                    style: context.text.titleM.copyWith(color: context.colors.safe),
                  ),
                ],
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.risky,
                foregroundColor: context.colors.textOnAccent,
              ),
              onPressed: _scanning
                  ? null
                  : () => Navigator.of(context).pop(
                      UninstallPlan(
                        apps: widget.apps,
                        paths: _selectedPaths,
                        totalBytes: _selectedBytes,
                        toTrash: _toTrash,
                      ),
                    ),
              child: Text(_toTrash ? 'Move to Trash' : 'Delete permanently'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildItemList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final app in widget.apps) ...[
          _PreviewRow(
            title: app.name,
            subtitle: app.path,
            sizeBytes: app.sizeBytes,
            selected: true,
            locked: true,
            categoryLabel: LeftoverCategory.appBundle.label,
            onChanged: (_) {},
          ),
          for (final item in _leftovers[app.path] ?? const <LeftoverItem>[])
            _PreviewRow(
              title: item.displayName,
              subtitle: item.location,
              sizeBytes: item.sizeBytes,
              selected: _isSelected(item.path),
              requiresAdmin: item.requiresAdmin,
              categoryLabel: item.category.label,
              onChanged: (value) => _toggle(item.path, value),
              onReveal: () => SystemBridge.revealInFinder(item.path),
            ),
        ],
      ],
    );
  }

  Widget _buildModeSelector() {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadii.mdAll,
      ),
      child: Row(
        children: [
          Icon(
            _toTrash
                ? AppIcons.restore
                : AppIcons.risky,
            size: 17,
            color: _toTrash ? colors.safe : colors.risky,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _toTrash
                  ? 'Everything moves to the Trash, so you can put it back. '
                        'Your disk will not show the space as free until the '
                        'Trash is emptied.'
                  : 'Removed immediately. Nothing can be recovered.',
              style: context.text.bodyS,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text('Delete permanently', style: context.text.caption),
          Switch(
            value: !_toTrash,
            activeThumbColor: colors.risky,
            onChanged: (value) => setState(() => _toTrash = !value),
          ),
        ],
      ),
    );
  }
}

/// One line in the preview: what it is, where it lives, how big it is.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.title,
    required this.subtitle,
    required this.sizeBytes,
    required this.selected,
    required this.categoryLabel,
    required this.onChanged,
    this.locked = false,
    this.requiresAdmin = false,
    this.onReveal,
  });

  final String title;
  final String subtitle;
  final int sizeBytes;
  final bool selected;
  final String categoryLabel;
  final ValueChanged<bool> onChanged;
  final bool locked;
  final bool requiresAdmin;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Checkbox(
              value: selected,
              onChanged: locked ? null : (value) => onChanged(value ?? false),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: context.text.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    StatusChip(
                      label: categoryLabel,
                      color: context.colors.textMuted,
                    ),
                    if (requiresAdmin) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Tooltip(
                        message: 'Needs administrator rights — this one may fail',
                        child: Icon(
                          AppIcons.locked,
                          size: 13,
                          color: context.colors.review,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: context.text.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(formatBytes(sizeBytes), style: context.text.bodyM),
          if (onReveal != null)
            IconButton(
              icon: const Icon(AppIcons.revealInFinder, size: 15),
              color: context.colors.textMuted,
              tooltip: 'Reveal in Finder',
              visualDensity: VisualDensity.compact,
              onPressed: onReveal,
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

