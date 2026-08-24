import 'package:get_it/get_it.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/insights/dashboard_repository.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/store/metric_sampler.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/core/updates/update_service.dart';
import 'package:tidy/features/apps/data/services/apps_service.dart';
import 'package:tidy/features/apps/data/services/junk_scanner.dart';
import 'package:tidy/features/apps/data/services/leftover_scanner.dart';
import 'package:tidy/features/apps/data/services/scan_cache.dart';
import 'package:tidy/features/apps/data/services/unused_apps_module.dart';
import 'package:tidy/features/cleanup/data/cleanup_scan_module.dart';
import 'package:tidy/features/clipboard/data/services/clipboard_service.dart';
import 'package:tidy/features/network/data/services/network_service.dart';
import 'package:tidy/features/performance/data/services/launch_items_service.dart';
import 'package:tidy/features/performance/data/services/maintenance_service.dart';
import 'package:tidy/features/performance/data/services/process_monitor_service.dart';
import 'package:tidy/features/recycle_bin/data/services/recycle_bin_service.dart';
import 'package:tidy/features/performance/data/models/launch_item.dart';
import 'package:tidy/features/performance/data/services/performance_bridge.dart';
import 'package:tidy/features/recycle_bin/data/services/recycle_bin_service.dart'
    show RecycleBinService;
import 'package:tidy/features/smart_care/data/smart_care_module.dart';

final GetIt locator = GetIt.instance;

/// Wires up services for one Flutter engine.
///
/// Called once per engine, not once per app: the menu-bar popover runs in a
/// second engine with its own Dart isolate, so it needs its own registry. That
/// engine previously hand-constructed four services as widget fields, which
/// quietly gave the popover different scanner instances to the main window.
Future<void> setUpLocator({required bool includeUi}) async {
  if (locator.isRegistered<AppManagerService>()) return;

  // ─── Platform ────────────────────────────────────────────────────────────
  locator.registerLazySingleton<FullDiskAccessService>(
    FullDiskAccessService.new,
  );

  // ─── History store ───────────────────────────────────────────────────────
  // Registered for both engines so that anything resolving it compiles in
  // either, but **opened by neither unless `includeUi`** — see below. Hive has
  // no cross-isolate locking, so the popover engine opening the same boxes as
  // the window would be two writers on one file. In the popover the store
  // simply stays closed and every call on it is a no-op.
  locator.registerSingleton<TidyStore>(TidyStore());

  // ─── Data ────────────────────────────────────────────────────────────────
  locator.registerLazySingleton<ScanCache>(ScanCache.new);
  locator.registerLazySingleton<AppManagerService>(AppManagerService.new);
  locator.registerLazySingleton<JunkScanner>(JunkScanner.new);
  locator.registerLazySingleton<LeftoverScanner>(LeftoverScanner.new);

  // ─── Scan modules ────────────────────────────────────────────────────────
  locator.registerLazySingleton<CleanupScanModule>(
    () => CleanupScanModule(
      scanner: locator<JunkScanner>(),
      apps: locator<AppManagerService>(),
      cache: locator<ScanCache>(),
    ),
  );

  locator.registerLazySingleton<UnusedAppsModule>(
    () => UnusedAppsModule(
      apps: locator<AppManagerService>(),
      leftovers: locator<LeftoverScanner>(),
      cache: locator<ScanCache>(),
    ),
  );

  // Composite: owns no scanning of its own, just fans out to the others.
  locator.registerLazySingleton<SmartCareModule>(
    () => SmartCareModule(
      cleanup: locator<CleanupScanModule>(),
      unusedApps: locator<UnusedAppsModule>(),
    ),
  );

  // ─── Performance ─────────────────────────────────────────────────────────
  // Singletons rather than per-page instances: each holds an icon cache, and
  // rebuilding that every time the user switches tabs is visible.
  locator.registerLazySingleton<LaunchItemsService>(LaunchItemsService.new);
  locator.registerLazySingleton<MaintenanceService>(
    () => MaintenanceService(store: locator<TidyStore>()),
  );
  locator.registerLazySingleton<ProcessMonitorService>(
    ProcessMonitorService.new,
  );

  // ─── Recycle Bin ─────────────────────────────────────────────────────────
  locator.registerLazySingleton<RecycleBinService>(RecycleBinService.new);

  // ─── Clipboard ───────────────────────────────────────────────────────────
  // The history itself is native — see ClipboardBridge for why — so this holds
  // only an image cache and the settings mirror.
  locator.registerLazySingleton<ClipboardService>(ClipboardService.new);

  // ─── Network ─────────────────────────────────────────────────────────────
  // Same shape as Clipboard: the sampler and the history are native, so this
  // holds the per-range cache and the settings mirror.
  locator.registerLazySingleton<NetworkService>(NetworkService.new);

  // The popover has no settings UI and no theme switcher, so it skips the
  // file read entirely.
  if (includeUi) {
    final settings = await AppSettings.load();
    locator.registerSingleton<AppSettings>(settings);

    // Opened before the first frame so the Dashboard never has to render an
    // "opening the store" state, and only here — this is the `includeUi` branch,
    // so the popover engine never reaches it. Failure is survivable by design:
    // the store stays closed, every call on it becomes a no-op, and the app
    // loses its charts rather than its ability to run.
    await locator<TidyStore>().open();

    // ─── Updates ───────────────────────────────────────────────────────────
    // `includeUi` only, and for two reasons: it needs `AppSettings`, and the
    // popover must never start an install. That panel closes on the first click
    // outside it, and an update that quits the app from a window which has
    // already vanished is not something to offer.
    locator.registerLazySingleton<UpdateService>(
      () => UpdateService(settings: settings),
    );

    // One owner for the samplers. Both engines could run them and both would
    // write the same minute, so the popover — which has no `includeUi` — does
    // not get one.
    locator.registerSingleton<MetricSampler>(
      MetricSampler(store: locator<TidyStore>()),
    );

    // ─── Dashboard ─────────────────────────────────────────────────────────
    // Assembled here rather than inside the feature because this is the only
    // file allowed to see both `core/` and every module: `docs/feature.md` §2
    // forbids a feature importing a sibling, and the Dashboard reads nine of
    // them. Each read goes in as a closure, so `DashboardRepository` depends on
    // function types instead of on Network, Clipboard, Recycle Bin and the rest.
    locator.registerLazySingleton<DashboardRepository>(
      () => DashboardRepository(
        store: locator<TidyStore>(),
        sampler: locator<MetricSampler>(),
        readDisk: SystemBridge.diskUsage,
        readVitals: PerformanceBridge.systemVitals,
        readProcesses: locator<ProcessMonitorService>().sample,
        readTrash: locator<RecycleBinService>().load,
        readClips: locator<ClipboardService>().history,
        readNetworkHeadline: locator<NetworkService>().headline,
        readNetworkSeries: locator<NetworkService>().series,
        readFullDiskAccess: SystemBridge.hasFullDiskAccess,
        readAppInventory: () => _appInventory(locator<ScanCache>()),
        readLaunchItems: () => _launchItemFacts(locator<LaunchItemsService>()),
      ),
    );

    // One funnel for pushing the clipboard preferences to the native recorder,
    // registered here so no individual setter can forget. The popover engine
    // skips it: it has no settings UI, and the native side reads the same file
    // itself at launch.
    locator<ClipboardService>().bindTo(settings);
    locator<NetworkService>().bindTo(settings);
  }
}

/// Reads the installed-app inventory from the on-disk cache.
///
/// The cache, never a scan: the Dashboard is the first thing the user sees, and
/// walking `/Applications` before the first frame would trade a fast window for
/// a number that barely changes between launches. An empty cache reports
/// [AppInventory.empty], whose `isKnown` is false — the tile then says so
/// rather than claiming zero apps are installed.
Future<AppInventory> _appInventory(ScanCache cache) async {
  final cached = await cache.read();
  if (cached == null || cached.apps.isEmpty) return AppInventory.empty;

  final apps = cached.apps.where((app) => !app.isSystem).toList();
  final bySize = [...apps]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

  final perDeveloper = <String, int>{};
  for (final app in apps) {
    final developer = app.developer;
    if (developer == null || developer.isEmpty) continue;
    perDeveloper[developer] = (perDeveloper[developer] ?? 0) + app.sizeBytes;
  }
  final developers =
      perDeveloper.entries.map((e) => (name: e.key, bytes: e.value)).toList()
        ..sort((a, b) => b.bytes.compareTo(a.bytes));

  return AppInventory(
    count: apps.length,
    totalBytes: apps.fold<int>(0, (sum, app) => sum + app.sizeBytes),
    // 180 days, matching `UnusedAppsModule.unusedAfter`. An app with no
    // recorded last-used date is not counted: Spotlight simply may not have
    // indexed it, and calling that "unused" would put apps on the list for
    // being unindexed rather than for being unopened.
    unusedCount:
        apps.where((app) {
          final days = app.daysSinceLastUsed;
          return days != null && days >= 180;
        }).length,
    largest: [
      for (final app in bySize.take(5)) (name: app.name, bytes: app.sizeBytes),
    ],
    byDeveloper: developers.take(5).toList(),
    scannedAt: cached.scannedAt,
  );
}

/// Counts the launch items without dragging `LaunchItem` into `core/`.
///
/// "Broken" means the same thing here as in `PerformanceState.brokenCount` —
/// the program the job points at is not there — so the Dashboard tile and the
/// Performance page cannot report different numbers.
Future<LaunchItemFacts> _launchItemFacts(LaunchItemsService service) async {
  final items = await service.load();
  return LaunchItemFacts(
    total: items.length,
    enabled: items.where((item) => item.enabled).length,
    broken:
        items.where((item) => item.health == LaunchItemHealth.broken).length,
  );
}
