import 'dart:async';

import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/core/vitals/system_vitals.dart';

/// Writes the machine's vital signs into [TidyStore] so the Dashboard has
/// something to draw a line through.
///
/// **One owner.** Both Flutter engines could run this, and both would write the
/// same minute — so only the main window starts it (see `setUpLocator`'s
/// `includeUi`). The popover never opens the store at all, so it neither reads
/// nor samples; `_store.isOpen` is false there and every call below returns
/// early.
///
/// Deliberately cheap. The roadmap's warning is the design constraint here: a
/// menu-bar app burning 3% CPU while idle gets uninstalled, and statistics are
/// not worth a fan. Two timers, both reading values the OS already has;
/// everything else is recorded opportunistically by whoever computed it for
/// another reason.
class MetricSampler {
  MetricSampler({required TidyStore store}) : _store = store;

  final TidyStore _store;

  /// Vitals are cheap — one `host_statistics64`-shaped call. A minute is fine
  /// resolution for a chart nobody watches in real time; the Performance page
  /// polls at 2s when you are actually looking at it.
  static const Duration _vitalsInterval = Duration(minutes: 1);

  /// Disk usage barely moves, and `statfs` is not free on a busy volume.
  static const Duration _diskInterval = Duration(minutes: 5);

  /// Fold aged-out samples down a tier about once an hour. Cheap, and it keeps
  /// the minute tier from being 48h+ deep if the Mac never sleeps.
  static const Duration _compactInterval = Duration(hours: 1);

  Timer? _vitalsTimer;
  Timer? _diskTimer;
  Timer? _compactTimer;
  bool _running = false;

  Future<SystemVitals> Function()? _readVitals;

  /// [readVitals] is injected rather than imported: `PerformanceBridge` lives in
  /// a feature, and `docs/feature.md` §2 does not let `core/` reach into one.
  /// The composition root supplies it.
  void start({required Future<SystemVitals> Function() readVitals}) {
    if (_running || !_store.isOpen) return;
    _running = true;
    _readVitals = readVitals;

    // Sample immediately so a short session still leaves a mark. An app opened
    // for two minutes a day would otherwise record nothing, ever.
    unawaited(_sampleDisk());
    unawaited(_sampleVitals());

    _vitalsTimer = Timer.periodic(_vitalsInterval, (_) => _sampleVitals());
    _diskTimer = Timer.periodic(_diskInterval, (_) => _sampleDisk());
    _compactTimer = Timer.periodic(_compactInterval, (_) => _store.compact());
  }

  void stop() {
    _vitalsTimer?.cancel();
    _diskTimer?.cancel();
    _compactTimer?.cancel();
    _vitalsTimer = null;
    _diskTimer = null;
    _compactTimer = null;
    _running = false;
  }

  /// Records disk usage now. Called on the timer, and worth calling again right
  /// after a removal — that is the one moment the number actually jumps, and
  /// waiting five minutes to notice makes the chart look like nothing happened.
  Future<void> _sampleDisk() async {
    if (!_store.isOpen) return;
    try {
      final disk = await SystemBridge.diskUsage();
      if (disk.totalBytes <= 0) return;
      _store
        ..sample(MetricSeries.diskFree, disk.freeBytes.toDouble())
        ..sample(MetricSeries.diskTotal, disk.totalBytes.toDouble());
    } catch (e) {
      AppLog.metrics.failed('sample disk usage', e);
    }
  }

  Future<void> sampleDiskNow() => _sampleDisk();

  Future<void> _sampleVitals() async {
    final read = _readVitals;
    if (read == null || !_store.isOpen) return;

    try {
      final vitals = await read();

      // Nullable-by-absence throughout `SystemVitals`, and respected here: a
      // CPU reading that has not arrived is not 0%, and recording it as one
      // puts a fictional trough in the chart forever.
      final cpu = vitals.cpuPercent;
      if (cpu != null) _store.sample(MetricSeries.cpuPercent, cpu);

      final pressure = vitals.memoryPressurePercent;
      if (pressure != null) {
        _store.sample(MetricSeries.memoryPressure, pressure);
      }

      if (vitals.memoryTotalBytes > 0) {
        _store.sample(
          MetricSeries.memoryUsed,
          vitals.memoryUsedBytes.toDouble(),
        );
      }
      if (vitals.swapTotalBytes > 0) {
        _store.sample(MetricSeries.swapUsed, vitals.swapUsedBytes.toDouble());
      }

      // Stored as its index so the chart can show "how often was this Mac hot".
      _store.sample(MetricSeries.thermal, vitals.thermal.index.toDouble());
    } catch (e) {
      AppLog.metrics.failed('sample the system vitals', e);
    }
  }

  /// Records the installed-app figures, at most once a day.
  ///
  /// Straight into the day tier: this is a daily fact, and putting it through
  /// the minute tier would let compaction average it with nothing.
  void recordAppInventory({required int appCount, required int totalBytes}) {
    if (!_store.isOpen) return;
    if (_store.hasDailySample(MetricSeries.appCount)) return;
    _store
      ..sampleDaily(MetricSeries.appCount, appCount.toDouble())
      ..sampleDaily(MetricSeries.appBytes, totalBytes.toDouble());
  }

  /// Records what a scan found, whenever one happens to have run. Nothing
  /// starts a scan for the sake of this.
  void recordJunkFound(int bytes) {
    if (!_store.isOpen) return;
    _store.sample(MetricSeries.junkBytes, bytes.toDouble());
  }

  void recordTrashSize(int bytes) {
    if (!_store.isOpen) return;
    _store.sample(MetricSeries.trashBytes, bytes.toDouble());
  }
}
