import 'package:tidy/core/scanning/domain/scan_node.dart';

/// The three headings developer junk is filed under.
enum DevGroup {
  xcode(
    'Xcode',
    'Build output, indexes and simulator caches Xcode makes again on its own.',
  ),
  packages(
    'Package Caches',
    'Downloads your package managers keep so the next install is quick.',
  ),
  editors(
    'Editor Caches',
    'Indexes and caches your editors rebuild when you open a project.',
  );

  const DevGroup(this.label, this.detail);

  final String label;
  final String detail;
}

/// One place a developer tool leaves things behind.
///
/// Declarative on purpose. [safety] is the most consequential field in the app
/// — it decides what is pre-ticked, and everything a user removes without
/// reading was pre-ticked by us — so every one of those judgements lives in
/// this one file where they can be read in a sitting, rather than being spread
/// through the scan.
class DevRoot {
  const DevRoot({
    required this.group,
    required this.label,
    required this.path,
    required this.detail,
    required this.safety,
    this.expand = false,
    this.sharesStorage = false,
  });

  final DevGroup group;

  /// Shown as the finding's title when the whole folder is offered at once.
  final String label;

  /// Absolute. `$HOME` is expanded by [devRootsFor], never left as `~`, because
  /// the native sizer keys its results on the exact string it was handed.
  final String path;

  /// The one plain-language line every finding owes the user.
  final String detail;

  final SafetyLevel safety;

  /// List the children as separate findings instead of offering the folder
  /// whole. One row per project under Derived Data is reviewable; a single
  /// 40 GB "Derived Data" row is a leap of faith.
  final bool expand;

  /// The bytes are hardlinked or cloned into somewhere still in use, so
  /// removing this frees far less than the figure says — often nothing. The UI
  /// says so and stops counting it as reclaimable.
  final bool sharesStorage;
}

/// Every developer cache this module knows about, as absolute paths.
///
/// **How [SafetyLevel] is assigned here**, since it is the field that decides
/// what is pre-ticked:
///
/// - [SafetyLevel.safe] — output this machine makes again by itself, offline:
///   build products, indexes, dyld and editor caches. The cost of being wrong
///   is a slow first build.
/// - [SafetyLevel.review] — anything whose restoration needs a **network round
///   trip or a device**: every package download cache, and device support
///   symbols. The bytes come back for free; your next build on a plane does
///   not.
/// - [SafetyLevel.risky] — Xcode archives. Those are the builds you shipped,
///   and the dSYMs in them are the only way a crash report from a user is ever
///   readable again.
///
/// **Deliberately absent, and why** (`docs/feature.md` §5). These are not
/// oversights, and they must not be added without reading that section:
///
/// - pnpm's content-addressed store (`~/Library/pnpm`,
///   `~/.local/share/pnpm/store`) — every `node_modules` hard-links *into* it,
///   so removing it breaks every installed project. `pnpm store prune`.
/// - Docker's disk image (`~/Library/Containers/com.docker.docker/Data/vms`,
///   `Docker.raw`) — `docker system prune`.
/// - `~/Library/Developer/CoreSimulator/Devices` — `device_set.plist` is the
///   index, and orphaning it corrupts Xcode's simulator list.
///   `xcrun simctl delete unavailable`.
/// - Homebrew's `Cellar` and the rest of `/opt/homebrew` — that is installed
///   software, not junk. Note `isRemovable` protects `/opt` itself but not its
///   children, so this restraint has to live here.
/// - Installed toolchains and the executables on `PATH`: `~/.cargo/bin`,
///   `~/go/bin`, `~/.pub-cache/bin`, `~/fvm/versions`, `~/.rustup/toolchains`,
///   `~/.nvm/versions`, the Android SDK. Large, and every one of them is
///   something you chose to install.
/// - `~/.android/avd` and `~/Library/Developer/XCTestDevices` — emulators and
///   test devices with state in them, the Android and Xcode analogues of
///   `CoreSimulator/Devices`.
/// - `~/Library/Developer/Xcode/UserData` — snippets, key bindings, themes.
///
/// **One invariant to keep**: any path here that lives under
/// `~/Library/Caches` must be *exactly* a direct child of it, because the
/// system-junk sweep lists that folder's children and the composite dedupes on
/// exact path equality. `~/Library/Caches/pip` is deduped; a deeper
/// `~/Library/Caches/pip/wheels` would be counted — and offered — twice.
///
/// None of those are surfaced at all for now — a row the user cannot act on is
/// noise. They earn a place once we can offer the tool's own command as the
/// action, which is what §5 asks for in the first place.
List<DevRoot> devRootsFor(String home) => [
  // ─── Xcode ────────────────────────────────────────────────────────────────
  DevRoot(
    group: DevGroup.xcode,
    label: 'Derived Data',
    path: '$home/Library/Developer/Xcode/DerivedData',
    detail:
        'Build output and indexes, one folder per project. Xcode makes them '
        'again the next time you build — that first build will be slow.',
    safety: SafetyLevel.safe,
    expand: true,
  ),
  DevRoot(
    group: DevGroup.xcode,
    label: 'Xcode Cache',
    path: '$home/Library/Caches/com.apple.dt.Xcode',
    detail: "Xcode's own scratch cache. It refills as you work.",
    safety: SafetyLevel.safe,
  ),
  DevRoot(
    group: DevGroup.xcode,
    label: 'Simulator Caches',
    path: '$home/Library/Developer/CoreSimulator/Caches',
    detail:
        'Shared caches the simulators rebuild on demand. Your simulators '
        'themselves are left alone.',
    safety: SafetyLevel.safe,
  ),
  DevRoot(
    group: DevGroup.xcode,
    label: 'Documentation Cache',
    path: '$home/Library/Developer/Xcode/DocumentationCache',
    detail: 'Downloaded documentation. Xcode fetches it again when you search.',
    safety: SafetyLevel.safe,
  ),
  for (final platform in const ['iOS', 'watchOS', 'tvOS', 'visionOS', 'macOS'])
    DevRoot(
      group: DevGroup.xcode,
      label: '$platform Device Support',
      path: '$home/Library/Developer/Xcode/$platform DeviceSupport',
      detail:
          'Symbols copied from a device you once plugged in. Needed again only '
          'if you attach that version — and then it is copied again, which '
          'takes a few minutes.',
      safety: SafetyLevel.review,
      expand: true,
    ),
  DevRoot(
    group: DevGroup.xcode,
    label: 'Archives',
    path: '$home/Library/Developer/Xcode/Archives',
    detail:
        'The builds you shipped. The dSYMs in here are what make a crash '
        'report from a user readable — once they are gone, it stays unreadable.',
    safety: SafetyLevel.risky,
    expand: true,
  ),

  // ─── Package managers ─────────────────────────────────────────────────────
  DevRoot(
    group: DevGroup.packages,
    label: 'Homebrew Downloads',
    path: '$home/Library/Caches/Homebrew',
    detail:
        'Bottles and installers Homebrew has already unpacked. It downloads '
        'again what it needs. Your installed formulae are untouched.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'npm Cache',
    path: '$home/.npm/_cacache',
    detail: 'Packages npm keeps to skip a download. It refills on install.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Yarn Cache',
    path: '$home/Library/Caches/Yarn',
    detail: 'Packages Yarn keeps to skip a download. It refills on install.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Bun Cache',
    path: '$home/.bun/install/cache',
    detail: 'Packages Bun keeps to skip a download. It refills on install.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Deno Cache',
    path: '$home/Library/Caches/deno',
    detail: 'Modules Deno has fetched. It fetches them again when you run.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'pip Cache',
    path: '$home/Library/Caches/pip',
    detail: 'Wheels pip keeps to skip a download. It refills on install.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'uv Cache',
    path: '$home/Library/Caches/uv',
    detail:
        "uv's package cache. Most of these bytes are hardlinked into your "
        'virtual environments, so removing it frees much less than the figure '
        'suggests.',
    safety: SafetyLevel.review,
    sharesStorage: true,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Cargo Downloads',
    path: '$home/.cargo/registry/cache',
    detail: 'Crate archives Cargo downloaded. It fetches them again on build.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Cargo Sources',
    path: '$home/.cargo/registry/src',
    detail:
        'Crates Cargo unpacked to build against. Unpacked again from the '
        'downloads, or fetched fresh. Your installed tools are untouched.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Go Modules',
    path: '$home/go/pkg/mod',
    detail:
        'Every module version Go has downloaded. `go mod download` fetches '
        'them again, which needs a network connection. Offered whole rather '
        'than module by module — Go writes this tree read-only.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Go Build Cache',
    path: '$home/Library/Caches/go-build',
    detail: 'Compiled build output. Go rebuilds it locally, no network needed.',
    safety: SafetyLevel.safe,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Gradle Cache',
    path: '$home/.gradle/caches',
    detail:
        'Dependencies and build output Gradle keeps between builds. It '
        'downloads them again on the next build.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Maven Repository',
    path: '$home/.m2/repository',
    detail:
        'Every artefact Maven has downloaded. Fetched again on the next '
        'build, which needs a network connection.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'CocoaPods Cache',
    path: '$home/Library/Caches/CocoaPods',
    detail: 'Pods CocoaPods keeps to skip a download. It refills on install.',
    safety: SafetyLevel.review,
  ),
  // Not `~/.pub-cache` whole: `bin/` there holds the globally activated
  // executables that are on the user's PATH, and those are installed software.
  DevRoot(
    group: DevGroup.packages,
    label: 'Dart Package Cache',
    path: '$home/.pub-cache/hosted',
    detail:
        'Every Dart and Flutter package you have pulled from pub.dev. '
        '`pub get` downloads them again, so the next build of every project '
        'needs a connection.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Dart Git Packages',
    path: '$home/.pub-cache/git',
    detail:
        'Dart packages pulled straight from a git repository. `pub get` '
        'clones them again.',
    safety: SafetyLevel.review,
  ),
  DevRoot(
    group: DevGroup.packages,
    label: 'Composer Cache',
    path: '$home/.composer/cache',
    detail:
        'Packages Composer keeps to skip a download. It refills on install.',
    safety: SafetyLevel.review,
  ),

  // ─── Editors ──────────────────────────────────────────────────────────────
  DevRoot(
    group: DevGroup.editors,
    label: 'JetBrains Caches',
    path: '$home/Library/Caches/JetBrains',
    detail:
        'Project indexes and shared caches. Rebuilt when you next open the '
        'project; your settings and projects are elsewhere and untouched.',
    safety: SafetyLevel.safe,
  ),
  DevRoot(
    group: DevGroup.editors,
    label: 'VS Code Cache',
    path: '$home/Library/Application Support/Code/Cache',
    detail: 'Scratch cache VS Code refills the next time it runs.',
    safety: SafetyLevel.safe,
  ),
  DevRoot(
    group: DevGroup.editors,
    label: 'VS Code Cached Data',
    path: '$home/Library/Application Support/Code/CachedData',
    detail: 'Compiled script cache. VS Code makes it again on the next launch.',
    safety: SafetyLevel.safe,
  ),
  DevRoot(
    group: DevGroup.editors,
    label: 'VS Code Extension Downloads',
    path: '$home/Library/Application Support/Code/CachedExtensionVSIXs',
    detail:
        'Installer archives for extensions that are already installed. The '
        'extensions themselves stay.',
    safety: SafetyLevel.safe,
  ),
  DevRoot(
    group: DevGroup.editors,
    label: 'VS Code System Cache',
    path: '$home/Library/Caches/com.microsoft.VSCode',
    detail: 'Scratch cache VS Code refills the next time it runs.',
    safety: SafetyLevel.safe,
  ),
];
