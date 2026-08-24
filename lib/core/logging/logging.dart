/// Structured logging for Tidy.
///
/// Import this and use [AppLog]; the rest is here for `main.dart` and for
/// anything that wants to add an output.
library;

// The parts of `logger` that leak into this app's own API: [Level] for
// `setUpLogging`, [Logger] for `Logger.level`, and the event and handler types
// for anyone adding a second [LogOutput]. The rest of the package stays behind
// [AppLog].
export 'package:logger/logger.dart'
    show Level, LogEvent, LogFilter, LogOutput, LogPrinter, Logger, OutputEvent;

export 'app_log.dart';
export 'log_printer.dart';
export 'log_record.dart';
export 'log_setup.dart';
