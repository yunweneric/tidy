import 'package:flutter/foundation.dart';
import 'package:tidy/core/models/clipboard_entry.dart';
import 'package:tidy/core/models/network_series.dart';
import 'package:tidy/core/models/trash_item.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/store/metric_sampler.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/core/vitals/process_sample.dart';
import 'package:tidy/core/vitals/system_vitals.dart';

/// The three counters the Dashboard wants out of the launch-items list.
///
/// A record rather than `LaunchItem`: dragging that model into `core/` to read
/// three numbers would be moving a feature's furniture to borrow a cup of sugar.
class LaunchItemFacts {
  const LaunchItemFacts({
    this.total = 0,
    this.enabled = 0,
    this.broken = 0,
  });

  static const LaunchItemFacts empty = LaunchItemFacts();

  final int total;
  final int enabled;

  /// Items whose program is missing or unreadable — the ones worth fixing.
  final int broken;
}

/// A snapshot of the installed-app inventory, read from the on-disk scan cache
/// rather than by scanning. The Dashboard must paint instantly.
class AppInventory {
  const AppInventory({
    this.count = 0,
    this.totalBytes = 0,
    this.unusedCount = 0,
    this.largest = const [],
    this.byDeveloper = const [],
    this.scannedAt,
  });

  static const AppInventory empty = AppInventory();

  final int count;
  final int totalBytes;

  /// Not opened in the last 180 days — the same threshold `UnusedAppsModule`
  /// uses, so the Dashboard and that scanner never disagree about "unused".
  final int unusedCount;

  final List<({String name, int bytes})> largest;
  final List<({String name, int bytes})> byDeveloper;

  final DateTime? scannedAt;

  bool get isKnown => scannedAt != null;
}

/// Everything the Dashboard reads, behind one door.
///
/// Owns no channels and imports no feature. Each live read arrives as a closure
/// supplied by `service_locator.dart` — the composition root, and the one place
/// allowed to know about both `core/` and every feature. `docs/feature.md` §2
/// is what forces this shape: a screen that aggregates eleven modules would
/// otherwise import eleven siblings.
///
/// Every read is individually guarded. A dashboard where one failing source
/// blanks the other nine is worse than one that admits it could not read the
/// Trash.
class DashboardRepository {
  DashboardRepository({
    required this.store,
    required Future<DiskUsage> Function() readDisk,
    required Future<SystemVitals> Function() readVitals,
    required Future<ProcessSnapshot> Function() readProcesses,
    required Future<TrashSnapshot> Function() readTrash,
    required Future<List<ClipboardEntry>> Function() readClips,
    required Future<NetworkHeadline> Function() readNetworkHeadline,
    required Future<NetworkSeries> Function(NetworkRange) readNetworkSeries,
    required Future<AppInventory> Function() readAppInventory,
    required Future<LaunchItemFacts> Function() readLaunchItems,
    required Future<bool> Function() readFullDiskAccess,
    MetricSampler? sampler,
  }) : _readDisk = readDisk,
       _readVitals = readVitals,
       _readProcesses = readProcesses,
       _readTrash = readTrash,
       _readClips = readClips,
       _readNetworkHeadline = readNetworkHeadline,
       _readNetworkSeries = readNetworkSeries,
       _readAppInventory = readAppInventory,
       _readLaunchItems = readLaunchItems,
       _readFullDiskAccess = readFullDiskAccess,
       _sampler = sampler;

  final TidyStore store;
  final MetricSampler? _sampler;

  final Future<DiskUsage> Function() _readDisk;
  final Future<SystemVitals> Function() _readVitals;
  final Future<ProcessSnapshot> Function() _readProcesses;
  final Future<TrashSnapshot> Function() _readTrash;
  final Future<List<ClipboardEntry>> Function() _readClips;
  final Future<NetworkHeadline> Function() _readNetworkHeadline;
  final Future<NetworkSeries> Function(NetworkRange) _readNetworkSeries;
  final Future<AppInventory> Function() _readAppInventory;
  final Future<LaunchItemFacts> Function() _readLaunchItems;
  final Future<bool> Function() _readFullDiskAccess;

  Future<DiskUsage?> disk() => _guard('disk usage', _readDisk);

  Future<SystemVitals?> vitals() => _guard('vitals', _readVitals);

  Future<ProcessSnapshot?> processes() => _guard('processes', _readProcesses);

  Future<bool?> fullDiskAccess() =>
      _guard('the Full Disk Access state', _readFullDiskAccess);

  Future<NetworkHeadline?> networkHeadline() =>
      _guard('network totals', _readNetworkHeadline);

  Future<NetworkSeries?> networkSeries(NetworkRange range) =>
      _guard('network history', () => _readNetworkSeries(range));

  Future<LaunchItemFacts?> launchItems() =>
      _guard('startup items', _readLaunchItems);

  /// The Trash, and a sample of its size while we have it.
  ///
  /// The sweep across every volume has already measured everything, so the
  /// trend line is one insert rather than a walk of its own.
  Future<TrashSnapshot?> trash() async {
    final snapshot = await _guard('the Trash', _readTrash);
    if (snapshot != null) _sampler?.recordTrashSize(snapshot.totalBytes);
    return snapshot;
  }

  /// The clipboard history, or null when it is switched off or unreadable.
  Future<List<ClipboardEntry>?> clips() => _guard('the clipboard', _readClips);

  /// The app inventory from cache, recording a daily snapshot as it goes.
  ///
  /// `AppsBloc` also records this, but it is created lazily by the Applications
  /// page — so on a Mac whose owner never opens that tab, this is the only
  /// thing that ever writes the row. `sampleDaily` keeps it to one a day
  /// whichever of them gets there first.
  Future<AppInventory?> apps() async {
    final inventory = await _guard('the app inventory', _readAppInventory);
    if (inventory != null && inventory.isKnown && inventory.count > 0) {
      _sampler?.recordAppInventory(
        appCount: inventory.count,
        totalBytes: inventory.totalBytes,
      );
    }
    return inventory;
  }

  /// Null on failure rather than a thrown exception or an empty value: the
  /// caller has to be able to tell "could not read" from "read, and it is
  /// empty", because the second is a fact and the first is not.
  Future<T?> _guard<T>(String what, Future<T> Function() read) async {
    try {
      return await read();
    } catch (e) {
      debugPrint('Dashboard could not read $what: $e');
      return null;
    }
  }
}
