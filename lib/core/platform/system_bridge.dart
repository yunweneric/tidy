import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Free/total capacity of the boot volume.
class DiskUsage {
  const DiskUsage({required this.totalBytes, required this.freeBytes});

  final int totalBytes;
  final int freeBytes;

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);

  double get usedFraction => totalBytes == 0 ? 0 : usedBytes / totalBytes;

  static const DiskUsage empty = DiskUsage(totalBytes: 0, freeBytes: 0);
}

/// One path that could not be removed, with the reason macOS gave.
class RemovalFailure {
  const RemovalFailure({required this.path, required this.error});

  final String path;
  final String error;
}

/// Outcome of a trash/delete request.
class RemovalResult {
  const RemovalResult({required this.removed, required this.failures});

  final List<String> removed;
  final List<RemovalFailure> failures;

  bool get isCompleteSuccess => failures.isEmpty;

  static const RemovalResult empty = RemovalResult(removed: [], failures: []);
}

/// Thin wrapper over the native macOS helpers in `macos/Runner/SystemChannel.swift`.
///
/// Removal goes through `FileManager` rather than `rm` so that "move to Trash"
/// is genuinely recoverable and per-item failures surface instead of being
/// swallowed by a shell exit code nobody checks.
class SystemBridge {
  SystemBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.macuninstaller/system',
  );

  /// Moves [paths] to the user's Trash.
  static Future<RemovalResult> trashItems(List<String> paths) =>
      _remove('trashItems', paths);

  /// Permanently deletes [paths]. Nothing is recoverable afterwards.
  static Future<RemovalResult> deleteItems(List<String> paths) =>
      _remove('deleteItems', paths);

  static Future<RemovalResult> _remove(String method, List<String> paths) async {
    if (paths.isEmpty) return RemovalResult.empty;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(method, {
        'paths': paths,
      });
      if (result == null) return RemovalResult.empty;

      final removed = (result['removed'] as List?)?.cast<String>() ?? const [];
      final failures = ((result['failures'] as List?) ?? const [])
          .map(
            (raw) => RemovalFailure(
              path: (raw as Map)['path'] as String? ?? '',
              error: raw['error'] as String? ?? 'Unknown error',
            ),
          )
          .toList();
      return RemovalResult(removed: removed, failures: failures);
    } catch (e) {
      final message = e is PlatformException ? (e.message ?? e.code) : e.toString();
      return RemovalResult(
        removed: const [],
        failures: paths.map((p) => RemovalFailure(path: p, error: message)).toList(),
      );
    }
  }

  /// Capacity of the volume backing `/`.
  static Future<DiskUsage> diskUsage() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('diskUsage');
      if (result == null) return DiskUsage.empty;
      return DiskUsage(
        totalBytes: (result['total'] as num?)?.toInt() ?? 0,
        freeBytes: (result['free'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('diskUsage failed: $e');
      return DiskUsage.empty;
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
      final result = await _channel.invokeMapMethod<String, dynamic>('iconsForPaths', {
        'paths': paths,
        'size': size,
      });
      if (result == null) return const {};
      return result.map(
        (path, bytes) => MapEntry(path, bytes as Uint8List),
      );
    } catch (e) {
      debugPrint('iconsForPaths failed: $e');
      return const {};
    }
  }

  /// Reveals [path] in Finder (used to inspect leftovers before removing them).
  static Future<void> revealInFinder(String path) async {
    try {
      await _channel.invokeMethod<void>('revealInFinder', {'path': path});
    } catch (e) {
      debugPrint('revealInFinder failed: $e');
    }
  }

  /// Opens System Settings → Privacy & Security → Full Disk Access.
  static Future<void> openFullDiskAccessSettings() async {
    try {
      await _channel.invokeMethod<void>('openFullDiskAccessSettings');
    } catch (e) {
      debugPrint('openFullDiskAccessSettings failed: $e');
    }
  }
}
