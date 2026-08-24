import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/features/settings/presentation/widgets/settings_controls.dart';

/// What the history store holds, and how to take it back.
///
/// Not optional polish. This store is a record of every file Tidy has removed
/// from this Mac — the most sensitive thing the app keeps. Someone has to be
/// able to see how much of it exists, take a copy, and delete it, without
/// reading the source to find out where it lives.
class HistorySection extends StatefulWidget {
  const HistorySection({super.key});

  @override
  State<HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<HistorySection> {
  final TidyStore _store = locator<TidyStore>();

  StoreStats _stats = StoreStats.empty;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() => _stats = _store.stats());

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TidyCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.info, size: 17, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '${Brand.name} keeps a record of what it removes — the path, '
                  'the size, and whether it went to the Trash or was deleted '
                  'outright — along with how full your disk has been over time. '
                  'It is what the Dashboard’s charts are drawn from. It is a '
                  'file on this Mac, it is never uploaded anywhere, and you can '
                  'export or erase it below.',
                  style: context.text.bodyM,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'What is stored',
          children: [
            SettingsLabel(
              title: 'Removal records',
              detail:
                  _store.isOpen
                      ? '${_stats.removedItemCount} files across '
                          '${_stats.operationCount} clean-ups, and '
                          '${_stats.scanCount} scans.'
                      : 'The history store could not be opened, so nothing is '
                          'being recorded. The rest of ${Brand.name} works as usual.',
            ),
            SettingsLabel(
              title: 'Measurements',
              detail:
                  '${_stats.bucketCount} readings of disk, memory and CPU. '
                  '${_since()}',
            ),
            SettingsLabel(
              title: 'On disk',
              detail:
                  '${formatBytes(_stats.fileSizeBytes)} in '
                  '~/Library/Application Support/${Brand.supportDirectoryName}/tidy.db',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'Your copy',
          children: [
            SettingsActionRow(
              title: 'Export the history',
              detail:
                  'Writes everything above to a JSON file next to the database, '
                  'and shows it to you in Finder.',
              actionLabel: 'Export',
              onPressed: _busy || !_store.isOpen ? null : _export,
            ),
            SettingsActionRow(
              title: 'Forget older records',
              detail:
                  'Drops the file-by-file records older than a year. The '
                  'clean-up totals and the charts are kept.',
              actionLabel: 'Trim',
              onPressed: _busy || !_store.isOpen ? null : _trim,
            ),
            SettingsActionRow(
              title: 'Erase the history',
              detail:
                  'Removes every record of what ${Brand.name} has done. The '
                  'Dashboard starts counting again from today.',
              actionLabel: 'Erase',
              destructive: true,
              onPressed: _busy || !_store.isOpen ? null : _clear,
            ),
          ],
        ),
      ],
    );
  }

  String _since() {
    final since = _stats.recordingSince;
    if (since == null) return 'Nothing recorded yet.';
    return 'Recording since ${since.day} ${_months[since.month - 1]} '
        '${since.year}.';
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final file = await _store.exportJson();
    if (!mounted) return;
    setState(() => _busy = false);

    if (file == null) {
      context.toastError('That export could not be written.');
      return;
    }
    await SystemBridge.revealInFinder(file.path);
    if (!mounted) return;
    context.toastSuccess(
      'Saved as ${file.uri.pathSegments.last}',
      title: 'History exported',
    );
  }

  Future<void> _trim() async {
    final ok = await TidyAlert.confirm(
      context,
      title: 'Forget records older than a year?',
      message:
          'The list of individual files removed before then is deleted. What '
          'each clean-up came to, and the charts, are kept.',
      confirmLabel: 'Forget them',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    final removed = _store.trimRemovedItems(const Duration(days: 365));
    setState(() => _busy = false);
    _refresh();
    if (!mounted) return;
    context.toastSuccess(
      removed == 0
          ? 'There was nothing older than a year.'
          : '$removed records removed.',
    );
  }

  Future<void> _clear() async {
    final ok = await TidyAlert.confirm(
      context,
      title: 'Erase everything ${Brand.name} has recorded?',
      message:
          'Every record of what was removed, every scan, and every '
          'measurement goes. Nothing on your Mac is touched — this is only '
          '${Brand.name}’s own memory of what it did. It cannot be undone.',
      confirmLabel: 'Erase',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    await _store.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    _refresh();
    context.toastSuccess('The history is empty. Recording starts again now.');
  }

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}
