import 'package:flutter/services.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/features/protection/data/models/signing_info.dart';

/// Thin wrapper over `macos/Runner/ProtectionChannel.swift`.
///
/// Every call degrades to a "could not read" rather than throwing, and that
/// distinction is carried rather than swallowed: this module's whole claim is
/// that it never reports an absence of findings it did not actually look for.
class ProtectionBridge {
  ProtectionBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.tidy/protection',
  );

  /// How many paths go over the channel at once.
  ///
  /// Reading a signature is three to six milliseconds, so the round trip would
  /// otherwise be the expensive half. Chunked rather than sent whole so the
  /// first rows can paint while the rest are still being read.
  static const int batch = 25;

  /// Signing information for many bundles. Reads; verifies nothing.
  static Future<Map<String, SigningInfo>> signingInfo(
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const {};
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'signingInfo',
        {'paths': paths},
      );
      if (raw == null) return const {};
      return {
        for (final entry in raw.entries)
          if (entry.value is Map)
            entry.key: SigningInfo.fromMap(
              entry.key,
              entry.value as Map<Object?, Object?>,
            ),
      };
    } catch (e) {
      AppLog.protection.failed(
        'read signatures',
        e,
        fields: {'count': paths.length},
      );
      return {for (final path in paths) path: SigningInfo.unchecked(path)};
    }
  }

  /// Where each of [paths] was downloaded from, for the ones that say.
  static Future<Map<String, QuarantineStamp>> quarantine(
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const {};
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'quarantineInfo',
        {'paths': paths},
      );
      if (raw == null) return const {};
      return {
        for (final entry in raw.entries)
          if (entry.value is Map)
            entry.key: QuarantineStamp.fromMap(
              entry.value as Map<Object?, Object?>,
            ),
      };
    } catch (e) {
      AppLog.protection.failed('read download records', e);
      return const {};
    }
  }

  /// The download history macOS keeps, newest first.
  ///
  /// Returns null when it could not be read, which the page shows as "could not
  /// read" — an empty list would claim this Mac has never downloaded anything.
  static Future<({List<DownloadEvent> events, int total})?> downloadEvents({
    int limit = 200,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'downloadEvents',
        {'limit': limit},
      );
      if (raw == null || raw['error'] != null) {
        if (raw?['error'] != null) {
          AppLog.protection.warn(
            'download history unreadable: ${raw!['error']}',
          );
        }
        return null;
      }
      final rows = raw['events'] as List? ?? const [];
      return (
        events: [
          for (final row in rows)
            if (row is Map) DownloadEvent.fromMap(row),
        ],
        total: (raw['total'] as num?)?.toInt() ?? rows.length,
      );
    } catch (e) {
      AppLog.protection.failed('read the download history', e);
      return null;
    }
  }

  /// Verifies one bundle's seal. **Seconds.** One item, on demand.
  static Future<({bool ok, String? reason})> validate(String path) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'validateSignature',
        {'path': path},
      );
      return (ok: raw?['ok'] == true, reason: raw?['reason'] as String?);
    } catch (e) {
      AppLog.protection.failed('check a signature', e, fields: {'path': path});
      return (ok: false, reason: 'Tidy could not run the check.');
    }
  }

  /// Asks Gatekeeper about one bundle. **A second or more.**
  static Future<({bool ok, String? reason})> assess(String path) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'assessGatekeeper',
        {'path': path},
      );
      return (ok: raw?['ok'] == true, reason: raw?['reason'] as String?);
    } catch (e) {
      AppLog.protection.failed('ask Gatekeeper', e, fields: {'path': path});
      return (ok: false, reason: 'Tidy could not ask.');
    }
  }

  /// Bundle ids of everything running right now.
  static Future<Set<String>> runningApps() async {
    try {
      final raw = await _channel.invokeListMethod<String>('runningBrowsers');
      return raw?.toSet() ?? const {};
    } catch (e) {
      AppLog.protection.failed('read what is running', e);
      return const {};
    }
  }
}
