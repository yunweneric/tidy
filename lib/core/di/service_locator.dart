import 'package:get_it/get_it.dart';
import 'package:mac_uninstaller/core/platform/full_disk_access_service.dart';
import 'package:mac_uninstaller/core/settings/app_settings.dart';
import 'package:mac_uninstaller/features/apps/data/services/apps_service.dart';
import 'package:mac_uninstaller/features/apps/data/services/junk_scanner.dart';
import 'package:mac_uninstaller/features/apps/data/services/leftover_scanner.dart';
import 'package:mac_uninstaller/features/apps/data/services/scan_cache.dart';
import 'package:mac_uninstaller/features/apps/data/services/unused_apps_module.dart';
import 'package:mac_uninstaller/features/cleanup/data/cleanup_scan_module.dart';
import 'package:mac_uninstaller/features/clipboard/data/services/clipboard_service.dart';
import 'package:mac_uninstaller/features/performance/data/services/launch_items_service.dart';
import 'package:mac_uninstaller/features/performance/data/services/maintenance_service.dart';
import 'package:mac_uninstaller/features/performance/data/services/process_monitor_service.dart';
import 'package:mac_uninstaller/features/recycle_bin/data/services/recycle_bin_service.dart';
import 'package:mac_uninstaller/features/smart_care/data/smart_care_module.dart';

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
  locator.registerLazySingleton<MaintenanceService>(MaintenanceService.new);
  locator.registerLazySingleton<ProcessMonitorService>(
    ProcessMonitorService.new,
  );

  // ─── Recycle Bin ─────────────────────────────────────────────────────────
  locator.registerLazySingleton<RecycleBinService>(RecycleBinService.new);

  // ─── Clipboard ───────────────────────────────────────────────────────────
  // The history itself is native — see ClipboardBridge for why — so this holds
  // only an image cache and the settings mirror.
  locator.registerLazySingleton<ClipboardService>(ClipboardService.new);

  // The popover has no settings UI and no theme switcher, so it skips the
  // file read entirely.
  if (includeUi) {
    final settings = await AppSettings.load();
    locator.registerSingleton<AppSettings>(settings);

    // One funnel for pushing the clipboard preferences to the native recorder,
    // registered here so no individual setter can forget. The popover engine
    // skips it: it has no settings UI, and the native side reads the same file
    // itself at launch.
    locator<ClipboardService>().bindTo(settings);
  }
}
