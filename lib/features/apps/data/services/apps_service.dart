import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/utils/disk_utils.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';

/// Discovers installed applications and their on-disk footprint.
///
/// The scan runs in two passes so the table can render quickly:
///  1. [scanApps] — metadata + size + last-used date for every bundle.
///  2. [attachIcons] — icons, streamed in batches once the list is on screen.
class AppManagerService {
  /// Locations the user can install into (and therefore uninstall from).
  static const List<String> userAppRoots = ['/Applications'];

  /// Read-only, SIP-protected system apps. Listed for context, never removable.
  static const String systemAppRoot = '/System/Applications';

  /// Bundles per `mdls` invocation.
  static const int _mdlsChunkSize = 100;

  /// Bundles per icon batch handed to the platform channel.
  static const int _iconChunkSize = 24;

  static String? get _home => Platform.environment['HOME'];

  /// Roots that are scanned for removable apps.
  static List<String> get removableRoots => [
    ...userAppRoots,
    if (_home != null) '$_home/Applications',
  ];

  /// Metadata pass. Returns apps sorted largest first.
  Future<List<MacApp>> scanApps() async {
    final bundles = _discoverBundles();

    // Sizes come back in a single native walk; metadata still needs one plist
    // read per bundle, which is what the pool is for.
    final sizes = await pathSizes(bundles.map((ref) => ref.path).toList());
    final apps = await mapPooled<_BundleRef, MacApp?>(
      bundles,
      (ref) => _readBundle(ref, sizes[ref.path] ?? 0),
    );

    final found = apps.whereType<MacApp>().toList();
    final withDates = await _attachLastUsed(found);

    withDates.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return withDates;
  }

  /// Icon pass. Yields the whole list again after each batch so the caller can
  /// emit progressive updates without tracking indices itself.
  Stream<List<MacApp>> attachIcons(List<MacApp> apps) async* {
    final working = List<MacApp>.from(apps);

    for (var start = 0; start < working.length; start += _iconChunkSize) {
      final end = (start + _iconChunkSize).clamp(0, working.length);
      final chunk = working.sublist(start, end);
      final icons = await SystemBridge.iconsForPaths(
        chunk.map((a) => a.path).toList(),
      );
      if (icons.isEmpty) continue;

      for (var i = start; i < end; i++) {
        final bytes = icons[working[i].path];
        if (bytes != null) {
          working[i] = working[i].copyWith(iconBytes: bytes);
        }
      }
      yield List<MacApp>.from(working);
    }
  }

  /// Moves [paths] to the Trash, or deletes them outright when [toTrash] is
  /// false. Always driven from a preview the user has confirmed.
  Future<RemovalResult> remove(List<String> paths, {required bool toTrash}) {
    return toTrash ? SystemBridge.trashItems(paths) : SystemBridge.deleteItems(paths);
  }

  // ---------------------------------------------------------------- discovery

  List<_BundleRef> _discoverBundles() {
    final bundles = <_BundleRef>[];
    final seen = <String>{};

    void collect(String root, {required bool isSystem}) {
      final dir = Directory(root);
      if (!dir.existsSync()) return;

      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException catch (e) {
        debugPrint('Cannot list $root: ${e.message}');
        return;
      }

      for (final entity in entries) {
        if (entity is! Directory) continue;
        final path = entity.path;

        if (path.endsWith('.app')) {
          if (seen.add(path)) {
            bundles.add(_BundleRef(path: path, isSystem: isSystem));
          }
          continue;
        }

        // One level deeper for grouping folders like /Applications/Utilities.
        try {
          for (final nested in entity.listSync(followLinks: false)) {
            if (nested is Directory && nested.path.endsWith('.app')) {
              if (seen.add(nested.path)) {
                bundles.add(_BundleRef(path: nested.path, isSystem: isSystem));
              }
            }
          }
        } on FileSystemException {
          // Unreadable subfolder — skip it rather than failing the whole scan.
        }
      }
    }

    for (final root in removableRoots) {
      collect(root, isSystem: false);
    }
    collect(systemAppRoot, isSystem: true);

    return bundles;
  }

  // ----------------------------------------------------------------- metadata

  Future<MacApp?> _readBundle(_BundleRef ref, int sizeBytes) async {
    final fileName = ref.path.split('/').last;
    final fallbackName = fileName.replaceAll(RegExp(r'\.app$'), '');

    final info = await _readPlist(ref.path);

    final name = _firstNonEmpty([
      info['CFBundleDisplayName'],
      info['CFBundleName'],
      fallbackName,
    ]);
    final bundleId = info['CFBundleIdentifier'] ?? '';

    return MacApp(
      name: name,
      path: ref.path,
      version: _firstNonEmpty([
        info['CFBundleShortVersionString'],
        info['CFBundleVersion'],
      ]),
      bundleId: bundleId,
      sizeBytes: sizeBytes,
      developer: _developerFrom(bundleId, info['NSHumanReadableCopyright']),
      isSystem: ref.isSystem,
    );
  }

  Future<Map<String, String>> _readPlist(String bundlePath) async {
    try {
      final result = await Process.run('plutil', [
        '-convert',
        'json',
        '-o',
        '-',
        '$bundlePath/Contents/Info.plist',
      ]);
      if (result.exitCode != 0) return {};

      final decoded = jsonDecode(result.stdout as String);
      if (decoded is! Map) return {};

      // Only scalar keys are interesting; drop nested arrays/dicts.
      return {
        for (final entry in decoded.entries)
          if (entry.value is String || entry.value is num)
            entry.key as String: '${entry.value}',
      };
    } catch (_) {
      return {};
    }
  }

  /// Fills in `lastUsed` from Spotlight, one `mdls` call per 100 bundles.
  Future<List<MacApp>> _attachLastUsed(List<MacApp> apps) async {
    if (apps.isEmpty) return apps;

    final result = List<MacApp>.from(apps);

    for (var start = 0; start < result.length; start += _mdlsChunkSize) {
      final end = (start + _mdlsChunkSize).clamp(0, result.length);
      final chunk = result.sublist(start, end);

      try {
        final process = await Process.run('mdls', [
          '-raw',
          '-name',
          'kMDItemLastUsedDate',
          ...chunk.map((a) => a.path),
        ]);
        if (process.exitCode != 0) continue;

        // `mdls -raw` separates values for multiple files with NUL bytes and
        // preserves argument order.
        final values = process.stdout.toString().split('\x00');
        if (values.length < chunk.length) continue;

        for (var i = 0; i < chunk.length; i++) {
          final parsed = _parseMdlsDate(values[i]);
          if (parsed != null) {
            result[start + i] = result[start + i].copyWith(lastUsed: parsed);
          }
        }
      } catch (e) {
        debugPrint('mdls chunk failed: $e');
      }
    }

    return result;
  }

  /// Parses `2026-08-16 20:17:19 +0000` as emitted by `mdls -raw`.
  static DateTime? _parseMdlsDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '(null)') return null;

    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) ([+-])(\d{2})(\d{2})$',
    ).firstMatch(value);
    if (match == null) return DateTime.tryParse(value);

    final utc = DateTime.tryParse('${match[1]}T${match[2]}Z');
    if (utc == null) return null;

    final offset =
        Duration(hours: int.parse(match[4]!), minutes: int.parse(match[5]!));
    final adjusted = match[3] == '+' ? utc.subtract(offset) : utc.add(offset);
    return adjusted.toLocal();
  }

  /// `com.google.Chrome` → `Google`; falls back to the copyright string.
  static String? _developerFrom(String bundleId, String? copyright) {
    final parts = bundleId.split('.');
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      final vendor = parts[1];
      return vendor[0].toUpperCase() + vendor.substring(1);
    }

    if (copyright == null || copyright.trim().isEmpty) return null;
    // "Copyright © 2026 Acme Inc. All rights reserved." → "Acme Inc."
    final cleaned = copyright
        .replaceAll(RegExp('copyright', caseSensitive: false), '')
        .replaceAll(RegExp(r'[©®]'), '')
        .replaceAll(RegExp(r'\b(19|20)\d{2}([-–]\d{2,4})?\b'), '')
        .replaceAll(RegExp(r'all rights reserved\.?', caseSensitive: false), '')
        .trim()
        .replaceAll(RegExp(r'^[,.\s]+|[,.\s]+$'), '');
    return cleaned.isEmpty ? null : cleaned;
  }

  static String _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null && candidate.trim().isNotEmpty) return candidate.trim();
    }
    return '';
  }

}

class _BundleRef {
  const _BundleRef({required this.path, required this.isSystem});

  final String path;
  final bool isSystem;
}
