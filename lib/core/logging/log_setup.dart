import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:tidy/core/logging/log_printer.dart';
import 'package:tidy/core/logging/log_record.dart';

/// The one [Logger] behind every [AppLog] channel.
///
/// One instance, not one per channel: the channel is data on the record (see
/// [LogRecord]), so a second `Logger` would only duplicate the printer and the
/// filter, and would make "turn the level down" a loop instead of an
/// assignment.
Logger get rootLogger => _logger ??= _buildLogger(TidyLogPrinter.primaryEngine);
Logger? _logger;

Logger _buildLogger(String engine) => Logger(
  filter: TidyLogFilter(),
  printer: TidyLogPrinter(engine: engine),
  output: DebugPrintOutput(),
);

/// Configures logging for one Flutter engine, and routes the framework's own
/// errors through it.
///
/// Called once per engine rather than once per app, for the same reason
/// `setUpLocator` is: the menu-bar popover runs in a second engine with its own
/// isolate, so it has its own statics and its own uninstalled error handlers.
/// [engine] is what tells the two apart in the output.
///
/// This must run before anything else in `main`, so that a failure during
/// startup — which is exactly when the store and the settings file fail —
/// is logged rather than swallowed by a logger that does not exist yet.
void setUpLogging({
  String engine = TidyLogPrinter.primaryEngine,
  Level? level,
}) {
  Logger.level = level ?? resolveLogLevel();
  _logger = _buildLogger(engine);

  // Framework errors: the red screen and the console dump. Routed here so a
  // build failure lands in the same stream, with the same timestamps, as the
  // service call that caused it — and so release builds report it at all,
  // where the default handler stays quiet.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    rootLogger.e(
      LogRecord(
        channel: AppLogChannels.flutter,
        message: 'uncaught framework error',
        fields: {
          'context': details.context?.toDescription(),
          'library': details.library,
        },
      ),
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  // Everything the framework does not catch — a failed future in a service, a
  // channel reply that throws after its caller has gone. Returning true says
  // "handled", which stops the platform from printing its own untagged copy.
  PlatformDispatcher.instance.onError = (error, stack) {
    rootLogger.f(
      const LogRecord(
        channel: AppLogChannels.app,
        message: 'uncaught error outside the framework',
      ),
      error: error,
      stackTrace: stack,
    );
    return true;
  };
}

/// Raises or lowers the floor at runtime, for every channel at once.
///
/// Exists so a "verbose logging" switch has something to call; nothing in the
/// UI calls it yet.
void setLogLevel(Level level) => Logger.level = level;

/// The level to log at when nothing overrides it.
///
/// Three ways to be wrong, in order of preference:
///
/// 1. `--dart-define=TIDY_LOG_LEVEL=trace` wins, in every build mode. This is
///    the one that matters for a shipped app: reproducing a user's bug usually
///    means turning the noise up on a release binary, and rebuilding in debug
///    changes the timings that caused it.
/// 2. Debug builds log at `debug` — the level where a scan narrates itself but
///    per-file work stays quiet. `trace` is for when you have asked for it.
/// 3. Release and profile builds log at `warning`: the things that went wrong
///    and were survived. That is precisely the set the app used to `debugPrint`,
///    so a release build says no less than it did before, in a form that can be
///    read.
Level resolveLogLevel() {
  const override = String.fromEnvironment('TIDY_LOG_LEVEL');
  if (override.isNotEmpty) {
    for (final level in Level.values) {
      if (level.name == override.toLowerCase()) return level;
    }
  }
  return kDebugMode ? Level.debug : Level.warning;
}

/// Channel names, kept here so [setUpLogging] can use them without importing
/// `AppLog` and creating a cycle. `AppLog`'s constants are the public face.
abstract final class AppLogChannels {
  static const String app = 'app';
  static const String flutter = 'flutter';
}
