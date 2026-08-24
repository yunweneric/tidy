import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/features/apps/data/models/mac_app_model.dart';
import 'package:path/path.dart' as p;

/// A previously persisted scan.
class CachedScan {
  const CachedScan({required this.apps, required this.scannedAt});

  final List<MacApp> apps;
  final DateTime scannedAt;

  Duration get age => DateTime.now().difference(scannedAt);
}

/// On-disk cache of the last scan, shared by the main window and the menu bar
/// popover.
///
/// The popover runs in a second Flutter engine — a separate Dart isolate that
/// cannot see the main window's bloc — so the cache is what keeps the two
/// views consistent, and what lets either one paint instantly instead of
/// re-scanning every disk on open.
class ScanCache {
  static const int _formatVersion = 1;
  static const String _appSupportFolder = 'Tidy';

  Directory? _cachedDir;

  Future<Directory?> _directory() async {
    if (_cachedDir != null) return _cachedDir;

    final home = Platform.environment['HOME'];
    if (home == null) return null;

    final dir = Directory(
      p.join(home, 'Library', 'Application Support', _appSupportFolder),
    );
    try {
      if (!dir.existsSync()) await dir.create(recursive: true);
      final icons = Directory(p.join(dir.path, 'icons'));
      if (!icons.existsSync()) await icons.create(recursive: true);
    } on FileSystemException catch (e) {
      AppLog.apps.failed(
        'create the cache directory',
        e,
        fields: {'path': dir.path},
      );
      return null;
    }

    return _cachedDir = dir;
  }

  Future<File?> _cacheFile() async {
    final dir = await _directory();
    if (dir == null) return null;
    return File(p.join(dir.path, 'scan_cache.json'));
  }

  /// Reads the last persisted scan, icons included. Returns null when there is
  /// no usable cache.
  Future<CachedScan?> read() async {
    try {
      final file = await _cacheFile();
      if (file == null || !file.existsSync()) return null;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      if (decoded['formatVersion'] != _formatVersion) return null;

      final scannedAt = DateTime.tryParse(
        decoded['scannedAt'] as String? ?? '',
      );
      final rawApps = decoded['apps'];
      if (scannedAt == null || rawApps is! List) return null;

      final dir = await _directory();
      final apps = <MacApp>[];
      for (final raw in rawApps) {
        if (raw is! Map) continue;
        final json = raw.cast<String, dynamic>();
        final app = MacApp.fromJson(json);
        apps.add(app.copyWith(iconBytes: await _readIcon(dir, app)));
      }
      return CachedScan(apps: apps, scannedAt: scannedAt);
    } catch (e) {
      AppLog.apps.failed('read the scan cache', e);
      return null;
    }
  }

  /// Persists [apps] plus any icons that are not cached yet.
  Future<void> write(List<MacApp> apps) async {
    try {
      final file = await _cacheFile();
      final dir = await _directory();
      if (file == null || dir == null) return;

      for (final app in apps) {
        await _writeIcon(dir, app);
      }

      await file.writeAsString(
        jsonEncode({
          'formatVersion': _formatVersion,
          'scannedAt': DateTime.now().toIso8601String(),
          'apps': apps.map((app) => app.toJson()).toList(),
        }),
      );
    } catch (e) {
      AppLog.apps.failed('write the scan cache', e);
    }
  }

  /// Drops [paths] from the cache after an uninstall, so the other view sees
  /// the removal without waiting for a full rescan.
  Future<void> removeApps(Iterable<String> paths) async {
    final cached = await read();
    if (cached == null) return;

    final removed = paths.toSet();
    await write(
      cached.apps.where((app) => !removed.contains(app.path)).toList(),
    );
  }

  /// Icons are stored as loose PNGs rather than base64 in the JSON so the cache
  /// file stays small enough to parse on every popover open.
  String _iconKey(MacApp app) {
    final raw = app.bundleId.isNotEmpty ? app.bundleId : app.path;
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  Future<Uint8List?> _readIcon(Directory? dir, MacApp app) async {
    if (dir == null) return null;
    final file = File(p.join(dir.path, 'icons', '${_iconKey(app)}.png'));
    if (!file.existsSync()) return null;
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _writeIcon(Directory dir, MacApp app) async {
    final bytes = app.iconBytes;
    if (bytes == null || bytes.isEmpty) return;

    final file = File(p.join(dir.path, 'icons', '${_iconKey(app)}.png'));
    if (file.existsSync()) return;
    try {
      await file.writeAsBytes(bytes);
    } on FileSystemException catch (e) {
      AppLog.apps.failed('cache an app icon', e, fields: {'app': app.name});
    }
  }
}
