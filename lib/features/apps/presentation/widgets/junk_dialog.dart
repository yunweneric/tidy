import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/features/apps/data/services/junk_scanner.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

/// What the user approved in the junk sweep.
class JunkCleanupPlan {
  const JunkCleanupPlan({required this.paths, required this.totalBytes});

  final List<String> paths;
  final int totalBytes;
}

/// Lists reclaimable space by category and returns the paths the user approved.
///
/// Caches, logs and saved state are pre-selected because macOS regenerates
/// them. Orphaned leftovers are guesses about apps that are already gone, so
/// they start unchecked and have to be opted into.
class JunkDialog extends StatefulWidget {
  const JunkDialog({super.key, required this.report});

  final JunkReport report;

  static Future<JunkCleanupPlan?> show(BuildContext context, JunkReport report) {
    return showDialog<JunkCleanupPlan>(
      context: context,
      builder: (_) => JunkDialog(report: report),
    );
  }

  @override
  State<JunkDialog> createState() => _JunkDialogState();
}

class _JunkDialogState extends State<JunkDialog> {
  late final Set<String> _selected = {
    for (final group in widget.report.groups)
      if (group.kind.safeByDefault)
        for (final item in group.items) item.path,
  };

  int get _selectedBytes {
    var total = 0;
    for (final group in widget.report.groups) {
      for (final item in group.items) {
        if (_selected.contains(item.path)) total += item.sizeBytes;
      }
    }
    return total;
  }

  void _toggleGroup(JunkGroup group, bool selected) {
    setState(() {
      for (final item in group.items) {
        if (selected) {
          _selected.add(item.path);
        } else {
          _selected.remove(item.path);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.report.groups;

    return AlertDialog(
      backgroundColor: AppTheme.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        'Reclaimable space',
        style: AppTheme.bodyPrimary.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 560,
        child: groups.isEmpty
            ? Text('Nothing to clean up right now.', style: AppTheme.bodySecondary)
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final group in groups) _buildGroup(group),
                    ],
                  ),
                ),
              ),
      ),
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
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      JunkCleanupPlan(
                        paths: _selected.toList(),
                        totalBytes: _selectedBytes,
                      ),
                    ),
              child: const Text('Move to Trash'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGroup(JunkGroup group) {
    final allSelected = group.items.every((item) => _selected.contains(item.path));
    final noneSelected = group.items.every((item) => !_selected.contains(item.path));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: allSelected ? true : (noneSelected ? false : null),
                tristate: true,
                onChanged: (_) => _toggleGroup(group, !allSelected),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          group.kind.label,
                          style: AppTheme.bodyPrimary.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!group.kind.safeByDefault)
                          const Tooltip(
                            message: 'Review these before removing',
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: AppTheme.accentOrange,
                            ),
                          ),
                      ],
                    ),
                    Text(group.kind.description, style: AppTheme.labelSmall),
                  ],
                ),
              ),
              Text(
                formatBytes(group.sizeBytes),
                style: AppTheme.bodyPrimary.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Only the largest few per group — the long tail is noise.
          for (final item in group.items.take(6)) _buildItem(item),
          if (group.items.length > 6)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 2),
              child: Text(
                '+ ${group.items.length - 6} more',
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItem(JunkItem item) {
    final selected = _selected.contains(item.path);
    return Padding(
      padding: const EdgeInsets.only(left: 36),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Checkbox(
              value: selected,
              onChanged: (value) => setState(() {
                if (value ?? false) {
                  _selected.add(item.path);
                } else {
                  _selected.remove(item.path);
                }
              }),
            ),
          ),
          Expanded(
            child: Text(
              item.label,
              style: AppTheme.bodySecondary,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(formatBytes(item.sizeBytes), style: AppTheme.labelSmall),
          IconButton(
            icon: const Icon(Icons.folder_open_outlined, size: 15),
            color: AppTheme.textMuted,
            tooltip: 'Reveal in Finder',
            onPressed: () => SystemBridge.revealInFinder(item.path),
          ),
        ],
      ),
    );
  }
}
