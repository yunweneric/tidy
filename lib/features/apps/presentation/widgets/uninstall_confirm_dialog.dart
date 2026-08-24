import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/features/apps/data/models/leftover_item.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/data/services/leftover_scanner.dart';
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
      backgroundColor: AppTheme.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      title: Text(
        multiple
            ? 'Uninstall ${widget.apps.length} applications?'
            : 'Uninstall "${widget.apps.first.name}"?',
        style: AppTheme.bodyPrimary.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
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
              style: AppTheme.bodySecondary,
            ),
            if (_scanning) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(
                backgroundColor: AppTheme.borderSubtle,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
                minHeight: 3,
              ),
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
                text: 'Frees ',
                style: AppTheme.bodySecondary,
                children: [
                  TextSpan(
                    text: formatBytes(_selectedBytes),
                    style: AppTheme.bodyPrimary.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentGreen,
                    ),
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
                backgroundColor: AppTheme.accentRed,
                foregroundColor: Colors.white,
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
              child: Text(_toTrash ? 'Move to Trash' : 'Delete Permanently'),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            _toTrash ? Icons.restore_from_trash_outlined : Icons.warning_amber_rounded,
            size: 18,
            color: _toTrash ? AppTheme.accentGreen : AppTheme.accentOrange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _toTrash
                  ? 'Items move to the Trash and can be restored.'
                  : 'Items are deleted immediately and cannot be restored.',
              style: AppTheme.bodySecondary,
            ),
          ),
          Text('Permanently delete', style: AppTheme.labelSmall),
          Switch(
            value: !_toTrash,
            activeThumbColor: AppTheme.accentRed,
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
                        style: AppTheme.bodyPrimary,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CategoryChip(label: categoryLabel),
                    if (requiresAdmin) ...[
                      const SizedBox(width: 6),
                      const Tooltip(
                        message: 'Needs administrator rights — may fail',
                        child: Icon(
                          Icons.lock_outline,
                          size: 13,
                          color: AppTheme.accentOrange,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(formatBytes(sizeBytes), style: AppTheme.bodySecondary),
          if (onReveal != null)
            IconButton(
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              color: AppTheme.textMuted,
              tooltip: 'Reveal in Finder',
              onPressed: onReveal,
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.backgroundPrimary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall.copyWith(fontSize: 10, color: AppTheme.textMuted),
      ),
    );
  }
}
