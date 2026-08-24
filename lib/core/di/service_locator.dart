import 'package:get_it/get_it.dart';
import 'package:mac_uninstaller/core/platform/full_disk_access_service.dart';
import 'package:mac_uninstaller/core/settings/app_settings.dart';
import 'package:mac_uninstaller/features/apps/data/services/apps_service.dart';
import 'package:mac_uninstaller/features/apps/data/services/junk_scanner.dart';
import 'package:mac_uninstaller/features/apps/data/services/leftover_scanner.dart';
import 'package:mac_uninstaller/features/apps/data/services/scan_cache.dart';
import 'package:mac_uninstaller/features/cleanup/data/cleanup_scan_module.dart';

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
  locator.registerLazySingleton<FullDiskAccessService>(FullDiskAccessService.new);

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

  // The popover has no settings UI and no theme switcher, so it skips the
  // file read entirely.
  if (includeUi) {
    locator.registerSingleton<AppSettings>(await AppSettings.load());
  }
}
