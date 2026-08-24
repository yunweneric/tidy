import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/store/metric_sampler.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/features/apps/data/models/mac_app_model.dart';
import 'package:tidy/features/apps/data/models/removal_progress.dart';
import 'package:tidy/features/apps/data/services/apps_service.dart';
import 'package:tidy/features/apps/data/services/junk_scanner.dart';
import 'package:tidy/features/apps/data/services/scan_cache.dart';
import 'package:tidy/features/apps/logic/app_event.dart';
import 'package:tidy/features/apps/logic/app_states.dart';

/// Drives the application list: scan, refresh, uninstall, junk sweep.
///
/// Scanning is staged so the window is usable immediately — cached list, then
/// fresh metadata, then icons, then the (slower) junk sweep.
class AppsBloc extends Bloc<AppsEvent, AppsState> {
  AppsBloc(
    this.service, {
    ScanCache? cache,
    JunkScanner? junkScanner,
    TidyStore? store,
    MetricSampler? sampler,
  }) : cache = cache ?? ScanCache(),
       junkScanner = junkScanner ?? JunkScanner(),
       _store = store,
       _sampler = sampler,
       super(AppsInitial()) {
    on<LoadApps>(_onLoadApps);
    on<RefreshApps>(_onRefresh);
    on<ReconcileApps>(_onReconcile);
    on<UninstallAppsEvent>(_onUninstall);
    on<ClearJunkEvent>(_onClearJunk);
  }

  final AppManagerService service;
  final ScanCache cache;
  final JunkScanner junkScanner;

  /// Where uninstalls are written down. Null means they simply are not.
  final TidyStore? _store;
  final MetricSampler? _sampler;

  Future<void> _onLoadApps(LoadApps event, Emitter<AppsState> emit) async {
    if (event.useCache) {
      final cached = await cache.read();
      if (cached != null && cached.apps.isNotEmpty) {
        emit(
          AppsLoaded(
            apps: cached.apps,
            isRefreshing: true,
            scannedAt: cached.scannedAt,
          ),
        );
      } else {
        emit(AppsLoading());
      }
    } else {
      emit(AppsLoading());
    }

    await _scan(emit);
  }

  Future<void> _onRefresh(RefreshApps event, Emitter<AppsState> emit) async {
    final current = state;
    if (current is AppsLoaded) {
      emit(current.copyWith(isRefreshing: true, clearOutcome: true));
    } else {
      emit(AppsLoading());
    }
    await _scan(emit);
  }

  /// Drops apps whose bundle is gone, e.g. uninstalled from the popover while
  /// this window was in the background.
  Future<void> _onReconcile(
    ReconcileApps event,
    Emitter<AppsState> emit,
  ) async {
    final current = state;
    if (current is! AppsLoaded || current.apps.isEmpty) return;

    final surviving =
        current.apps.where((app) => Directory(app.path).existsSync()).toList();

    if (surviving.length == current.apps.length) return;

    await cache.write(surviving);
    emit(
      current.copyWith(
        apps: surviving,
        disk: await SystemBridge.diskUsage(),
        clearOutcome: true,
      ),
    );
  }

  /// Full scan pipeline. Every stage emits so the UI fills in progressively.
  Future<void> _scan(Emitter<AppsState> emit) async {
    try {
      final disk = await SystemBridge.diskUsage();
      var apps = await service.scanApps();

      emit(
        AppsLoaded(
          apps: apps,
          disk: disk,
          junk: _currentJunk,
          isRefreshing: true,
          isScanningJunk: true,
          scannedAt: DateTime.now(),
        ),
      );

      // Icons first: they are a handful of quick channel calls and they are
      // what makes the list look like the user's own Mac rather than a table.
      await for (final withIcons in service.attachIcons(apps)) {
        apps = withIcons;
        emit(
          AppsLoaded(
            apps: apps,
            disk: disk,
            junk: _currentJunk,
            isRefreshing: true,
            isScanningJunk: true,
            scannedAt: DateTime.now(),
          ),
        );
      }

      // Sizes last of the app passes: measuring a bundle means walking every
      // file in it, and one Xcode is worth every other app combined. Streaming
      // them means the list is usable long before the total is exact.
      await for (final withSizes in service.attachSizes(apps)) {
        apps = withSizes;
        emit(
          AppsLoaded(
            apps: apps,
            disk: disk,
            junk: _currentJunk,
            isRefreshing: true,
            isScanningJunk: true,
            scannedAt: DateTime.now(),
          ),
        );
      }

      await cache.write(apps);

      // A daily snapshot of the inventory, so "apps installed" becomes a line
      // rather than a number. `ScanCache` overwrites itself every scan, so
      // without this the history is lost as fast as it is made. The sampler
      // keeps it to one row a day whatever we call it.
      _sampler?.recordAppInventory(
        appCount: apps.length,
        totalBytes: apps.fold<int>(0, (sum, app) => sum + app.sizeBytes),
      );

      emit(
        AppsLoaded(
          apps: apps,
          disk: disk,
          junk: _currentJunk,
          isScanningJunk: true,
          scannedAt: DateTime.now(),
        ),
      );

      // The junk sweep walks ~/Library and is the slowest stage, so it lands last.
      final junk = await junkScanner.scan(installedApps: apps);
      _sampler?.recordJunkFound(junk.totalBytes);
      emit(
        AppsLoaded(
          apps: apps,
          disk: disk,
          junk: junk,
          scannedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      final current = state;
      if (current is AppsLoaded && current.apps.isNotEmpty) {
        // Keep whatever is on screen; a failed refresh should not blank the app.
        emit(current.copyWith(isRefreshing: false, isScanningJunk: false));
      } else {
        emit(AppsError('Could not scan your applications.\n$e'));
      }
    }
  }

  JunkReport get _currentJunk {
    final current = state;
    return current is AppsLoaded ? current.junk : JunkReport.empty;
  }

  Future<void> _onUninstall(
    UninstallAppsEvent event,
    Emitter<AppsState> emit,
  ) async {
    final current = state;
    if (current is! AppsLoaded) return;

    // The outcome is cleared before anything runs: the confirm dialog closes
    // itself the moment one appears, and a leftover from the previous removal
    // would slam it shut before this one had started.
    emit(
      current.copyWith(
        isRefreshing: true,
        clearOutcome: true,
        removal: RemovalProgress(
          completed: 0,
          total: event.paths.length,
          movedToTrash: event.toTrash,
        ),
      ),
    );

    // Measured before anything is removed — afterwards the paths are gone (or
    // moved), and a size read then is a size read of nothing. One batched
    // `fts` walk on a background thread, which is why `sizeOfPaths` exists and
    // why this is not a loop over `pathSizeBytes`.
    final sizes = await _sizesFor(event);
    final operationId = _store?.beginOperation(
      OperationDraft(
        kind: OperationKind.uninstall,
        label: _uninstallLabel(event.apps),
      ),
    );

    final result = await service.remove(
      event.paths,
      toTrash: event.toTrash,
      // Emitting from the callback is legal while the handler is still
      // awaiting, and it is what puts a moving bar in front of the user during
      // the seconds a large bundle takes to trash.
      onProgress: (completed, total, currentPath) {
        final live = state;
        if (emit.isDone || live is! AppsLoaded) return;
        emit(
          live.copyWith(
            removal: RemovalProgress(
              completed: completed,
              total: total,
              movedToTrash: event.toTrash,
              currentLabel: currentPath == null ? null : _basename(currentPath),
            ),
          ),
        );
      },
    );

    final removedPaths = result.removed.toSet();
    final removedApps =
        event.apps.where((app) => removedPaths.contains(app.path)).toList();

    // `current` is the pre-removal snapshot and the progress emits have since
    // replaced the live state. Build on the live one so nothing that landed
    // mid-removal is thrown away.
    final live = state;
    final base = live is AppsLoaded ? live : current;

    final remaining =
        base.apps.where((app) => !removedApps.contains(app)).toList();

    if (removedApps.isNotEmpty) {
      await cache.removeApps(removedApps.map((app) => app.path));
    }

    final freed = _freedBytes(
      requested: event.paths,
      removed: removedPaths,
      expectedBytes: event.expectedBytes,
    );

    _record(
      operationId: operationId,
      removed: removedPaths,
      sizes: sizes,
      categoryOf:
          (path) => _isBundle(path, event.apps) ? 'Application' : 'Leftovers',
      nameOf: (path) => _nameFor(path, event.apps),
      toTrash: event.toTrash,
      failureCount: result.failures.length,
    );

    emit(
      base.copyWith(
        apps: remaining,
        disk: await SystemBridge.diskUsage(),
        isRefreshing: false,
        clearRemoval: true,
        lastOutcome: RemovalOutcome(
          removedCount: removedApps.length,
          freedBytes: freed,
          failures: result.failures,
          movedToTrash: event.toTrash,
        ),
      ),
    );
  }

  /// `~/Library/Caches/com.acme.Widget` → `com.acme.Widget`. Enough to say what
  /// is going without a path the dialog has no room for.
  static String _basename(String path) {
    final cut = path.lastIndexOf('/');
    return cut < 0 || cut == path.length - 1 ? path : path.substring(cut + 1);
  }

  Future<void> _onClearJunk(
    ClearJunkEvent event,
    Emitter<AppsState> emit,
  ) async {
    final current = state;
    if (current is! AppsLoaded) return;

    emit(current.copyWith(isScanningJunk: true, clearOutcome: true));

    // The junk report already measured every one of these, so unlike an
    // uninstall this needs no second walk of the disk.
    final byPath = {
      for (final group in current.junk.groups)
        for (final item in group.items) item.path: item,
    };

    final operationId = _store?.beginOperation(
      const OperationDraft(
        kind: OperationKind.cleanup,
        label: 'Caches, logs and leftovers',
      ),
    );

    final result = await service.remove(event.paths, toTrash: event.toTrash);
    final removedPaths = result.removed.toSet();

    _record(
      operationId: operationId,
      removed: removedPaths,
      sizes: {
        for (final entry in byPath.entries) entry.key: entry.value.sizeBytes,
      },
      categoryOf: (path) => byPath[path]?.kind.label ?? 'Other',
      nameOf: (path) => byPath[path]?.label ?? _basename(path),
      toTrash: event.toTrash,
      failureCount: result.failures.length,
    );

    final freed = _freedBytes(
      requested: event.paths,
      removed: removedPaths,
      expectedBytes: event.expectedBytes,
    );

    final junk = await junkScanner.scan(installedApps: current.apps);
    _sampler?.recordJunkFound(junk.totalBytes);

    emit(
      current.copyWith(
        junk: junk,
        disk: await SystemBridge.diskUsage(),
        isScanningJunk: false,
        lastOutcome: RemovalOutcome(
          removedCount: result.removed.length,
          freedBytes: freed,
          failures: result.failures,
          movedToTrash: event.toTrash,
        ),
      ),
    );
  }

  /// Measures everything an uninstall is about to remove.
  ///
  /// App bundles are already sized in the inventory; only the leftovers need a
  /// walk, and they go in one batched native call rather than one per path.
  Future<Map<String, int>> _sizesFor(UninstallAppsEvent event) async {
    if (_store == null) return const {};

    final sizes = <String, int>{};
    final bundles = {for (final app in event.apps) app.path: app.sizeBytes};

    final unknown = <String>[];
    for (final path in event.paths) {
      final known = bundles[path];
      if (known != null) {
        sizes[path] = known;
      } else {
        unknown.add(path);
      }
    }

    if (unknown.isEmpty) return sizes;

    try {
      sizes.addAll(await SystemBridge.sizeOfPaths(unknown));
    } catch (_) {
      // A size we could not read is not a reason to abandon the record. The
      // row still says the file went; it just cannot say how big it was.
    }
    return sizes;
  }

  /// Writes down what actually left the disk.
  void _record({
    required int? operationId,
    required Set<String> removed,
    required Map<String, int> sizes,
    required String Function(String path) categoryOf,
    required String Function(String path) nameOf,
    required bool toTrash,
    required int failureCount,
  }) {
    final store = _store;
    if (store == null || operationId == null) return;

    final at = DateTime.now();
    final items = <RemovedItemDraft>[];
    var bytes = 0;

    for (final path in removed) {
      final size = sizes[path] ?? 0;
      bytes += size;
      items.add(
        RemovedItemDraft(
          path: path,
          name: nameOf(path),
          sizeBytes: size,
          trashed: toTrash,
          category: categoryOf(path),
          at: at,
        ),
      );
    }

    store
      ..recordRemovedItems(operationId, items)
      ..finishOperation(
        operationId,
        OperationOutcome(
          // Kept apart deliberately: trashing frees nothing until the Trash is
          // emptied, so only a permanent delete may be counted as space back.
          bytesTrashed: toTrash ? bytes : 0,
          bytesDeleted: toTrash ? 0 : bytes,
          itemCount: items.length,
          failureCount: failureCount,
        ),
      );
    unawaited(_sampler?.sampleDiskNow() ?? Future<void>.value());
  }

  /// "Xcode", or "3 apps" — the Activity feed reads better naming one thing
  /// than listing five.
  static String _uninstallLabel(List<MacApp> apps) => switch (apps.length) {
    0 => 'Leftovers',
    1 => apps.first.name,
    _ => '${apps.length} apps',
  };

  static bool _isBundle(String path, List<MacApp> apps) =>
      apps.any((app) => app.path == path);

  static String _nameFor(String path, List<MacApp> apps) {
    for (final app in apps) {
      if (app.path == path) return app.name;
    }
    return _basename(path);
  }

  /// Pro-rates the previewed total when only some paths were removed.
  static int _freedBytes({
    required List<String> requested,
    required Set<String> removed,
    required int expectedBytes,
  }) {
    if (requested.isEmpty) return 0;
    if (removed.length == requested.length) return expectedBytes;
    return (expectedBytes * removed.length / requested.length).round();
  }
}

/// Convenience for the uninstall flow: every path a removal should touch.
List<String> uninstallPaths(MacApp app, Iterable<String> leftoverPaths) => [
  app.path,
  ...leftoverPaths,
];
