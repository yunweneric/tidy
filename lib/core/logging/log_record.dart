import 'package:flutter/foundation.dart';

/// One log line, before anything decides how it looks.
///
/// Every log in the app travels as one of these rather than as a formatted
/// string, which is the whole point of the rewrite: the app used to log with
/// `debugPrint('sizeOfPaths failed: $e')`, where the subsystem, the operation,
/// the failure and the context were already melted into prose by the time
/// anything could act on them. Keeping them apart means the printer can align
/// them into columns, and a future file or crash-report sink can serialise them
/// without re-parsing English.
///
/// [fields] is the structured half — the values a reader would otherwise have
/// to fish out of the sentence. Keep them short and machine-ish
/// (`module`, `count`, `ms`, `path`); the sentence in [message] stays free of
/// interpolated values so that identical events group together.
@immutable
class LogRecord {
  const LogRecord({required this.channel, required this.message, this.fields});

  /// Which part of the app spoke. See [AppLog] for the registry.
  final String channel;

  /// What happened, in lower case and without a trailing full stop, phrased so
  /// that two occurrences differ only in their [fields].
  final String message;

  /// Context, as `key=value` pairs. Null and empty mean the same thing.
  final Map<String, Object?>? fields;

  /// Only used when something outside the printer stringifies a record — a
  /// test, or a `LogOutput` that has no formatting of its own.
  @override
  String toString() {
    final buffer = StringBuffer('[$channel] $message');
    final fields = this.fields;
    if (fields != null && fields.isNotEmpty) {
      buffer.write(' ${formatFields(fields)}');
    }
    return buffer.toString();
  }

  /// Renders [fields] as `key=value key="value with spaces"`.
  ///
  /// Shared with the printer so that a record reads the same wherever it lands.
  /// Entries with a null value are dropped rather than printed as `key=null`:
  /// call sites pass optional context straight through, and "we did not have
  /// this" is not worth a column.
  static String formatFields(Map<String, Object?> fields) {
    final parts = <String>[];
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      final text = value is Duration ? '${value.inMilliseconds}ms' : '$value';
      final needsQuotes = text.isEmpty || text.contains(' ');
      parts.add('${entry.key}=${needsQuotes ? '"$text"' : text}');
    }
    return parts.join(' ');
  }
}
