import 'package:flutter/widgets.dart';

import 'package:tidy/core/design/app_icons.dart';

/// Product identity, in one place.
///
/// The app ships as "Tidy" but keeps the `com.yunweneric.tidy` bundle
/// id: TCC grants (Full Disk Access in particular) are keyed to the bundle id,
/// so renaming it would cost every existing user their permission grant for no
/// benefit. Nothing else should hard-code either string.
@immutable
class Brand {
  const Brand._();

  static const String name = 'Tidy';
  static const String tagline = 'Clean, tune and reclaim your Mac';

  /// Shown under the logo in the sidebar.
  static const String subtitle = 'for macOS';

  /// The bundle id.
  ///
  /// Renamed from `com.yunweneric.macuninstaller` along with everything else.
  /// TCC grants are keyed to the bundle id, so anyone who had granted Full
  /// Disk Access has to grant it again — done now, before release, precisely
  /// because that cost only grows.
  static const String bundleId = 'com.yunweneric.tidy';

  /// Where the scan cache, settings, trash ledger and clipboard history live.
  ///
  /// Renamed from `MacUninstaller`; `AppSupport.migrate()` on the native side
  /// moves the old folder across on first launch so nothing is orphaned.
  static const String supportDirectoryName = 'Tidy';

  static const IconData mark = AppIcons.brand;
}
