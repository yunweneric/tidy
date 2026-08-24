import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/scanning/logic/scan_state.dart';
import 'package:tidy/core/scanning/presentation/scan_hero.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/tidy_card.dart';

/// What the scanner is doing right now, under the hero.
///
/// A scan of `~/Library` takes tens of seconds, and for most of it the ring is
/// the only thing moving. That proves the app is alive; it does not show that
/// it is getting anywhere. This does — a count that climbs, a size that grows,
/// and the last few places it looked, so you can watch it walk through Caches,
/// then Logs, then Containers.
///
/// It says "places checked" rather than a percentage whenever the total is not
/// knowable. A filesystem walk usually cannot know its own total until it has
/// finished walking, and a percentage invented from nothing is worse than an
/// honest count — a bar that sticks at 80% is how progress loses its meaning.
class ScanProgressPanel extends StatelessWidget {
  const ScanProgressPanel({super.key, required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final fraction = state.fraction;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: TidyCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: AppRadii.xsAll,
                child: LinearProgressIndicator(
                  // Null drives the indeterminate sweep. Under Reduce Motion
                  // that is a bar that never stops moving and never means
                  // anything, so it is pinned flat instead and the counts below
                  // carry the progress on their own.
                  value: fraction ?? (motion.reduced ? 0 : null),
                  minHeight: 4,
                  backgroundColor: colors.surfaceHover,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _Counts(state: state, fraction: fraction),
              if (state.recentPaths.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: colors.border),
                const SizedBox(height: AppSpacing.md),
                _RecentPaths(paths: state.recentPaths),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.state, required this.fraction});

  final ScanState state;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final checked = state.visitedCount;

    return Row(
      children: [
        Expanded(
          child: Text(
            checked == 0
                ? 'Starting…'
                : '$checked place${checked == 1 ? '' : 's'} checked',
            style: context.text.bodyM.copyWith(color: colors.textPrimary),
          ),
        ),
        if (state.totalBytes > 0)
          Text(
            '${formatBytes(state.totalBytes)} found',
            style: context.text.titleS.copyWith(color: colors.safe),
          ),
        if (fraction != null) ...[
          const SizedBox(width: AppSpacing.md),
          Text(
            '${(fraction!.clamp(0.0, 1.0) * 100).round()}%',
            style: context.text.titleS,
          ),
        ],
      ],
    );
  }
}

/// The last few places, newest at the top and fading downward.
///
/// A fixed number of rows, always: letting the list grow into place makes the
/// panel jump every time a scan starts, and the hero above it moves with it.
class _RecentPaths extends StatelessWidget {
  const _RecentPaths({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < ScanState.recentPathLimit; i++)
          SizedBox(
            height: 18,
            child:
                i < paths.length
                    ? Opacity(
                      // The newest line is the one being worked on; the rest are
                      // there for the sense of movement, not to be read closely.
                      opacity:
                          i == 0
                              ? 1
                              : (1 - (i / ScanState.recentPathLimit)) * 0.7,
                      child: Row(
                        children: [
                          Icon(
                            i == 0 ? AppIcons.forward : AppIcons.check,
                            size: 11,
                            color: i == 0 ? colors.textSecondary : colors.safe,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              shortenPath(paths[i], limit: 72),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              // Right-to-left so a long path truncates at the
                              // front: the informative end of a path is the tail.
                              textDirection: TextDirection.rtl,
                              style: context.text.mono,
                            ),
                          ),
                        ],
                      ),
                    )
                    : null,
          ),
      ],
    );
  }
}
