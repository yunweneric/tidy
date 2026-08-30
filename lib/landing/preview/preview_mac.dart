import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';

const int _kb = 1024;
const int _mb = _kb * 1024;
const int _gb = _mb * 1024;

/// The destinations the app itself opens a "not built yet" page for.
///
/// Named rather than derived from [PreviewScreen], because "has a demo pane"
/// and "is built" are different questions. Smart Care is built and has no pane
/// of its own — what it does is run the other modules — and Settings is built
/// and is not worth a pane. Deriving one from the other would quietly label
/// both as unfinished.
const Set<AppDestination> kPlannedDestinations = {
  AppDestination.protection,
  AppDestination.clutter,
  AppDestination.allTools,
  AppDestination.activity,
  AppDestination.assistant,
};

/// Which screen the preview window is showing.
///
/// A subset of [AppDestination] — the modules that are actually built. Each
/// value carries its destination rather than duplicating a label and an icon,
/// so the preview's sidebar, title bar and tab strip all read the same strings
/// the app does and cannot drift from it.
enum PreviewScreen {
  dashboard(AppDestination.dashboard),
  cleanup(AppDestination.cleanup),
  applications(AppDestination.applications),
  clipboard(AppDestination.clipboard),
  performance(AppDestination.performance),
  network(AppDestination.network),
  recycleBin(AppDestination.recycleBin);

  const PreviewScreen(this.destination);

  final AppDestination destination;

  String get label => destination.label;

  /// The one-line subtitle under the page title, written for people who do not
  /// know what a plist is. Reused verbatim as the tour's caption.
  String get blurb => destination.blurb;

  static PreviewScreen? forDestination(AppDestination destination) {
    for (final screen in values) {
      if (screen.destination == destination) return screen;
    }
    return null;
  }
}

/// A category of reclaimable junk, matching the app's own `JunkKind`.
@immutable
class PreviewJunk {
  const PreviewJunk({
    required this.id,
    required this.title,
    required this.blurb,
    required this.safety,
    required this.bytes,
    required this.items,
  });

  final String id;
  final String title;
  final String blurb;
  final SafetyLevel safety;
  final int bytes;

  /// A handful of real-looking paths, so the review list shows what a category
  /// actually means rather than asking for trust in a number.
  final List<String> items;
}

/// One installed application.
@immutable
class PreviewApp {
  const PreviewApp({
    required this.name,
    required this.developer,
    required this.version,
    required this.bytes,
    required this.lastOpened,
    required this.leftovers,
    this.unused = false,
  });

  final String name;
  final String developer;
  final String version;
  final int bytes;
  final String lastOpened;

  /// What uninstalling would also remove. Matched by bundle id and exact
  /// display name in the real app — never by substring, which is how cleaners
  /// end up deleting `~/Library/Mail` because an app was called "Mail".
  final List<({String path, int bytes, SafetyLevel safety})> leftovers;

  /// Not opened in six months.
  final bool unused;

  int get leftoverBytes =>
      leftovers.fold(0, (total, item) => total + item.bytes);
}

/// One thing in the Trash.
@immutable
class PreviewTrashItem {
  const PreviewTrashItem({
    required this.name,
    required this.bytes,
    required this.deleted,
    this.stale = false,
  });

  final String name;
  final int bytes;
  final String deleted;

  /// Older than a month.
  final bool stale;
}

enum PreviewClipKind { text, link, image, file }

/// One entry in the clipboard history.
@immutable
class PreviewClip {
  const PreviewClip({
    required this.body,
    required this.source,
    required this.age,
    required this.kind,
    this.pinned = false,
    this.masked = false,
  });

  final String body;
  final String source;
  final String age;
  final PreviewClipKind kind;
  final bool pinned;

  /// Anything key- or card-shaped is masked before it is stored. Shown here
  /// because it is the part of the feature worth advertising.
  final bool masked;

  PreviewClip copyWith({bool? pinned}) => PreviewClip(
    body: body,
    source: source,
    age: age,
    kind: kind,
    pinned: pinned ?? this.pinned,
    masked: masked,
  );
}

enum PreviewItemKind { login, background }

/// A login item or a background agent.
@immutable
class PreviewLaunchItem {
  const PreviewLaunchItem({
    required this.name,
    required this.detail,
    required this.kind,
    required this.enabled,
  });

  final String name;
  final String detail;
  final PreviewItemKind kind;
  final bool enabled;

  PreviewLaunchItem copyWith({bool? enabled}) => PreviewLaunchItem(
    name: name,
    detail: detail,
    kind: kind,
    enabled: enabled ?? this.enabled,
  );
}

/// One provider's limit window, as the AI Usage popover draws it.
///
/// `usedPercent` is null where the provider publishes no allowance. That is the
/// honesty boundary the real panel is built around: Codex reports its own
/// `used_percent` and gets a percentage, Claude Code publishes nothing, so its
/// windows can only report the tokens that went through them. Inventing a
/// denominator for the second would be the single most tempting lie in the
/// feature, and the preview does not tell it either.
@immutable
class PreviewUsageWindow {
  const PreviewUsageWindow({
    required this.label,
    required this.resetsIn,
    required this.tokens,
    required this.elapsed,
    this.usedPercent,
  });

  final String label;
  final String resetsIn;

  /// Already formatted the way `formatCount` would render it.
  final String tokens;

  /// How far through the window the clock is, 0–1.
  final double elapsed;

  final double? usedPercent;

  bool get isMeasured => usedPercent != null;

  /// How full the bar is — the allowance where one is published, the clock
  /// where it is not. An inferred window still draws a bar, dimmed, because a
  /// row with an empty track reads as a reading that failed rather than as a
  /// window nobody publishes a ceiling for.
  double get fraction => (usedPercent ?? elapsed * 100) / 100;
}

/// One model's share of the day, for the popover's Models section.
@immutable
class PreviewModelUsage {
  const PreviewModelUsage({
    required this.model,
    required this.tokens,
    required this.cost,
    this.priced = true,
  });

  final String model;
  final String tokens;
  final String cost;

  /// Nobody publishes a per-token rate for the Codex models, and `$0.00` would
  /// say those tokens were free rather than unpriced. Those rows draw a dash.
  final bool priced;
}

/// A running process, for the heavy-consumers table.
@immutable
class PreviewProcess {
  const PreviewProcess({
    required this.name,
    required this.cpu,
    required this.memoryBytes,
  });

  final String name;
  final double cpu;
  final int memoryBytes;
}

/// How far along the Cleanup scan is.
enum PreviewScanPhase { idle, scanning, results }

/// The invented Mac behind the preview window.
///
/// A [ChangeNotifier] rather than a wall of constants, because the preview is
/// meant to be *used*. Reclaiming junk has to move the free-space bar on the
/// dashboard and put something in the Trash; uninstalling an app has to drop
/// the app count and be undoable from the Recycle Bin. A demo whose screens
/// quietly disagree with each other is worse than a screenshot, because a
/// screenshot never promised to add up.
///
/// Nothing here persists. A reload restores the fiction.
class PreviewMac extends ChangeNotifier {
  static const int diskTotalBytes = 512 * _gb;
  static const int _baseFreeBytes = 170 * _gb;

  // ─── Junk ────────────────────────────────────────────────────────────────

  /// The four categories the Cleanup module actually scans for.
  static const List<PreviewJunk> junk = [
    PreviewJunk(
      id: 'caches',
      title: 'User caches',
      blurb: 'Regenerated automatically the next time an app runs.',
      safety: SafetyLevel.safe,
      bytes: 7 * _gb + 640 * _mb,
      items: [
        '~/Library/Caches/com.apple.Safari',
        '~/Library/Caches/com.google.Chrome',
        '~/Library/Caches/com.spotify.client',
        '~/Library/Caches/Homebrew',
        '~/Library/Developer/Xcode/DerivedData',
      ],
    ),
    PreviewJunk(
      id: 'logs',
      title: 'App logs',
      blurb: 'Diagnostic logs written by installed apps.',
      safety: SafetyLevel.safe,
      bytes: 1 * _gb + 180 * _mb,
      items: [
        '~/Library/Logs/DiagnosticReports',
        '~/Library/Logs/Adobe',
        '~/Library/Logs/JetBrains',
      ],
    ),
    PreviewJunk(
      id: 'state',
      title: 'Saved app state',
      blurb: 'Window and document restore data.',
      safety: SafetyLevel.review,
      bytes: 820 * _mb,
      items: [
        '~/Library/Saved Application State/com.apple.dt.Xcode.savedState',
        '~/Library/Saved Application State/com.figma.Desktop.savedState',
      ],
    ),
    PreviewJunk(
      id: 'orphans',
      title: 'Orphaned leftovers',
      blurb: 'Files left behind by apps you no longer have.',
      safety: SafetyLevel.review,
      bytes: 2 * _gb + 760 * _mb,
      items: [
        '~/Library/Application Support/Sketch',
        '~/Library/Preferences/com.evernote.Evernote.plist',
        '~/Library/Containers/com.docker.docker',
      ],
    ),
  ];

  static int get totalJunkBytes =>
      junk.fold(0, (total, kind) => total + kind.bytes);

  // ─── Applications ────────────────────────────────────────────────────────

  static const List<PreviewApp> _catalogue = [
    PreviewApp(
      name: 'Xcode',
      developer: 'Apple',
      version: '16.4',
      bytes: 18 * _gb + 400 * _mb,
      lastOpened: 'Yesterday',
      leftovers: [
        (
          path: '~/Library/Developer/Xcode/DerivedData',
          bytes: 6 * _gb,
          safety: SafetyLevel.safe,
        ),
        (
          path: '~/Library/Caches/com.apple.dt.Xcode',
          bytes: 1 * _gb + 200 * _mb,
          safety: SafetyLevel.safe,
        ),
      ],
    ),
    PreviewApp(
      name: 'Docker Desktop',
      developer: 'Docker Inc.',
      version: '4.38.0',
      bytes: 2 * _gb + 100 * _mb,
      lastOpened: '3 days ago',
      leftovers: [
        (
          path: '~/Library/Containers/com.docker.docker',
          bytes: 24 * _gb,
          safety: SafetyLevel.risky,
        ),
        (
          path: '~/Library/Group Containers/group.com.docker',
          bytes: 340 * _mb,
          safety: SafetyLevel.review,
        ),
      ],
    ),
    PreviewApp(
      name: 'Figma',
      developer: 'Figma, Inc.',
      version: '124.6.4',
      bytes: 780 * _mb,
      lastOpened: 'Today',
      leftovers: [
        (
          path: '~/Library/Application Support/Figma',
          bytes: 1 * _gb + 400 * _mb,
          safety: SafetyLevel.review,
        ),
      ],
    ),
    PreviewApp(
      name: 'Adobe Photoshop',
      developer: 'Adobe Inc.',
      version: '25.9',
      bytes: 4 * _gb + 300 * _mb,
      lastOpened: '8 months ago',
      unused: true,
      leftovers: [
        (
          path: '~/Library/Application Support/Adobe',
          bytes: 3 * _gb + 700 * _mb,
          safety: SafetyLevel.review,
        ),
        (
          path: '~/Library/Preferences/Adobe Photoshop 2024 Settings',
          bytes: 84 * _mb,
          safety: SafetyLevel.review,
        ),
        (
          path: '/Library/LaunchAgents/com.adobe.AdobeCreativeCloud.plist',
          bytes: 4 * _kb,
          safety: SafetyLevel.safe,
        ),
      ],
    ),
    PreviewApp(
      name: 'Slack',
      developer: 'Slack Technologies',
      version: '4.42.0',
      bytes: 640 * _mb,
      lastOpened: 'Today',
      leftovers: [
        (
          path: '~/Library/Application Support/Slack',
          bytes: 920 * _mb,
          safety: SafetyLevel.review,
        ),
      ],
    ),
    PreviewApp(
      name: 'Android Studio',
      developer: 'Google',
      version: '2025.1',
      bytes: 3 * _gb + 900 * _mb,
      lastOpened: '7 months ago',
      unused: true,
      leftovers: [
        (
          path: '~/Library/Caches/Google/AndroidStudio2025.1',
          bytes: 2 * _gb + 300 * _mb,
          safety: SafetyLevel.safe,
        ),
        (
          path: '~/Library/Application Support/Google/AndroidStudio2025.1',
          bytes: 1 * _gb + 100 * _mb,
          safety: SafetyLevel.review,
        ),
      ],
    ),
    PreviewApp(
      name: 'VLC',
      developer: 'VideoLAN',
      version: '3.0.21',
      bytes: 138 * _mb,
      lastOpened: '2 months ago',
      leftovers: [
        (
          path: '~/Library/Preferences/org.videolan.vlc.plist',
          bytes: 12 * _kb,
          safety: SafetyLevel.safe,
        ),
      ],
    ),
    PreviewApp(
      name: 'Spotify',
      developer: 'Spotify AB',
      version: '1.2.53',
      bytes: 420 * _mb,
      lastOpened: 'Today',
      leftovers: [
        (
          path: '~/Library/Caches/com.spotify.client',
          bytes: 2 * _gb + 800 * _mb,
          safety: SafetyLevel.safe,
        ),
      ],
    ),
    PreviewApp(
      name: 'Zoom',
      developer: 'Zoom Video Communications',
      version: '6.2.11',
      bytes: 310 * _mb,
      lastOpened: '3 weeks ago',
      leftovers: [
        (
          path: '~/Library/Application Support/zoom.us',
          bytes: 180 * _mb,
          safety: SafetyLevel.review,
        ),
      ],
    ),
    PreviewApp(
      name: 'Sketch',
      developer: 'Sketch B.V.',
      version: '2024.2',
      bytes: 210 * _mb,
      lastOpened: '11 months ago',
      unused: true,
      leftovers: [
        (
          path: '~/Library/Application Support/com.bohemiancoding.sketch3',
          bytes: 640 * _mb,
          safety: SafetyLevel.review,
        ),
      ],
    ),
  ];

  /// The full inventory is 66 apps; ten of them are named. The rest exist as a
  /// count and a total, which is what the real table's footer reports anyway.
  static const int hiddenAppCount = 56;
  static const int hiddenAppBytes = 12 * _gb + 200 * _mb;

  // ─── Clipboard ───────────────────────────────────────────────────────────

  static const List<PreviewClip> _initialClips = [
    PreviewClip(
      body: 'https://github.com/yunweneric/tidy/releases/latest',
      source: 'Safari',
      age: '2 minutes ago',
      kind: PreviewClipKind.link,
      pinned: true,
    ),
    PreviewClip(
      body: 'flutter build macos --release',
      source: 'Terminal',
      age: '11 minutes ago',
      kind: PreviewClipKind.text,
    ),
    PreviewClip(
      body: '•••• •••• •••• 4242',
      source: '1Password',
      age: '20 minutes ago',
      kind: PreviewClipKind.text,
      masked: true,
    ),
    PreviewClip(
      body: 'Screenshot 2026-08-25 at 09.14.22.png',
      source: 'Screenshot',
      age: '35 minutes ago',
      kind: PreviewClipKind.image,
    ),
    PreviewClip(
      body: 'The module\'s colour is the window.',
      source: 'Notes',
      age: '1 hour ago',
      kind: PreviewClipKind.text,
      pinned: true,
    ),
    PreviewClip(
      body: '~/Library/Application Support/Tidy',
      source: 'Finder',
      age: '2 hours ago',
      kind: PreviewClipKind.file,
    ),
    PreviewClip(
      body: 'com.yunweneric.tidy',
      source: 'Xcode',
      age: '3 hours ago',
      kind: PreviewClipKind.text,
    ),
    PreviewClip(
      body: 'https://tidy.yunweneric.com',
      source: 'Slack',
      age: 'Yesterday',
      kind: PreviewClipKind.link,
    ),
  ];

  // ─── Performance ─────────────────────────────────────────────────────────

  static const List<PreviewLaunchItem> _initialLaunchItems = [
    PreviewLaunchItem(
      name: 'Dropbox',
      detail: 'Opens at login · adds ~4s to startup',
      kind: PreviewItemKind.login,
      enabled: true,
    ),
    PreviewLaunchItem(
      name: 'Adobe Creative Cloud',
      detail: 'Opens at login · adds ~7s to startup',
      kind: PreviewItemKind.login,
      enabled: true,
    ),
    PreviewLaunchItem(
      name: 'Docker Desktop',
      detail: 'Opens at login',
      kind: PreviewItemKind.login,
      enabled: false,
    ),
    PreviewLaunchItem(
      name: 'com.microsoft.autoupdate.helper',
      detail: '/Library/LaunchDaemons',
      kind: PreviewItemKind.background,
      enabled: true,
    ),
    PreviewLaunchItem(
      name: 'com.google.keystone.agent',
      detail: '~/Library/LaunchAgents',
      kind: PreviewItemKind.background,
      enabled: true,
    ),
    PreviewLaunchItem(
      name: 'com.spotify.webhelper',
      detail: '~/Library/LaunchAgents',
      kind: PreviewItemKind.background,
      enabled: false,
    ),
  ];

  static const List<PreviewProcess> processes = [
    PreviewProcess(
      name: 'Chrome Helper (Renderer)',
      cpu: 42.6,
      memoryBytes: 1 * _gb + 800 * _mb,
    ),
    PreviewProcess(name: 'Xcode', cpu: 18.3, memoryBytes: 3 * _gb + 200 * _mb),
    PreviewProcess(name: 'mds_stores', cpu: 11.9, memoryBytes: 240 * _mb),
    PreviewProcess(name: 'Docker', cpu: 6.4, memoryBytes: 2 * _gb + 100 * _mb),
    PreviewProcess(name: 'WindowServer', cpu: 4.1, memoryBytes: 620 * _mb),
  ];

  // ─── AI usage ────────────────────────────────────────────────────────────

  /// Today, at published API rates — which is a floor, not a bill.
  static const String aiCostToday = r'$12.84';
  static const String aiTokensToday = '8.4M';
  static const int aiRepliesToday = 214;
  static const int aiSessionsToday = 6;

  static const List<({String provider, List<PreviewUsageWindow> windows})>
  aiWindows = [
    (
      provider: 'Claude Code',
      windows: [
        PreviewUsageWindow(
          label: 'Session (5h)',
          resetsIn: '2h 41m',
          tokens: '5.1M',
          elapsed: 0.46,
        ),
        PreviewUsageWindow(
          label: 'Week',
          resetsIn: '4d 6h',
          tokens: '31.8M',
          elapsed: 0.39,
        ),
      ],
    ),
    (
      provider: 'Codex',
      windows: [
        PreviewUsageWindow(
          label: 'Session (5h)',
          resetsIn: '1h 09m',
          tokens: '820K',
          elapsed: 0.77,
          usedPercent: 38.2,
        ),
        PreviewUsageWindow(
          label: 'Week',
          resetsIn: '2d 14h',
          tokens: '6.4M',
          elapsed: 0.63,
          usedPercent: 71.5,
        ),
      ],
    ),
  ];

  static const List<PreviewModelUsage> aiModels = [
    PreviewModelUsage(model: 'claude-opus-5', tokens: '4.9M', cost: r'$9.12'),
    PreviewModelUsage(model: 'claude-sonnet-5', tokens: '2.3M', cost: r'$3.72'),
    PreviewModelUsage(
      model: 'gpt-5.1-codex',
      tokens: '1.2M',
      cost: '—',
      priced: false,
    ),
  ];

  // ─── Mutable state ───────────────────────────────────────────────────────

  PreviewScanPhase _phase = PreviewScanPhase.idle;
  PreviewScanPhase get phase => _phase;

  /// 0–1 while scanning. Null before a scan starts, which is what makes the
  /// gauge ring indeterminate rather than sitting at zero.
  double? _scanProgress;
  double? get scanProgress => _scanProgress;

  /// Categories landed so far. The real scan streams them in one at a time so
  /// the screen is never empty during a slow orphan sweep, and this does the
  /// same.
  final List<PreviewJunk> _found = [];
  List<PreviewJunk> get found => List.unmodifiable(_found);

  /// Ticked for removal. Only the `safe` tiers start selected — an inference
  /// about what a file *probably* is never does.
  final Set<String> _selected = {};

  final List<PreviewApp> _apps = List.of(_catalogue);
  List<PreviewApp> get apps => List.unmodifiable(_apps);

  final List<PreviewClip> _clips = List.of(_initialClips);
  List<PreviewClip> get clips => List.unmodifiable(_clips);

  final List<PreviewLaunchItem> _launchItems = List.of(_initialLaunchItems);
  List<PreviewLaunchItem> get launchItems => List.unmodifiable(_launchItems);

  final List<PreviewTrashItem> _trash = [
    PreviewTrashItem(
      name: 'Old renders',
      bytes: 3 * _gb + 200 * _mb,
      deleted: '2 days ago',
    ),
    PreviewTrashItem(
      name: 'Screen Recording 2026-01-14.mov',
      bytes: 1 * _gb + 700 * _mb,
      deleted: '6 weeks ago',
      stale: true,
    ),
    PreviewTrashItem(
      name: 'invoices-2025.zip',
      bytes: 84 * _mb,
      deleted: '3 months ago',
      stale: true,
    ),
    PreviewTrashItem(
      name: 'node_modules',
      bytes: 620 * _mb,
      deleted: 'Yesterday',
    ),
  ];
  List<PreviewTrashItem> get trash => List.unmodifiable(_trash);

  String _appQuery = '';
  String get appQuery => _appQuery;

  int _reclaimedBytes = 0;

  /// What the visitor has actually cleaned in this session. The one number on
  /// the page that starts at zero and is theirs.
  int get reclaimedBytes => _reclaimedBytes;

  // ─── Derived ─────────────────────────────────────────────────────────────

  int get appCount => _apps.length + hiddenAppCount;

  int get appBytes =>
      _apps.fold(hiddenAppBytes, (total, app) => total + app.bytes);

  int get unusedAppCount => _apps.where((app) => app.unused).length;

  int get trashBytes => _trash.fold(0, (total, item) => total + item.bytes);

  int get staleTrashCount => _trash.where((item) => item.stale).length;

  int get pinnedClipCount => _clips.where((clip) => clip.pinned).length;

  int get enabledLaunchItems =>
      _launchItems.where((item) => item.enabled).length;

  /// What is still on the disk to be found. Falls as the visitor reclaims.
  int get reclaimableBytes {
    final source = _phase == PreviewScanPhase.idle ? junk : _found;
    return source.fold(0, (total, kind) => total + kind.bytes) -
        _reclaimedBytes;
  }

  bool isSelected(PreviewJunk kind) => _selected.contains(kind.id);

  /// The figure on the reclaim button. Nothing ticked, nothing to press.
  int get selectedBytes =>
      _found.where(isSelected).fold(0, (total, kind) => total + kind.bytes);

  int get freeBytes =>
      math.min(diskTotalBytes, _baseFreeBytes + _reclaimedBytes);

  int get usedBytes => diskTotalBytes - freeBytes;

  double get usedFraction => usedBytes / diskTotalBytes;

  /// Out of 100. Climbs as junk goes and unused apps come off, so the number at
  /// the top of the dashboard answers to what the visitor has been doing.
  int get healthScore {
    final reclaimedGb = _reclaimedBytes / _gb;
    final penalty = (reclaimableBytes / _gb) * 1.4 + unusedAppCount * 2.0;
    return (72 + reclaimedGb * 1.6 - penalty + 18).clamp(1, 100).round();
  }

  List<PreviewApp> get visibleApps {
    if (_appQuery.isEmpty) return apps;
    final needle = _appQuery.toLowerCase();
    return _apps
        .where(
          (app) =>
              app.name.toLowerCase().contains(needle) ||
              app.developer.toLowerCase().contains(needle),
        )
        .toList();
  }

  // ─── Network ─────────────────────────────────────────────────────────────

  /// A minute of readings, newest last, in bytes per second.
  final List<double> _down = List<double>.filled(60, 0, growable: true);
  final List<double> _up = List<double>.filled(60, 0, growable: true);

  List<double> get down => List.unmodifiable(_down);
  List<double> get up => List.unmodifiable(_up);

  int _tick = 0;

  PreviewMac() {
    for (var i = 0; i < 60; i++) {
      _tick = i;
      _down[i] = _syntheticDown(i);
      _up[i] = _syntheticUp(i);
    }
  }

  /// Deterministic rather than random: a page that renders a different chart on
  /// every reload looks unfinished, and `Math.random` in a build would make the
  /// shape jump on every repaint.
  double _syntheticDown(int t) =>
      (2.4 + math.sin(t / 4.7) * 1.6 + math.sin(t / 1.9) * 0.7).abs() * _mb;

  double _syntheticUp(int t) =>
      (0.5 + math.sin(t / 6.1 + 1.2) * 0.34 + math.sin(t / 2.3) * 0.18).abs() *
      _mb;

  int get downNowBytes => _down.last.round();
  int get upNowBytes => _up.last.round();

  int get todayDownBytes => 4 * _gb + 380 * _mb;
  int get todayUpBytes => 740 * _mb;

  /// Advances the live chart by one reading. Driven by the pane that is showing
  /// it, so nothing keeps ticking behind a page nobody is looking at.
  void tickNetwork() {
    _tick++;
    _down
      ..removeAt(0)
      ..add(_syntheticDown(_tick));
    _up
      ..removeAt(0)
      ..add(_syntheticUp(_tick));
    notifyListeners();
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  /// Streams the four categories in over a couple of seconds, the way the real
  /// scan does.
  Future<void> scan() async {
    if (_phase == PreviewScanPhase.scanning) return;

    _phase = PreviewScanPhase.scanning;
    _scanProgress = null;
    _found.clear();
    _selected.clear();
    notifyListeners();

    // Indeterminate for a beat before the first category lands, so the ring
    // spins rather than snapping to a number it could not have known yet.
    await Future<void>.delayed(const Duration(milliseconds: 420));

    for (var i = 0; i < junk.length; i++) {
      if (_disposed) return;
      await Future<void>.delayed(const Duration(milliseconds: 380));
      _found.add(junk[i]);
      _scanProgress = (i + 1) / junk.length;
      // Only `safe` is ticked for you. Saved app state and orphans are
      // inferences, and an inference is never pre-selected.
      if (junk[i].safety == SafetyLevel.safe) _selected.add(junk[i].id);
      notifyListeners();
    }

    if (_disposed) return;
    _phase = PreviewScanPhase.results;
    notifyListeners();
  }

  void toggleJunk(PreviewJunk kind) {
    if (!_selected.remove(kind.id)) _selected.add(kind.id);
    notifyListeners();
  }

  /// Moves what is ticked to the Trash and credits the space back.
  ///
  /// The real app is careful here — moving to the Trash frees nothing until the
  /// Trash is emptied, and it says "moved to Trash" rather than claiming space
  /// it has not returned. The preview keeps that distinction: the bytes land in
  /// the Recycle Bin pane, and the free-space bar only moves when the Trash is
  /// emptied.
  void reclaimSelected() {
    if (_selected.isEmpty) return;

    final taken = _found.where(isSelected).toList();
    for (final kind in taken) {
      _trash.insert(
        0,
        PreviewTrashItem(
          name: kind.title,
          bytes: kind.bytes,
          deleted: 'Just now',
        ),
      );
      _found.remove(kind);
    }
    _selected.clear();
    if (_found.isEmpty) _phase = PreviewScanPhase.idle;
    notifyListeners();
  }

  /// Empties the Trash. This is the only thing here that actually frees space,
  /// which is exactly the distinction the app makes.
  void emptyTrash() {
    if (_trash.isEmpty) return;
    _reclaimedBytes += trashBytes;
    _trash.clear();
    notifyListeners();
  }

  void putBack(PreviewTrashItem item) {
    _trash.remove(item);
    notifyListeners();
  }

  /// Uninstalls an app and everything it left behind — into the Trash, so it is
  /// recoverable, which is what `FileManager.trashItem` buys the real app.
  void uninstall(PreviewApp app) {
    _apps.remove(app);
    _trash.insert(
      0,
      PreviewTrashItem(
        name: '${app.name}.app',
        bytes: app.bytes + app.leftoverBytes,
        deleted: 'Just now',
      ),
    );
    notifyListeners();
  }

  void setAppQuery(String value) {
    if (_appQuery == value) return;
    _appQuery = value;
    notifyListeners();
  }

  void togglePin(PreviewClip clip) {
    final index = _clips.indexOf(clip);
    if (index < 0) return;
    _clips[index] = clip.copyWith(pinned: !clip.pinned);
    notifyListeners();
  }

  void toggleLaunchItem(PreviewLaunchItem item) {
    final index = _launchItems.indexOf(item);
    if (index < 0) return;
    // Disabled, not deleted. The app never removes a launch item — it turns it
    // off, because a login item you can put back is a different promise.
    _launchItems[index] = item.copyWith(enabled: !item.enabled);
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
