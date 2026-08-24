import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:tidy/core/logging/log_record.dart';

/// Formats a [LogRecord] as one aligned line, plus continuation lines for an
/// error and its stack.
///
/// Not `PrettyPrinter`: this app's logs are overwhelmingly one-line facts from
/// background services — a bridge call that failed, a sample that was written —
/// and `PrettyPrinter` draws a boxed, multi-line frame around each of them.
/// Fifty of those scroll a terminal off the screen and make the shape of a
/// session impossible to see. Fixed columns instead, so the eye can scan the
/// level and the channel straight down the left edge:
///
/// ```
/// 09:41:02.118 I app       started                    engine=main level=debug
/// 09:41:02.402 W store     could not open the store   path="/Users/…/history"
///                          ↳ FileSystemException: Permission denied
/// ```
class TidyLogPrinter extends LogPrinter {
  TidyLogPrinter({required this.engine, bool? colors, this.stackFrames = 8})
    : colors = colors ?? _terminalSupportsAnsi();

  /// Which Flutter engine this line came from — see `main.dart`. Printed only
  /// for engines other than [primaryEngine]: the menu-bar popover is a second
  /// isolate logging into the same console, and without the marker its lines
  /// look like the window's own. Adding a constant `main` column to the other
  /// 95% of lines would be noise, so it is left off there.
  final String engine;

  /// Whether to colour the level and channel columns.
  final bool colors;

  /// How many stack frames to keep. A full Flutter stack is ~60 frames of
  /// framework internals; the top handful is what identifies the call site.
  final int stackFrames;

  /// The engine whose name is implied rather than printed.
  static const String primaryEngine = 'main';

  /// Width of everything left of the message, so continuation lines line up
  /// underneath it: `HH:mm:ss.SSS` + space + level + space + channel + space.
  static const int _channelWidth = 9;
  static final String _indent = ' ' * (12 + 1 + 1 + 1 + _channelWidth + 1);

  static const Map<Level, String> _levelGlyphs = {
    Level.trace: 'T',
    Level.debug: 'D',
    Level.info: 'I',
    Level.warning: 'W',
    Level.error: 'E',
    Level.fatal: 'F',
  };

  static const Map<Level, AnsiColor> _levelColors = {
    Level.trace: AnsiColor.fg(244),
    Level.debug: AnsiColor.fg(39),
    Level.info: AnsiColor.fg(40),
    Level.warning: AnsiColor.fg(214),
    Level.error: AnsiColor.fg(196),
    Level.fatal: AnsiColor.fg(199),
  };

  static const AnsiColor _dim = AnsiColor.fg(244);
  static const AnsiColor _plain = AnsiColor.none();

  @override
  List<String> log(LogEvent event) {
    final record = _asRecord(event.message);

    final head =
        StringBuffer()
          ..write(_paint(_dim, _timestamp(event.time)))
          ..write(' ')
          ..write(
            _paint(_levelColors[event.level] ?? _plain, _glyph(event.level)),
          )
          ..write(' ')
          ..write(_paint(_dim, _pad(record.channel, _channelWidth)))
          ..write(' ');

    if (engine != primaryEngine) head.write(_paint(_dim, '[$engine] '));
    head.write(record.message);

    final fields = record.fields;
    if (fields != null && fields.isNotEmpty) {
      final rendered = LogRecord.formatFields(fields);
      if (rendered.isNotEmpty) head.write('  ${_paint(_dim, rendered)}');
    }

    final lines = <String>[head.toString()];

    final error = event.error;
    if (error != null) {
      for (final line in _describeError(error)) {
        lines.add(
          '$_indent${_paint(_levelColors[event.level] ?? _plain, '↳ ')}$line',
        );
      }
    }

    final stackTrace = event.stackTrace;
    if (stackTrace != null) {
      for (final frame in _frames(stackTrace)) {
        lines.add(_paint(_dim, '$_indent  $frame'));
      }
    }

    return lines;
  }

  /// Anything that is not already a [LogRecord] — a raw string from a stray
  /// `logger.i('…')`, say — still prints, on the `app` channel. Dropping it
  /// would be worse than filing it slightly wrong.
  LogRecord _asRecord(Object? message) {
    if (message is LogRecord) return message;
    return LogRecord(channel: 'app', message: '$message');
  }

  String _glyph(Level level) => _levelGlyphs[level] ?? '?';

  String _paint(AnsiColor color, String text) => colors ? color(text) : text;

  static String _pad(String value, int width) =>
      value.length >= width ? value.substring(0, width) : value.padRight(width);

  static String _timestamp(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final millis = time.millisecond.toString().padLeft(3, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.$millis';
  }

  /// Errors are printed by `toString`, but split on newlines so that a
  /// multi-line `PlatformException` keeps the indent instead of breaking the
  /// column alignment for everything below it.
  static List<String> _describeError(Object error) =>
      error.toString().trimRight().split('\n');

  /// Keeps the top [stackFrames] frames and says how many were dropped, so a
  /// truncated stack can never be mistaken for a shallow one.
  List<String> _frames(StackTrace stackTrace) {
    final all =
        stackTrace
            .toString()
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
    if (all.length <= stackFrames) return all;
    return [
      ...all.take(stackFrames),
      '… ${all.length - stackFrames} more frames',
    ];
  }

  static bool _terminalSupportsAnsi() {
    if (kIsWeb) return false;
    try {
      return stdout.supportsAnsiEscapes;
    } catch (_) {
      return false;
    }
  }
}

/// Logs anything at or above [Logger.level].
///
/// Deliberately not `DevelopmentFilter`, which drops **everything** in a
/// release build. Tidy is a desktop app that does most of its work in
/// background services against the filesystem and a native channel, and when a
/// user reports "it says it cleaned nothing", the release build's warnings in
/// Console.app are the entire diagnosis. What release mode changes here is the
/// *level* — see `resolveLogLevel` — not whether logging happens at all.
class TidyLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => event.level >= (level ?? Logger.level);
}

/// Sends each line through [debugPrint].
///
/// Rather than `print` (what `ConsoleOutput` uses) because `debugPrint`
/// throttles: a scan that fails on a few thousand paths can log faster than the
/// platform console drains, and dropped lines in the middle of a failure are
/// the ones you needed. Throttling delays them instead.
class DebugPrintOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      debugPrint(line);
    }
  }
}
