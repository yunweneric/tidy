import 'dart:io';

/// Default number of concurrent shell-outs. Each unit of work is a short-lived
/// process, so this hides spawn latency without thrashing the disk.
const int kDefaultConcurrency = 8;

/// Size of a file or directory in bytes, via `du -sk`.
///
/// Kilobytes rather than `du -sh`: the human-readable form uses a localized
/// decimal separator and has to be parsed back, which is exactly the round-trip
/// that used to corrupt totals here.
Future<int> pathSizeBytes(String path) async {
  try {
    final result = await Process.run('du', ['-sk', path]);
    final firstField = result.stdout.toString().split(RegExp(r'\s+')).first;
    return (int.tryParse(firstField) ?? 0) * 1024;
  } catch (_) {
    return 0;
  }
}

/// Runs [task] over [items] with at most [limit] futures in flight, preserving
/// input order in the result.
Future<List<R>> mapPooled<T, R>(
  List<T> items,
  Future<R> Function(T) task, {
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

  final workers = limit.clamp(1, items.length);
  await Future.wait(List.generate(workers, (_) => worker()));
  return results.cast<R>();
}
