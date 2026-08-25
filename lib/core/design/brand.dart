import 'package:flutter/widgets.dart';

import 'package:tidy/core/config/flavor.dart';
import 'package:tidy/core/design/app_icons.dart';

/// Product identity, in one place.
///
/// The app ships as "Tidy" but keeps the `com.yunweneric.tidy` bundle
/// id: TCC grants (Full Disk Access in particular) are keyed to the bundle id,
/// so renaming it would cost every existing user their permission grant for no
/// benefit. Nothing else should hard-code either string.
///
/// Three of these vary by flavour — [displayName], [bundleId] and
/// [supportDirectoryName] — and so are getters rather than constants. The
/// values themselves live on [Flavor]; this class is the front door everything
/// else uses.
@immutable
class Brand {
  const Brand._();

  /// The product's name, as it appears in prose.
  ///
  /// Not flavour-aware, and not the window title: settings copy that reads
  /// "What Tidy remembers about what it has done" should say Tidy in a dev
  /// build too. [displayName] is the one that carries the flavour.
  static const String name = 'Tidy';

  /// The name macOS shows: the window title, the Dock, the app switcher.
  ///
  /// This is where a dev build announces itself in words, the way the amber
  /// icon does in colour. Must match `PRODUCT_NAME` in the flavour's
  /// `AppInfo-<flavor>.xcconfig`, or the title bar and the Dock disagree.
  static String get displayName {
    final label = currentFlavor.label;
    return label == null ? name : '$name $label';
  }

  static const String tagline = 'Clean, tune and reclaim your Mac';

  /// Shown under the logo in the sidebar.
  static const String subtitle = 'for macOS';

  /// The bundle id, per flavour.
  ///
  /// Renamed from `com.yunweneric.macuninstaller` along with everything else.
  /// TCC grants are keyed to the bundle id, so anyone who had granted Full
  /// Disk Access has to grant it again — done now, before release, precisely
  /// because that cost only grows. The same property is why dev gets its own:
  /// a debug build asking for Full Disk Access must not be answered with the
  /// grant the shipping app was given.
  static String get bundleId => currentFlavor.bundleId;

  /// Where the scan cache, settings, trash ledger and clipboard history live.
  ///
  /// Renamed from `MacUninstaller`; `AppSupport.migrate()` on the native side
  /// moves the old folder across on first launch so nothing is orphaned.
  ///
  /// Per flavour, so a dev build gets `Tidy Dev` and leaves the real folder
  /// alone. That is not tidiness for its own sake: the store's Hive boxes take
  /// an exclusive file lock, so sharing one folder would mean a dev build and
  /// the installed app could not be open at the same time.
  static String get supportDirectoryName => currentFlavor.supportDirectoryName;

  static const IconData mark = AppIcons.brand;
}
