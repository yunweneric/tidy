import 'package:mac_uninstaller/core/platform/system_bridge.dart';

/// Default parallelism for [mapPooled].
const int kDefaultConcurrency = 8;

/// Allocated size of [path], including everything beneath it.
///
/// Prefer [pathSizes] when measuring more than one path — this convenience
/// wrapper costs a full channel round trip each time.
Future<int> pathSizeBytes(String path) async {
  final sizes = await pathSizes([path]);
  return sizes[path] ?? 0;
}

/// Allocated bytes for each of [paths], in one native call.
///
/// This used to spawn one `du -sk` process per path, which meant thousands of
/// process spawns for a single sweep of `~/Library` and made sizing far and away
/// the slowest thing in the app. The native side walks with `fts(3)` on a
/// background thread instead.
///
/// The figures are *allocated* size (`st_blocks * 512`), not logical size. On
/// APFS that distinction is worth real money: a sparse file like Docker's
/// `Docker.raw` reports 64 GB logically while occupying 8, and quoting the
/// logical number promises the user space that isn't there.
Future<Map<String, int>> pathSizes(List<String> paths) =>
    SystemBridge.sizeOfPaths(paths);

/// Maps [items] through [task] with at most [limit] running at once, preserving
/// order.
///
/// Still the right tool for anything the native side can't batch — per-item
/// plist reads, icon fetches, sub-scans.
Future<List<R>> mapPooled<T, R>(
  List<T> items,
  Future<R> Function(T item) task, {
  int limit = kDefaultConcurrency,
}) async {
  if (items.isEmpty) return <R>[];

  final results = List<R?>.filled(items.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= items.length) return;
      results[index] = await task(items[index]);
    }
  }

  await Future.wait([
    for (var i = 0; i < limit && i < items.length; i++) worker(),
  ]);

  return results.cast<R>();
}
