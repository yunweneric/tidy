import 'package:flutter/material.dart';

/// Product identity, in one place.
///
/// The app ships as "Tidy" but keeps the `com.yunweneric.macuninstaller` bundle
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

  /// The bundle id, which deliberately still says MacUninstaller.
  static const String bundleId = 'com.yunweneric.macuninstaller';

  /// Where the on-disk scan cache lives. Also unchanged, for the same reason.
  static const String supportDirectoryName = 'MacUninstaller';

  static const IconData mark = Icons.auto_awesome_rounded;
}
