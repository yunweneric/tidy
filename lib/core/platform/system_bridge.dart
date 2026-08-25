import 'package:flutter/services.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/platform/action_outcome.dart';
import 'package:tidy/core/platform/trash_ledger.dart';

/// Free/total capacity of the boot volume.
class DiskUsage {
  const DiskUsage({required this.totalBytes, required this.freeBytes});

  final int totalBytes;
  final int freeBytes;

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);

  double get usedFraction => totalBytes == 0 ? 0 : usedBytes / totalBytes;

  static const DiskUsage empty = DiskUsage(totalBytes: 0, freeBytes: 0);
}

/// One entry in a directory, with its full recursive allocated size.
class DirectoryEntry {
  const DirectoryEntry({
    required this.path,
    required this.sizeBytes,
    required this.isDirectory,
    this.modified,
  });

  final String path;
  final int sizeBytes;
  final bool isDirectory;
  final DateTime? modified;

  String get name => path.split('/').last;
}

/// One path that could not be removed, with the reason macOS gave.
class RemovalFailure {
  const RemovalFailure({required this.path, required this.error});

  final String path;
  final String error;
}

/// Outcome of a trash/delete request.
class RemovalResult {
  const RemovalResult({
    required this.removed,
    required this.failures,
    this.trashedTo = const {},
  });

  final List<String> removed;
  final List<RemovalFailure> failures;

  /// Original path to where it landed in the Trash. Only a trash request fills
  /// this in, and only for items macOS actually moved.
  final Map<String, String> trashedTo;

  bool get isCompleteSuccess => failures.isEmpty;

  static const RemovalResult empty = RemovalResult(removed: [], failures: []);
}

/// Identity of the running `.app` bundle.
class AppBundleInfo {
  const AppBundleInfo({
    required this.version,
    required this.build,
    required this.bundlePath,
    required this.installWritable,
  });

  /// `CFBundleShortVersionString` — the number a user recognises.
  final String version;

  /// `CFBundleVersion`.
  final String build;

  final String bundlePath;

  /// Whether the folder holding the bundle can be written to by this user.
  ///
  /// This is what decides whether the app can replace itself at all. An app in
  /// `/Applications` on a Mac whose owner is an admin: yes. The same app on a
  /// managed or standard account: no, and the update has to be installed by
  /// hand from the disk image.
  final bool installWritable;

  static const AppBundleInfo unknown = AppBundleInfo(
    version: '0.0.0',
    build: '0',
    bundlePath: '',
    installWritable: false,
  );
}

/// Thin wrapper over the native macOS helpers in `macos/Runner/SystemChannel.swift`.
///
/// Removal goes through `FileManager` rather than `rm` so that "move to Trash"
/// is genuinely recoverable and per-item failures surface instead of being
/// swallowed by a shell exit code nobody checks.
class SystemBridge {
  SystemBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.tidy/system',
  );

  /// Moves [paths] to the user's Trash.
  ///
  /// Records where each item came from in [TrashLedger] on the way through.
  /// Here rather than at the call sites because this is the app's only route to
  /// the Trash, so recording here is the only version of it that cannot be
  /// forgotten by a new scanner — and without a record, Recycle Bin's "Put
  /// Back" has nowhere to put anything back to.
  static Future<RemovalResult> trashItems(List<String> paths) async {
    final result = await _remove('trashItems', paths);
    if (result.trashedTo.isNotEmpty) {
      await TrashLedger.instance.record(result.trashedTo);
    }
    return result;
  }

  /// Permanently deletes [paths]. Nothing is recoverable afterwards.
  static Future<RemovalResult> deleteItems(List<String> paths) =>
      _remove('deleteItems', paths);

  static Future<RemovalResult> _remove(
    String method,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return RemovalResult.empty;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(method, {
        'paths': paths,
      });
      if (result == null) return RemovalResult.empty;

      final removed = (result['removed'] as List?)?.cast<String>() ?? const [];
      final trashedTo = ((result['trashed'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(key as String, value as String),
      );
      final failures =
          ((result['failures'] as List?) ?? const [])
              .map(
                (raw) => RemovalFailure(
                  path: (raw as Map)['path'] as String? ?? '',
                  error: raw['error'] as String? ?? 'Unknown error',
                ),
              )
              .toList();
      return RemovalResult(
        removed: removed,
        failures: failures,
        trashedTo: trashedTo,
      );
    } catch (e) {
      final message =
          e is PlatformException ? (e.message ?? e.code) : e.toString();
      // Error, not warning: nothing downstream recovers from this. Every path
      // in the request comes back as a failure and the user is told the clean
      // did not happen.
      AppLog.platform.error(
        'removal call failed',
        error: e,
        fields: {'method': method, 'count': paths.length},
      );
      return RemovalResult(
        removed: const [],
        failures:
            paths.map((p) => RemovalFailure(path: p, error: message)).toList(),
      );
    }
  }

  /// Capacity of the volume backing `/`.
  static Future<DiskUsage> diskUsage() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'diskUsage',
      );
      if (result == null) return DiskUsage.empty;
      return DiskUsage(
        totalBytes: (result['total'] as num?)?.toInt() ?? 0,
        freeBytes: (result['free'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      AppLog.platform.failed('read disk usage', e);
      return DiskUsage.empty;
    }
  }

  /// Allocated bytes for each of [paths], walked natively with `fts(3)`.
  ///
  /// Batched deliberately: one call for a thousand paths, not a thousand calls.
  static Future<Map<String, int>> sizeOfPaths(List<String> paths) async {
    if (paths.isEmpty) return const {};
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'sizeOfPaths',
        {'paths': paths},
      );
      if (result == null) return const {};
      return result.map((path, size) => MapEntry(path, (size as num).toInt()));
    } catch (e) {
      AppLog.platform.failed('size paths', e, fields: {'count': paths.length});
      return const {};
    }
  }

  /// Immediate children of [path] with their full recursive sizes. Backs the
  /// disk map and any "what is big in here" view.
  static Future<List<DirectoryEntry>> childSizes(String path) async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('childSizes', {
        'path': path,
      });
      if (result == null) return const [];
      return result.map((raw) {
        final map = (raw as Map).cast<String, dynamic>();
        final modified = (map['modified'] as num?)?.toInt() ?? 0;
        return DirectoryEntry(
          path: map['path'] as String? ?? '',
          sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
          isDirectory: map['isDirectory'] as bool? ?? false,
          modified:
              modified == 0
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(modified * 1000),
        );
      }).toList();
    } catch (e) {
      AppLog.platform.failed('list child sizes', e, fields: {'path': path});
      return const [];
    }
  }

  /// Rendered icons for app bundles, keyed by bundle path.
  ///
  /// Uses `NSWorkspace`, which resolves .icns files, asset-catalog icons and
  /// generic fallbacks alike — far cheaper and more complete than shelling out
  /// to `iconutil` per bundle.
  static Future<Map<String, Uint8List>> iconsForPaths(
    List<String> paths, {
    double size = 64,
  }) async {
    if (paths.isEmpty) return const {};
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'iconsForPaths',
        {'paths': paths, 'size': size},
      );
      if (result == null) return const {};
      return result.map((path, bytes) => MapEntry(path, bytes as Uint8List));
    } catch (e) {
      AppLog.platform.failed('read icons', e, fields: {'count': paths.length});
      return const {};
    }
  }

  /// Reveals [path] in Finder (used to inspect leftovers before removing them).
  static Future<void> revealInFinder(String path) async {
    try {
      await _channel.invokeMethod<void>('revealInFinder', {'path': path});
    } catch (e) {
      AppLog.platform.failed('reveal in Finder', e, fields: {'path': path});
    }
  }

  /// Opens System Settings → Privacy & Security → Full Disk Access.
  static Future<void> openFullDiskAccessSettings() async {
    try {
      await _channel.invokeMethod<void>('openFullDiskAccessSettings');
    } catch (e) {
      AppLog.platform.failed('open the Full Disk Access settings', e);
    }
  }

  /// Version, build and location of the running bundle.
  ///
  /// Read from `Bundle.main` on the native side rather than from a generated
  /// Dart constant: the number that matters is the one in the `Info.plist` of
  /// the bundle actually on disk, which is what the updater is about to
  /// replace, and what macOS itself reports about the app.
  static Future<AppBundleInfo> appVersion() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'appVersion',
      );
      if (result == null) return AppBundleInfo.unknown;
      return AppBundleInfo(
        version: result['version'] as String? ?? '0.0.0',
        build: result['build'] as String? ?? '0',
        bundlePath: result['bundlePath'] as String? ?? '',
        installWritable: result['installWritable'] as bool? ?? false,
      );
    } catch (e) {
      AppLog.platform.failed('read the app version', e);
      return AppBundleInfo.unknown;
    }
  }

  /// Whether the app launches at login, and whether macOS lets us ask.
  ///
  /// `SMAppService` arrived in macOS 13 and the app supports 11, so
  /// `available` is false on older systems and the Settings row hides itself
  /// rather than offering a switch that cannot do anything.
  static Future<({bool available, bool enabled})> loginItemStatus() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'loginItemStatus',
      );
      return (
        available: result?['available'] as bool? ?? false,
        enabled: result?['enabled'] as bool? ?? false,
      );
    } catch (e) {
      AppLog.platform.failed('read the login item status', e);
      return (available: false, enabled: false);
    }
  }

  static Future<ActionOutcome> setLoginItem({required bool enabled}) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setLoginItem',
        {'enabled': enabled},
      );
      return ActionOutcome.fromMap(result);
    } catch (e) {
      final message =
          e is PlatformException ? (e.message ?? e.code) : e.toString();
      AppLog.platform.failed(
        'change the login item',
        e,
        fields: {'enabled': enabled},
      );
      return ActionOutcome(ok: false, message: message);
    }
  }

  /// Opens a Privacy & Security pane by anchor, e.g. `Privacy_Accessibility`.
  static Future<void> openSettingsPane(String anchor) async {
    try {
      await _channel.invokeMethod<void>('openSettingsPane', {'anchor': anchor});
    } catch (e) {
      AppLog.platform.failed(
        'open a Settings pane',
        e,
        fields: {'anchor': anchor},
      );
    }
  }

  /// Whether the app currently holds Full Disk Access.
  ///
  /// There is no API to *request* it — macOS grants it only when the user adds
  /// the app by hand — so this probes a TCC-protected read. Note the grant is
  /// cached per process: after the user grants it, the app must be relaunched
  /// before this flips to true.
  static Future<bool> hasFullDiskAccess() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'fullDiskAccessStatus',
      );
      return result?['granted'] as bool? ?? false;
    } catch (e) {
      AppLog.platform.failed('probe Full Disk Access', e);
      // Assume access rather than hiding features behind a failed probe.
      return true;
    }
  }

  /// Reads another app's container, putting macOS's own dialog on screen if it
  /// has not asked yet.
  ///
  /// Sonoma carved `kTCCServiceSystemPolicyAppData` out of Full Disk Access,
  /// and there is no way to check it without asking — the first access *is* the
  /// request. Only the onboarding permissions step and the Permissions settings
  /// tab call this, so the dialog always arrives next to an explanation of what
  /// it is for.
  static Future<bool> requestAppDataAccess() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'requestAppDataAccess',
      );
      return result?['granted'] as bool? ?? false;
    } catch (e) {
      AppLog.platform.failed('request access to other apps’ data', e);
      // Assume access rather than hiding features behind a failed probe, the
      // same way `hasFullDiskAccess` does.
      return true;
    }
  }

  /// The same probe, for a screen reporting state after the question has
  /// already been put once. Silent, because TCC has the answer cached.
  static Future<bool> hasAppDataAccess() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'appDataAccessStatus',
      );
      return result?['granted'] as bool? ?? false;
    } catch (e) {
      AppLog.platform.failed('probe access to other apps’ data', e);
      return true;
    }
  }

  /// Opens Privacy & Security → Files and Folders, which is where this
  /// permission is listed — not under Full Disk Access, where people look.
  static Future<void> openAppDataSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppDataSettings');
    } catch (e) {
      AppLog.platform.failed('open the Files and Folders settings', e);
    }
  }

  /// Which of [paths] we can actually read, so a scanner can report "denied"
  /// instead of a confident zero.
  static Future<Map<String, bool>> canReadPaths(List<String> paths) async {
    if (paths.isEmpty) return const {};
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'canReadPaths',
        {'paths': paths},
      );
      if (result == null) return const {};
      return result.map((path, readable) => MapEntry(path, readable as bool));
    } catch (e) {
      AppLog.platform.failed(
        'check which paths are readable',
        e,
        fields: {'count': paths.length},
      );
      return {for (final path in paths) path: true};
    }
  }
}
