import 'package:flutter/services.dart';
import 'package:tidy/core/logging/logging.dart';

/// A downloaded update that has been unpacked, checked and put where the swap
/// can reach it.
class PreparedUpdate {
  const PreparedUpdate({
    required this.ok,
    this.stagedPath,
    this.version,
    this.message,
    this.canRetryManually = false,
  });

  final bool ok;

  /// The staged `.app`, beside the installed one. Null when [ok] is false.
  final String? stagedPath;

  /// The version read back out of the staged bundle, rather than the one the
  /// release claimed. These agree in every ordinary case; when they do not, the
  /// bundle is what is about to be installed, so the bundle is what to report.
  final String? version;

  final String? message;

  /// True when the failure is one the user can work around by installing the
  /// DMG by hand — an unwritable install location, mostly. It decides whether
  /// the UI offers a download link or just an apology.
  final bool canRetryManually;

  static const PreparedUpdate failure = PreparedUpdate(
    ok: false,
    message: 'The update could not be prepared.',
  );
}

/// Thin wrapper over `macos/Runner/UpdateChannel.swift`.
///
/// The download happens in Dart, where progress is easy to stream into a bloc.
/// Everything after it happens in Swift, because verifying a code signature and
/// atomically exchanging a running bundle are both things only the platform can
/// do honestly.
class UpdateBridge {
  UpdateBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.yunweneric.tidy/updates',
  );

  /// Unpacks [zipPath], checks it, and stages it next to the installed app.
  ///
  /// [expectedSha256] is the digest GitHub published for the asset, when it
  /// published one. Nothing is installed by this call.
  static Future<PreparedUpdate> prepare({
    required String zipPath,
    String? expectedSha256,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'prepareUpdate',
        {'zipPath': zipPath, 'expectedSha256': expectedSha256},
      );
      if (result == null) return PreparedUpdate.failure;

      return PreparedUpdate(
        ok: result['ok'] as bool? ?? false,
        stagedPath: result['stagedPath'] as String?,
        version: result['version'] as String?,
        message: result['message'] as String?,
        canRetryManually: result['canRetryManually'] as bool? ?? false,
      );
    } catch (e) {
      AppLog.updates.failed('prepare the downloaded update', e);
      return PreparedUpdate.failure;
    }
  }

  /// Swaps the staged bundle into place and relaunches.
  ///
  /// On success this does not return in any meaningful sense: the app is asked
  /// to terminate while a detached helper waits for it to go and reopens the
  /// new copy. A returned message therefore always describes a failure.
  static Future<String?> install(String stagedPath) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'installUpdate',
        {'stagedPath': stagedPath},
      );
      if (result == null) return 'The update could not be installed.';
      if (result['ok'] as bool? ?? false) return null;
      return result['message'] as String? ??
          'The update could not be installed.';
    } catch (e) {
      AppLog.updates.failed('install the update', e);
      return 'The update could not be installed.';
    }
  }

  /// Throws away a staged bundle the user is not going to install.
  static Future<void> discard(String stagedPath) async {
    try {
      await _channel.invokeMethod<void>('discardUpdate', {
        'stagedPath': stagedPath,
      });
    } catch (e) {
      AppLog.updates.failed('discard the staged update', e);
    }
  }
}
