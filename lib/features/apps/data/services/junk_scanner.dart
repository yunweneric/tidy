import 'dart:io';

import 'package:mac_uninstaller/core/utils/disk_utils.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';

/// Kinds of reclaimable space the scanner reports.
enum JunkKind {
  /// `~/Library/Caches/*` — regenerated on demand, safe to clear.
  caches('User Caches', 'Regenerated automatically the next time an app runs.'),

  /// `~/Library/Logs/*` — diagnostic output, safe to clear.
  logs('App Logs', 'Diagnostic logs written by installed apps.'),

  /// `~/Library/Saved Application State/*` — window restore data, safe to clear.
  savedState('Saved App State', 'Window and document restore data.'),

  /// Support/preference folders whose owning app is no longer installed.
  orphaned(
    'Orphaned Leftovers',
    'Files left behind by apps you no longer have.',
  );

  const JunkKind(this.label, this.description);

  final String label;
  final String description;

  /// Orphans are guesswork by nature, so they are never pre-selected.
  bool get safeByDefault => this != JunkKind.orphaned;
}

/// One removable chunk of junk.
class JunkItem {
  const JunkItem({
    required this.path,
    required this.sizeBytes,
    required this.kind,
    required this.label,
  });

  final String path;
  final int sizeBytes;
  final JunkKind kind;
  final String label;
}

/// A [JunkKind] with its items and total size.
class JunkGroup {
  const JunkGroup({required this.kind, required this.items});

  final JunkKind kind;
  final List<JunkItem> items;

  int get sizeBytes => items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
}

/// Result of a full junk sweep.
class JunkReport {
  const JunkReport({required this.groups});

  final List<JunkGroup> groups;

  static const JunkReport empty = JunkReport(groups: []);

  int get totalBytes =>
      groups.fold<int>(0, (sum, group) => sum + group.sizeBytes);

  /// Bytes that can be cleared without judgement calls — everything except
  /// orphaned leftovers.
  int get safeBytes => groups
      .where((group) => group.kind.safeByDefault)
      .fold<int>(0, (sum, group) => sum + group.sizeBytes);

  List<JunkItem> itemsOf(JunkKind kind) =>
      groups.where((g) => g.kind == kind).expand((g) => g.items).toList();

  List<String> pathsFor(Iterable<JunkKind> kinds) => [
    for (final group in groups)
      if (kinds.contains(group.kind))
        for (final item in group.items) item.path,
  ];
}

/// Finds space that can be reclaimed without uninstalling anything: caches,
/// logs, saved window state, and support folders whose app is long gone.
class JunkScanner {
  static String? get _home => Platform.environment['HOME'];

  /// Roots scanned for orphaned, bundle-id-named leftovers.
  static List<String> get _orphanRoots {
    final home = _home;
    if (home == null) return const [];
    return [
      '$home/Library/Application Support',
      '$home/Library/Caches',
      '$home/Library/Preferences',
      '$home/Library/HTTPStorages',
      '$home/Library/Containers',
    ];
  }

  /// A bundle-id-looking folder name: at least two dot-separated segments.
  static final RegExp _bundleIdPattern = RegExp(
    r'^[A-Za-z0-9_-]+(\.[A-Za-z0-9_+-]+){1,}$',
  );

  /// Vendors whose files belong to macOS itself and are never touched.
  static const List<String> _protectedPrefixes = ['com.apple.', 'apple.'];

  /// Folders that sit behind macOS privacy controls (Music, Photos, Contacts,
  /// Mail, …). Merely running `du` on them makes the system throw a TCC consent
  /// prompt at the user, and nothing in them is ours to delete, so they are
  /// skipped outright rather than scanned and filtered later.
  static const Set<String> _privacyProtectedNames = {
    'AddressBook',
    'CallHistoryDB',
    'CallHistoryTransactions',
    'CloudDocs',
    'Calendars',
    'FileProvider',
    'Group Containers',
    'HomeKit',
    'IdentityServices',
    'Knowledge',
    'Mail',
    'Messages',
    'Metadata',
    'Photos',
    'PersonalizationPortrait',
    'Reminders',
    'Safari',
    'Sharing',
    'Suggestions',
    'Trial',
  };

  /// True for anything owned by macOS or protected by privacy controls.
  static bool _isProtectedEntry(String name) {
    if (_protectedPrefixes.any(name.startsWith)) return true;
    return _privacyProtectedNames.contains(name);
  }

  Future<JunkReport> scan({required List<MacApp> installedApps}) async {
    final home = _home;
    if (home == null) return JunkReport.empty;

    final groups = await Future.wait([
      for (final kind in JunkKind.values)
        scanKind(kind, installedBundleIds: _bundleIdsOf(installedApps)),
    ]);

    return JunkReport(groups: groups.where((g) => g.items.isNotEmpty).toList());
  }

  /// One category at a time, so a caller can stream results as they land
  /// instead of waiting on the slowest root.
  ///
  /// [installedBundleIds] is only consulted for [JunkKind.orphaned]; taking ids
  /// rather than [MacApp]s keeps the argument cheap to hand to an isolate,
  /// since a MacApp drags its icon bytes along with it.
  Future<JunkGroup> scanKind(
    JunkKind kind, {
    Set<String> installedBundleIds = const {},
  }) async {
    final home = _home;
    if (home == null) return JunkGroup(kind: kind, items: const []);

    return switch (kind) {
      JunkKind.caches => _scanDirectory('$home/Library/Caches', kind),
      JunkKind.logs => _scanDirectory('$home/Library/Logs', kind),
      JunkKind.savedState => _scanDirectory(
        '$home/Library/Saved Application State',
        kind,
      ),
      JunkKind.orphaned => _scanOrphans(installedBundleIds),
    };
  }

  static Set<String> _bundleIdsOf(List<MacApp> apps) => {
    for (final app in apps)
      if (app.bundleId.isNotEmpty) app.bundleId,
  };

  /// Every immediate child of [root] counts as clearable junk, except those
  /// owned by macOS itself.
  Future<JunkGroup> _scanDirectory(String root, JunkKind kind) async {
    final entries =
        _childrenOf(
          root,
        ).where((path) => !_isProtectedEntry(path.split('/').last)).toList();
    final sizes = await pathSizes(entries);

    final items = <JunkItem>[
      for (final path in entries)
        if ((sizes[path] ?? 0) > 0)
          JunkItem(
            path: path,
            sizeBytes: sizes[path]!,
            kind: kind,
            label: path.split('/').last,
          ),
    ];
    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return JunkGroup(kind: kind, items: items);
  }

  /// Bundle-id-named folders with no matching installed app.
  Future<JunkGroup> _scanOrphans(Set<String> installedIds) async {
    final candidates = <String>[];
    for (final root in _orphanRoots) {
      for (final path in _childrenOf(root)) {
        final name = _stripKnownSuffix(path.split('/').last);
        if (!_bundleIdPattern.hasMatch(name)) continue;
        if (_isProtectedEntry(name)) continue;
        if (_belongsToInstalledApp(name, installedIds)) continue;
        candidates.add(path);
      }
    }

    final sizes = await pathSizes(candidates);

    final items = <JunkItem>[
      for (final path in candidates)
        if ((sizes[path] ?? 0) > 0)
          JunkItem(
            path: path,
            sizeBytes: sizes[path]!,
            kind: JunkKind.orphaned,
            label: path.split('/').last,
          ),
    ];
    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return JunkGroup(kind: JunkKind.orphaned, items: items);
  }

  /// True when [name] is, or is a child identifier of, an installed bundle id —
  /// e.g. `com.acme.Widget.helper` belongs to `com.acme.Widget`.
  static bool _belongsToInstalledApp(String name, Set<String> installedIds) {
    if (installedIds.contains(name)) return true;
    for (final id in installedIds) {
      if (name.startsWith('$id.') || id.startsWith('$name.')) return true;
    }
    return false;
  }

  static String _stripKnownSuffix(String name) {
    for (final suffix in const [
      '.plist',
      '.savedState',
      '.binarycookies',
      '.lockfile',
    ]) {
      if (name.endsWith(suffix)) {
        return name.substring(0, name.length - suffix.length);
      }
    }
    return name;
  }

  static List<String> _childrenOf(String root) {
    final dir = Directory(root);
    if (!dir.existsSync()) return const [];
    try {
      return dir.listSync(followLinks: false).map((e) => e.path).toList();
    } on FileSystemException {
      // Full Disk Access not granted for this location.
      return const [];
    }
  }
}
