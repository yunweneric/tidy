import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/dashboard/logic/dashboard_state.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';

/// The counters, each one a way into the module behind it.
///
/// Every tile is a link as well as a number. A dashboard that shows you a
/// problem and then makes you find the screen that fixes it has done half a job.
class DashboardCounters extends StatelessWidget {
  const DashboardCounters({
    super.key,
    required this.state,
    required this.onOpen,
  });

  final DashboardState state;
  final ValueChanged<AppDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tiles = <Widget>[
      StatTile(
        label: 'Applications',
        value: state.apps.isKnown ? '${state.apps.count}' : '—',
        detail:
            state.apps.isKnown
                ? '${formatBytes(state.apps.totalBytes)} · '
                    '${state.apps.unusedCount} unused for 6 months'
                : 'Open Applications to take stock',
        icon: AppIcons.applications,
        color: colors.info,
        onTap: () => onOpen(AppDestination.applications),
      ),
      StatTile(
        label: 'Reclaimable junk',
        // Null is "no scan has run", and it says so. A confident `0 B` from a
        // scan that never happened is the same lie as a virus checker
        // reporting no threats without looking.
        value:
            state.junkBytes == null
                ? 'Not scanned'
                : formatBytes(state.junkBytes!),
        detail:
            state.junkBytes == null
                ? 'Run a scan to find out'
                : 'Caches, logs, saved state and build output',
        icon: AppIcons.cleanup,
        color: colors.safe,
        onTap: () => onOpen(AppDestination.smartCare),
      ),
      StatTile(
        label: 'In the Trash',
        value: state.trash == null ? '—' : formatBytes(state.trash!.totalBytes),
        detail:
            state.trash == null
                ? 'Could not read the Trash'
                : '${state.trash!.items.length} items · '
                    '${state.staleTrashCount} older than a month',
        icon: AppIcons.recycleBin,
        color: colors.review,
        onTap: () => onOpen(AppDestination.recycleBin),
      ),
      StatTile(
        label: 'Clipboard',
        value: state.clips == null ? '—' : '${state.clips!.length}',
        detail:
            state.clips == null
                ? 'History is off, or unreadable'
                : '${formatBytes(state.clipboardBytes)} held · '
                    '${state.pinnedClips} pinned',
        icon: AppIcons.clipboard,
        color: colors.accent,
        onTap: () => onOpen(AppDestination.clipboard),
      ),
      StatTile(
        label: 'Network today',
        value:
            state.networkHeadline == null
                ? '—'
                : formatBytes(state.networkHeadline!.todayBytes),
        detail:
            state.networkHeadline == null
                ? 'Nothing recorded yet'
                : '${formatBytes(state.networkHeadline!.todayDownBytes)} down · '
                    '${formatBytes(state.networkHeadline!.todayUpBytes)} up',
        icon: AppIcons.network,
        color: colors.downstream,
        onTap: () => onOpen(AppDestination.network),
      ),
      StatTile(
        label: 'Startup items',
        value:
            state.launchStatus == SectionStatus.ready
                ? '${state.launchItems.total}'
                : '—',
        detail:
            state.launchStatus == SectionStatus.ready
                ? '${state.launchItems.enabled} enabled · '
                    '${state.launchItems.broken} broken'
                : 'Reading launch agents…',
        icon: AppIcons.performance,
        color: state.launchItems.broken > 0 ? colors.review : colors.safe,
        onTap: () => onOpen(AppDestination.performance),
      ),
    ];

    // The grid idiom from `result_tiles.dart`: columns from the width rather
    // than a fixed Row, so six tiles still fit at the 1100px minimum window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 260).floor().clamp(1, 3);
        const gap = AppSpacing.lg;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }
}
