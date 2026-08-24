import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mac_uninstaller/core/scanning/domain/scan_module.dart';
import 'package:mac_uninstaller/core/scanning/domain/scan_node.dart';

/// Runs several modules as one scan and merges their findings.
///
/// Children run concurrently and each emission re-merges whatever every child
/// has produced so far, so results fill in as they land rather than waiting on
/// the slowest member.
///
/// The merge is not a concatenation. Two modules can legitimately find the same
/// path — an orphaned cache folder is both "junk" and "left over from an app you
/// removed" — and letting both keep it would double-count the bytes and hand the
/// same path to removal twice. Earlier modules win; see [_deduplicate].
class CompositeScanModule implements ScanModule {
  CompositeScanModule({
    required this.id,
    required this.icon,
    required this.modules,
  });

  @override
  final ModuleId id;

  @override
  final IconData icon;

  /// Order matters: when two modules claim a path, the earlier one keeps it.
  final List<ScanModule> modules;

  @override
  bool get needsFullDiskAccess =>
      modules.any((module) => module.needsFullDiskAccess);

  @override
  bool get mayNeedAdmin => modules.any((module) => module.mayNeedAdmin);

  @override
  Stream<ScanProgress> scan(ScanRequest request) {
    if (modules.isEmpty) return Stream.value(const ScanProgress.done([]));

    final controller = StreamController<ScanProgress>();
    final subscriptions = <StreamSubscription<ScanProgress>>[];
    final latest = <ModuleId, ScanProgress>{};
    var running = modules.length;

    void publish() {
      if (controller.isClosed) return;

      final roots = <ScanNode>[];
      for (final module in modules) {
        final progress = latest[module.id];
        if (progress == null) continue;
        // Node ids are already module-namespaced by convention
        // (`cleanup:caches`, `unusedApps:<path>`), so roots from different
        // modules cannot collide.
        roots.addAll(progress.roots);
      }

      final merged = _deduplicate(roots);
      final done = running == 0;

      // Children that cannot know their own totals report null; averaging what
      // we do have is more honest than inventing a denominator.
      final fractions = latest.values
          .map((progress) => progress.fraction)
          .whereType<double>()
          .toList();
      final fraction = done
          ? 1.0
          : (fractions.length == modules.length
                ? fractions.reduce((a, b) => a + b) / modules.length
                : null);

      controller.add(
        ScanProgress(
          roots: merged,
          fraction: fraction,
          currentPath: done
              ? null
              : latest.values
                    .where((progress) => !progress.done)
                    .map((progress) => progress.currentPath)
                    .whereType<String>()
                    .firstOrNull,
          done: done,
          skippedForPermission:
              latest.values.any((progress) => progress.skippedForPermission),
        ),
      );

      if (done) controller.close();
    }

    for (final module in modules) {
      subscriptions.add(
        module.scan(request).listen(
          (progress) {
            latest[module.id] = progress;
            publish();
          },
          // One module failing must not take the whole sweep with it: record
          // what it managed and let the others finish.
          onError: (Object _) {
            latest[module.id] = ScanProgress.done(
              latest[module.id]?.roots ?? const [],
            );
            running--;
            publish();
          },
          onDone: () {
            running--;
            publish();
          },
          cancelOnError: true,
        ),
      );
    }

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };

    return controller.stream;
  }

  /// Drops leaves whose paths an earlier root already claimed, then drops any
  /// group left empty by that.
  static List<ScanNode> _deduplicate(List<ScanNode> roots) {
    final claimed = <String>{};

    ScanNode? prune(ScanNode node) {
      if (node.isLeaf) {
        if (node.paths.isEmpty) return node;
        if (node.paths.any(claimed.contains)) return null;
        claimed.addAll(node.paths);
        return node;
      }

      final children = node.children.map(prune).whereType<ScanNode>().toList();
      return children.isEmpty ? null : node.copyWith(children: children);
    }

    return roots.map(prune).whereType<ScanNode>().toList();
  }
}
