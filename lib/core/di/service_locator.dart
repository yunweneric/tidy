import 'package:get_it/get_it.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/store/metric_sampler.dart';
import 'package:tidy/core/store/tidy_store.dart';
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
  // Registered for both engines: the popover reads the same database (WAL, so
  // its reads never block the window's writes). Opened below, and only the main
  // engine ever samples into it.
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
    // "opening the database" state. Failure is survivable by design: the store
    // stays closed, every call on it becomes a no-op, and the app loses its
    // charts rather than its ability to run.
    await locator<TidyStore>().open();

    // One owner for the samplers. Both engines could run them and both would
    // write the same minute, so the popover — which has no `includeUi` — does
    // not get one.
    locator.registerSingleton<MetricSampler>(
      MetricSampler(store: locator<TidyStore>()),
    );

    // One funnel for pushing the clipboard preferences to the native recorder,
    // registered here so no individual setter can forget. The popover engine
    // skips it: it has no settings UI, and the native side reads the same file
    // itself at launch.
    locator<ClipboardService>().bindTo(settings);
    locator<NetworkService>().bindTo(settings);
  }
}
