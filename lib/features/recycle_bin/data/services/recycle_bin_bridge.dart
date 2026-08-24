import 'package:flutter/foundation.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:flutter/services.dart';

/// Where one item ended up after being restored.
@immutable
class RestoredItem {
  const RestoredItem({required this.from, required this.to});

  /// Where it was in the Trash.
  final String from;

  /// Where it is now. Not always the folder that was asked for, name-wise:
  /// something already called that gets " 2" appended rather than overwritten.
  final String to;
}

/// One item that could not be restored, with the reason macOS gave.
@immutable
class RestoreFailure {
  const RestoreFailure({required this.path, required this.error});

  final String path;
  final String error;
}

/// Outcome of a restore request.
@immutable
class RestoreResult {
  const RestoreResult({required this.restored, required this.failures});

  static const RestoreResult empty = RestoreResult(
    restored: [],
    failures: [],
  );

  final List<RestoredItem> restored;
  final List<RestoreFailure> failures;

  bool get isCompleteSuccess => failures.isEmpty;
}

/// Thin wrapper over `macos/Runner/RecycleBinChannel.swift`.
///
/// Reading and restoring only. Permanent removal deliberately is not here — it
/// goes through [SystemBridge.deleteItems] so it passes the same `isRemovable`
/// guard as every other deletion in the app, rather than getting a second,
/// less-guarded route of its own.
class RecycleBinBridge {
  RecycleBinBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.tidy/recycle-bin',
  );

  /// Every trash folder and everything in them, sized. One call: a bin with two
  /// thousand items in it is one native walk, not two thousand round trips.
  static Future<Map<String, dynamic>> readBins() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('readBins');
      return result ?? const {};
    } catch (e) {
      AppLog.recycleBin.failed('read the trash folders', e);
      return const {};
    }
  }

  /// Moves items out of the Trash. [moves] pairs a trashed path with the folder
  /// it should go into.
  static Future<RestoreResult> restore(List<Map<String, String>> moves) async {
    if (moves.isEmpty) return RestoreResult.empty;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'restoreItems',
        {'moves': moves},
      );
      if (result == null) return RestoreResult.empty;

      final restored =
          ((result['restored'] as List?) ?? const []).map((raw) {
            final map = (raw as Map);
            return RestoredItem(
              from: map['from'] as String? ?? '',
              to: map['to'] as String? ?? '',
            );
          }).toList();

      final failures =
          ((result['failures'] as List?) ?? const []).map((raw) {
            final map = (raw as Map);
            return RestoreFailure(
              path: map['path'] as String? ?? '',
              error: map['error'] as String? ?? 'Unknown error',
            );
          }).toList();

      return RestoreResult(restored: restored, failures: failures);
    } catch (e) {
      final message =
          e is PlatformException ? (e.message ?? e.code) : e.toString();
      return RestoreResult(
        restored: const [],
        failures: [
          for (final move in moves)
            RestoreFailure(path: move['from'] ?? '', error: message),
        ],
      );
    }
  }

  /// Asks the user for a folder. Null when they cancel, which is an ordinary
  /// outcome rather than a failure and must not be reported as one.
  static Future<String?> chooseFolder({
    required String prompt,
    required String message,
  }) async {
    try {
      return await _channel.invokeMethod<String>('chooseFolder', {
        'prompt': prompt,
        'message': message,
      });
    } catch (e) {
      AppLog.recycleBin.failed('open the folder picker', e);
      return null;
    }
  }
}
