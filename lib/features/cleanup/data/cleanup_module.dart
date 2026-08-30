import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/scanning/domain/composite_scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/features/cleanup/data/cleanup_scan_module.dart';
import 'package:tidy/features/cleanup/data/scanners/developer_junk_module.dart';

/// Everything the machine will make again on its own: system junk and the
/// build output and caches developer tools leave behind.
///
/// A [CompositeScanModule] and nothing else — the sub-scanners do the work and
/// this merges them, so adding the next Phase 2 sweep (trash bins, browser
/// caches) means adding it to [modules] and nothing more.
///
/// Order matters. Developer Junk runs first, so when both it and the system
/// sweep claim a folder under `~/Library/Caches` — Homebrew, CocoaPods and
/// JetBrains all live there — it stays filed under the tool that owns it, with
/// the label and the safety level that go with it, rather than being one more
/// anonymous cache folder. The tiles are ordered by size on screen either way.
class CleanupModule extends CompositeScanModule {
  CleanupModule({
    required DeveloperJunkModule developerJunk,
    required CleanupScanModule systemJunk,
  }) : super(
         id: ModuleId.cleanup,
         icon: AppIcons.cleanup,
         modules: [developerJunk, systemJunk],
       );
}
