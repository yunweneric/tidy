import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:tidy/core/logging/log_record.dart';
import 'package:tidy/core/logging/log_setup.dart';

/// The app's log, split into named channels.
///
/// Every log statement in Tidy goes through one of the constants below:
///
/// ```dart
/// AppLog.store.failed('open the history store', e);
/// AppLog.scan.info('scan finished', fields: {'module': id.name, 'found': 412});
/// ```
///
/// **Why channels rather than one flat stream.** The app is a dozen background
/// services running at once — samplers on a timer, a scanner walking the disk,
/// two native channels, a second Flutter engine — and their output interleaves.
/// A channel is the column that makes `grep store` or "why is Performance
/// quiet?" a question with an answer. It is also the unit a future per-area
/// verbosity switch would toggle.
///
/// **Choosing a level.** The distinction the old `debugPrint` calls could not
/// make, and the one that matters here, is between *degraded* and *broken*:
///
/// - [trace] — per-item work inside a loop. Off by default even in debug.
/// - [debug] — the narration of one operation: a scan started, a cache hit.
/// - [info] — facts a user could feel: a scan's totals, files removed, the app
///   starting. Rare. Every one of these should be worth reading in a release
///   build's log.
/// - [warn] — something failed and the app carried on with a fallback. This is
///   the app's most common log by far, and [failed] is its shorthand: a bridge
///   call that returned empty, a sample that was not written. The user still
///   has a working app; a number on screen may be missing or stale.
/// - [error] — something failed and the feature did not recover.
/// - [fatal] — the app cannot continue, or an error escaped every handler.
@immutable
class AppLog {
  /// Prefer the constants below. This is public so a feature can name a channel
  /// of its own without editing `core/`, but a channel that two files use
  /// belongs here where it can be seen.
  const AppLog(this.channel);

  /// The name printed in the channel column. Nine characters or fewer, or the
  /// printer truncates it.
  final String channel;

  // ─── Core ─────────────────────────────────────────────────────────────────

  /// Lifecycle: startup, shutdown, engine wiring.
  static const AppLog app = AppLog(AppLogChannels.app);

  /// The framework's own errors. Written by `setUpLogging`, not by hand.
  static const AppLog flutter = AppLog(AppLogChannels.flutter);

  /// `TidyStore` — the Hive history database.
  static const AppLog store = AppLog('store');

  /// `AppSettings` — reading and writing `settings.json`.
  static const AppLog settings = AppLog('settings');

  /// `SystemBridge`, `TrashLedger`, Full Disk Access — the macOS boundary.
  static const AppLog platform = AppLog('platform');

  /// `MetricSampler` — the periodic disk and vitals samples.
  static const AppLog metrics = AppLog('metrics');

  /// `DashboardRepository` — the fan-out that assembles the first screen.
  static const AppLog dashboard = AppLog('dashboard');

  /// `ScanBloc` and the scan pipeline in `core/scanning`.
  static const AppLog scan = AppLog('scan');

  // ─── Features ─────────────────────────────────────────────────────────────

  /// Installed-app inventory: `AppManagerService`, `ScanCache`, the scanners.
  static const AppLog apps = AppLog('apps');

  /// The junk cleanup module.
  static const AppLog cleanup = AppLog('cleanup');

  /// Login items, maintenance tasks, process and vitals sampling.
  static const AppLog performance = AppLog('perf');

  /// The native network sampler and its history.
  static const AppLog network = AppLog('network');

  /// The native clipboard recorder.
  static const AppLog clipboard = AppLog('clipboard');

  /// Trash listing and "Put Back".
  static const AppLog recycleBin = AppLog('recycle');

  /// The update check, download and the native installer.
  static const AppLog updates = AppLog('updates');

  /// The menu-bar popover and its second engine.
  static const AppLog menuBar = AppLog('menubar');

  /// Reading the AI CLIs' session logs, and the isolate that does it.
  static const AppLog aiUsage = AppLog('ai');

  // ─── Writing ──────────────────────────────────────────────────────────────

  /// Per-item detail inside a loop. Off unless the level is turned down.
  void trace(String message, {Map<String, Object?>? fields}) =>
      _log(Level.trace, message, fields: fields);

  /// The narration of one operation.
  void debug(String message, {Map<String, Object?>? fields}) =>
      _log(Level.debug, message, fields: fields);

  /// A fact worth having in a release build's log.
  void info(String message, {Map<String, Object?>? fields}) =>
      _log(Level.info, message, fields: fields);

  /// Degraded, but survived. See [failed] for the common shape of this.
  void warn(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => _log(
    Level.warning,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// Broken: the feature did not recover.
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => _log(
    Level.error,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// Unrecoverable, or an error that escaped every handler.
  void fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => _log(
    Level.fatal,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// The house shape: an operation threw, and the caller returned a fallback.
  ///
  /// Almost every log in this app is this one event — a native channel call, a
  /// Hive write or a directory read that failed while the caller carried on
  /// with an empty list. Giving it a method rather than leaving each site to
  /// phrase it means the operation stays a stable string (`'read the trash
  /// ledger'`, never `'read the trash ledger for /Users/…'`), so the same
  /// failure reads the same way everywhere and the varying part lands in
  /// [fields] where it can be searched.
  ///
  /// Name the operation as a bare verb phrase: `failed('open the store', e)`
  /// prints `could not open the store`.
  void failed(
    String operation,
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => _log(
    Level.warning,
    'could not $operation',
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  void _log(
    Level level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => rootLogger.log(
    level,
    LogRecord(channel: channel, message: message, fields: fields),
    error: error,
    stackTrace: stackTrace,
  );
}
