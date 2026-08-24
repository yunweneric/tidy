import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/data/services/apps_service.dart';
import 'package:mac_uninstaller/features/apps/data/services/junk_scanner.dart';
import 'package:mac_uninstaller/features/apps/data/services/scan_cache.dart';
import 'package:mac_uninstaller/features/apps/logic/app_event.dart';
import 'package:mac_uninstaller/features/apps/logic/app_states.dart';

/// Drives the application list: scan, refresh, uninstall, junk sweep.
///
/// Scanning is staged so the window is usable immediately — cached list, then
/// fresh metadata, then icons, then the (slower) junk sweep.
class AppsBloc extends Bloc<AppsEvent, AppsState> {
  AppsBloc(this.service, {ScanCache? cache, JunkScanner? junkScanner})
    : cache = cache ?? ScanCache(),
      junkScanner = junkScanner ?? JunkScanner(),
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
  Future<void> _onReconcile(ReconcileApps event, Emitter<AppsState> emit) async {
    final current = state;
    if (current is! AppsLoaded || current.apps.isEmpty) return;

    final surviving = current.apps
        .where((app) => Directory(app.path).existsSync())
        .toList();

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

    emit(current.copyWith(isRefreshing: true, clearOutcome: true));

    final result = await service.remove(event.paths, toTrash: event.toTrash);

    final removedPaths = result.removed.toSet();
    final removedApps = event.apps
        .where((app) => removedPaths.contains(app.path))
        .toList();

    final remaining = current.apps
        .where((app) => !removedApps.contains(app))
        .toList();

    if (removedApps.isNotEmpty) {
      await cache.removeApps(removedApps.map((app) => app.path));
    }

    final freed = _freedBytes(
      requested: event.paths,
      removed: removedPaths,
      expectedBytes: event.expectedBytes,
    );

    emit(
      current.copyWith(
        apps: remaining,
        disk: await SystemBridge.diskUsage(),
        isRefreshing: false,
        lastOutcome: RemovalOutcome(
          removedCount: removedApps.length,
          freedBytes: freed,
          failures: result.failures,
          movedToTrash: event.toTrash,
        ),
      ),
    );
  }

  Future<void> _onClearJunk(ClearJunkEvent event, Emitter<AppsState> emit) async {
    final current = state;
    if (current is! AppsLoaded) return;

    emit(current.copyWith(isScanningJunk: true, clearOutcome: true));

    final result = await service.remove(event.paths, toTrash: event.toTrash);
    final freed = _freedBytes(
      requested: event.paths,
      removed: result.removed.toSet(),
      expectedBytes: event.expectedBytes,
    );

    final junk = await junkScanner.scan(installedApps: current.apps);

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
