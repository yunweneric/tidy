import 'package:flutter/services.dart' show appFlavor;

/// Which build of Tidy this is.
///
/// Two, and deliberately only two. `dev` is what you run from source; `prod` is
/// what ships. They are separate *installs* rather than separate builds of one
/// install: different bundle id, different name, different icon, and — the
/// point of the exercise — a different Application Support folder, so a
/// debug session cannot corrupt or lock the history of the copy you actually
/// use. Hive holds an exclusive lock on its box files, so without that split
/// running a dev build while Tidy is open would fail to open the store at all.
enum Flavor {
  dev(
    label: 'Dev',
    bundleId: 'com.yunweneric.tidy.dev',
    supportDirectoryName: 'Tidy Dev',
  ),
  prod(
    label: null,
    bundleId: 'com.yunweneric.tidy',
    supportDirectoryName: 'Tidy',
  );

  const Flavor({
    required this.label,
    required this.bundleId,
    required this.supportDirectoryName,
  });

  /// The suffix appended to the product name, or null when there is none.
  ///
  /// Prod is unlabelled on purpose: the shipping app is just "Tidy", and every
  /// place that shows a flavour badge should show nothing at all for it.
  final String? label;

  /// Must match `PRODUCT_BUNDLE_IDENTIFIER` in the matching
  /// `macos/Runner/Configs/AppInfo-<flavor>.xcconfig`.
  ///
  /// TCC grants — Full Disk Access above all — are keyed to this, which is why
  /// dev has its own: granting access to a debug build must not silently grant
  /// it to the shipping one, and revoking one must not revoke the other.
  final String bundleId;

  /// The folder under `~/Library/Application Support`.
  ///
  /// Mirrored on the native side by `AppSupport.directoryName`, which derives
  /// the same answer from the bundle id. The two have to agree: Dart writes
  /// settings, the scan cache and the store here, Swift writes the clipboard
  /// history to the same folder.
  final String supportDirectoryName;
}

/// The flavour this binary was compiled for.
///
/// Read from Flutter's own [appFlavor], which carries the `--flavor` the build
/// was invoked with — rather than a `--dart-define` we would have to remember
/// to pass alongside it, and could get wrong. There is nothing to keep in sync:
/// the Xcode configuration and this answer come from the same flag.
Flavor get currentFlavor => switch (appFlavor) {
  'dev' => Flavor.dev,
  // `null` — no `--flavor` at all — is prod, because that is what the plain
  // `Release` configuration builds and what `scripts/build_dmg.sh` and CI
  // ship. Anything else is a build-config mistake rather than a flavour, and
  // resolving it to prod would point a debug build at the real store; the
  // assert in `main()` is what stops that reaching anyone.
  _ => Flavor.prod,
};

/// The raw `--flavor` string, for diagnostics. `(none)` when there was none,
/// which is the normal case for a release build.
String get rawFlavor => appFlavor ?? '(none)';

/// True when the `--flavor` passed is one this app knows about.
///
/// Asserted at startup rather than thrown: a release build should not die over
/// its own build configuration, but a typo'd flavour should not pass silently
/// in a debug session either.
bool get isKnownFlavor =>
    appFlavor == null || appFlavor == 'dev' || appFlavor == 'prod';
