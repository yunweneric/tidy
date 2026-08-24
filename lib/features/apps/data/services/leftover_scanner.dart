import 'dart:io';

import 'package:mac_uninstaller/core/utils/disk_utils.dart';
import 'package:mac_uninstaller/features/apps/data/models/leftover_item.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';

/// One directory that is searched for an app's leftovers.
class _SearchRoot {
  const _SearchRoot(this.path, this.category, {this.requiresAdmin = false});

  final String path;
  final LeftoverCategory category;
  final bool requiresAdmin;
}

/// Finds the support files an app leaves behind, so the uninstall preview can
/// show exactly what will be removed before anything is touched.
///
/// Matching is bundle-id first (`com.acme.Widget`, `com.acme.Widget.plist`,
/// `com.acme.Widget.helper.plist`), then an exact display-name match for the
/// apps that use human-readable folders. Prefix matching on the display name is
/// deliberately avoided — it is how cleaners end up deleting the wrong folder.
class LeftoverScanner {
  static String? get _home => Platform.environment['HOME'];

  static List<_SearchRoot> get _roots {
    final home = _home;
    return [
      if (home != null) ...[
        _SearchRoot(
          '$home/Library/Application Support',
          LeftoverCategory.applicationSupport,
        ),
        _SearchRoot('$home/Library/Caches', LeftoverCategory.caches),
        _SearchRoot('$home/Library/Preferences', LeftoverCategory.preferences),
        _SearchRoot('$home/Library/Logs', LeftoverCategory.logs),
        _SearchRoot('$home/Library/Containers', LeftoverCategory.containers),
        _SearchRoot(
          '$home/Library/Group Containers',
          LeftoverCategory.containers,
        ),
        _SearchRoot(
          '$home/Library/Application Scripts',
          LeftoverCategory.containers,
        ),
        _SearchRoot('$home/Library/HTTPStorages', LeftoverCategory.caches),
        _SearchRoot('$home/Library/WebKit', LeftoverCategory.caches),
        _SearchRoot('$home/Library/Cookies', LeftoverCategory.caches),
        _SearchRoot(
          '$home/Library/Saved Application State',
          LeftoverCategory.savedState,
        ),
        _SearchRoot(
          '$home/Library/LaunchAgents',
          LeftoverCategory.launchAgents,
        ),
      ],
      const _SearchRoot(
        '/Library/Application Support',
        LeftoverCategory.applicationSupport,
        requiresAdmin: true,
      ),
      const _SearchRoot(
        '/Library/Caches',
        LeftoverCategory.caches,
        requiresAdmin: true,
      ),
      const _SearchRoot(
        '/Library/Logs',
        LeftoverCategory.logs,
        requiresAdmin: true,
      ),
      const _SearchRoot(
        '/Library/LaunchAgents',
        LeftoverCategory.launchAgents,
        requiresAdmin: true,
      ),
      const _SearchRoot(
        '/Library/LaunchDaemons',
        LeftoverCategory.launchAgents,
        requiresAdmin: true,
      ),
      const _SearchRoot(
        '/Library/PreferencePanes',
        LeftoverCategory.other,
        requiresAdmin: true,
      ),
    ];
  }

  /// Leftovers belonging to [app], largest first. Never includes the bundle
  /// itself — the caller adds that as the first preview row.
  Future<List<LeftoverItem>> scan(MacApp app) async {
    if (app.isSystem) return const [];

    final matches = <_SearchRoot, List<String>>{};

    for (final root in _roots) {
      final dir = Directory(root.path);
      if (!dir.existsSync()) continue;

      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        // Usually a TCC denial (Full Disk Access not granted). Skip the root
        // rather than aborting the whole preview.
        continue;
      }

      for (final entity in entries) {
        final name = entity.path.split('/').last;
        if (!_matches(name, app)) continue;
        if (!_isSafeToRemove(entity.path, root.path)) continue;
        (matches[root] ??= []).add(entity.path);
      }
    }

    final flattened = <MapEntry<_SearchRoot, String>>[
      for (final entry in matches.entries)
        for (final path in entry.value) MapEntry(entry.key, path),
    ];

    final sizes = await pathSizes(
      flattened.map((entry) => entry.value).toList(),
    );

    final items = <LeftoverItem>[
      for (final entry in flattened)
        LeftoverItem(
          path: entry.value,
          sizeBytes: sizes[entry.value] ?? 0,
          category: entry.key.category,
          requiresAdmin: entry.key.requiresAdmin,
        ),
    ];

    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return items;
  }

  bool _matches(String entryName, MacApp app) {
    final bundleId = app.bundleId.trim();
    if (bundleId.length >= 5 && bundleId.contains('.')) {
      if (entryName == bundleId) return true;
      // com.acme.Widget.plist / com.acme.Widget.helper.plist /
      // com.acme.Widget.savedState / com.acme.Widget.binarycookies
      if (entryName.startsWith('$bundleId.')) return true;
      // Group containers are often "TEAMID.com.acme.Widget".
      if (entryName.endsWith('.$bundleId')) return true;
    }

    // Human-readable folders: exact match only, and never for names so short
    // or generic that a collision is likely.
    final name = app.name.trim();
    if (name.length >= 3 && !_ambiguousNames.contains(name.toLowerCase())) {
      if (entryName.toLowerCase() == name.toLowerCase()) return true;
      if (entryName.toLowerCase() == '${name.toLowerCase()}.plist') return true;
    }

    return false;
  }

  /// Display names too generic to match on — a folder called "Google" belongs
  /// to every Google app, not the one being uninstalled.
  static const Set<String> _ambiguousNames = {
    'google',
    'microsoft',
    'apple',
    'adobe',
    'com',
    'app',
    'application',
    'applications',
    'data',
    'preferences',
    'caches',
    'logs',
    'temp',
    'tmp',
  };

  /// Refuses anything that escaped its search root, lives under /System, or is
  /// the root itself. Belt and braces before handing paths to a delete call.
  static bool _isSafeToRemove(String path, String rootPath) {
    if (path == rootPath) return false;
    if (!path.startsWith('$rootPath/')) return false;
    if (path.startsWith('/System')) return false;
    if (path.split('/').length < 3) return false;

    final relative = path.substring(rootPath.length + 1);
    if (relative.isEmpty || relative.contains('/')) return false;

    return true;
  }
}
