import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/parsing/claude_code_parser.dart';
import 'package:tidy/features/ai_usage/data/parsing/codex_parser.dart';
import 'package:tidy/features/ai_usage/data/parsing/file_usage.dart';

/// How far through a sweep we are.
///
/// `docs/feature.md` §3.2 makes the case for emitting these as you go rather
/// than awaiting the whole thing: a window left on a spinner for half a minute
/// reads as a hang. That argument is about scans, but the reason is about
/// waiting, and a cold sweep here reads 1.5 GB.
class UsageScanProgress {
  const UsageScanProgress({
    required this.filesDone,
    required this.filesTotal,
    this.currentLabel,
  });

  final int filesDone;
  final int filesTotal;

  /// The provider being read, for the rolling status line.
  final String? currentLabel;

  double get fraction => filesTotal == 0 ? 0 : filesDone / filesTotal;
}

/// What a sweep produced, plus the state the next sweep needs.
class UsageScanResult {
  const UsageScanResult({
    required this.files,
    this.missingRoots = const [],
    this.unreadablePaths = const [],
    this.unreadableFiles = 0,
    this.filesScanned = 0,
    this.filesParsed = 0,
  });

  /// Path → that file's rollup. This *is* the cache; the service writes it
  /// straight out.
  final Map<String, FileUsage> files;

  /// Provider roots that are not on this Mac. "Codex: not installed" and
  /// "Codex: nothing used" are different facts and the page says which.
  final List<String> missingRoots;

  /// The first few paths that could not be read.
  ///
  /// The sweep runs in a spawned isolate, which has no `AppLog` output of its
  /// own, so a swallowed exception cannot be logged where it happens. Carrying
  /// the paths back is how `docs/feature.md` §4b's rule is kept: the caller
  /// logs them on the main isolate, and the count reaches the page as well.
  /// Capped, because a permission problem tends to hit every file at once and
  /// a thousand-line log entry helps nobody.
  final List<String> unreadablePaths;

  final int unreadableFiles;
  final int filesScanned;

  /// How many had to be read rather than taken from the cache. Only useful for
  /// the log line that says whether the cache is doing its job.
  final int filesParsed;
}

/// Runs a sweep on a background isolate.
///
/// The first isolate in this app, and unavoidable: a cold sweep decodes JSON
/// out of 1.5 GB of logs, which on the UI isolate would freeze the window for
/// the whole of it.
Future<UsageScanResult> runUsageScan({
  required Map<AiProvider, String> roots,
  required Map<String, FileUsage> cached,
  void Function(UsageScanProgress progress)? onProgress,
}) async {
  final port = ReceivePort();
  final request = <String, dynamic>{
    'send': port.sendPort,
    'roots': {for (final entry in roots.entries) entry.key.name: entry.value},
    'cache': {
      for (final entry in cached.entries) entry.key: entry.value.toJson(),
    },
  };

  final done = Completer<UsageScanResult>();
  Isolate? isolate;

  port.listen((message) {
    if (message is! Map) return;
    switch (message['kind']) {
      case 'progress':
        onProgress?.call(
          UsageScanProgress(
            filesDone: message['done'] as int,
            filesTotal: message['total'] as int,
            currentLabel: message['label'] as String?,
          ),
        );
      case 'result':
        if (!done.isCompleted) done.complete(_decodeResult(message));
        port.close();
      case 'error':
        if (!done.isCompleted) {
          done.completeError(StateError('${message['message']}'));
        }
        port.close();
    }
  });

  try {
    isolate = await Isolate.spawn(usageScanEntryPoint, request);
    return await done.future;
  } finally {
    port.close();
    isolate?.kill(priority: Isolate.beforeNextEvent);
  }
}

/// The isolate body. Public only so [Isolate.spawn] can name it.
Future<void> usageScanEntryPoint(Map<String, dynamic> request) async {
  final send = request['send'] as SendPort;
  try {
    final roots = <AiProvider, String>{
      for (final entry in (request['roots'] as Map).entries)
        if (AiProvider.tryParse('${entry.key}') case final provider?)
          provider: '${entry.value}',
    };
    final cached = <String, FileUsage>{
      for (final entry in (request['cache'] as Map).entries)
        if (FileUsage.fromJson('${entry.key}', entry.value) case final file?)
          '${entry.key}': file,
    };

    final result = await sweep(
      roots: roots,
      cached: cached,
      onProgress:
          (done, total, label) => send.send({
            'kind': 'progress',
            'done': done,
            'total': total,
            'label': label,
          }),
    );

    send.send({
      'kind': 'result',
      'files': {
        for (final entry in result.files.entries)
          entry.key: entry.value.toJson(),
      },
      'missingRoots': result.missingRoots,
      'unreadablePaths': result.unreadablePaths,
      'unreadableFiles': result.unreadableFiles,
      'filesScanned': result.filesScanned,
      'filesParsed': result.filesParsed,
    });
  } catch (error) {
    send.send({'kind': 'error', 'message': '$error'});
  }
}

/// The sweep itself, with no isolate around it so it can be driven directly
/// from a test or a one-off script.
Future<UsageScanResult> sweep({
  required Map<AiProvider, String> roots,
  required Map<String, FileUsage> cached,
  void Function(int done, int total, String? label)? onProgress,
}) async {
  final discovered = <AiProvider, List<File>>{};
  final missingRoots = <String>[];
  final deniedRoots = <String>[];

  for (final entry in roots.entries) {
    final directory = Directory(_logsDirectory(entry.key, entry.value));
    if (!directory.existsSync()) {
      missingRoots.add(entry.key.label);
      continue;
    }
    final walk = _jsonlFilesUnder(directory);
    discovered[entry.key] = walk.files;
    if (!walk.complete) deniedRoots.add(directory.path);
  }

  final total = discovered.values.fold(0, (sum, list) => sum + list.length);
  final files = <String, FileUsage>{};
  final unreadablePaths = <String>[];
  var done = 0;
  var parsed = 0;
  var unreadable = 0;

  for (final entry in discovered.entries) {
    for (final file in entry.value) {
      final path = file.path;
      FileStat stat;
      try {
        stat = file.statSync();
      } on FileSystemException {
        unreadable++;
        if (unreadablePaths.length < _maxReportedPaths) {
          unreadablePaths.add(path);
        }
        done++;
        continue;
      }

      final modifiedMs = stat.modified.millisecondsSinceEpoch;
      final size = stat.size;

      final hit = cached[path];
      if (hit != null && hit.matches(modifiedMs: modifiedMs, size: size)) {
        files[path] = hit;
      } else {
        final fresh = await _parseFile(
          file: file,
          provider: entry.key,
          modifiedMs: modifiedMs,
          size: size,
        );
        if (fresh == null) {
          unreadable++;
          if (unreadablePaths.length < _maxReportedPaths) {
            unreadablePaths.add(path);
          }
        } else {
          files[path] = fresh;
          parsed++;
        }
      }

      done++;
      if (done % 8 == 0 || done == total) {
        onProgress?.call(done, total, entry.key.label);
      }
    }
  }

  return UsageScanResult(
    files: files,
    missingRoots: missingRoots,
    unreadablePaths: [...deniedRoots, ...unreadablePaths],
    unreadableFiles: unreadable + deniedRoots.length,
    filesScanned: total,
    filesParsed: parsed,
  );
}

/// How many failing paths are carried back for the log line.
const int _maxReportedPaths = 12;

/// Where each CLI keeps its logs, relative to its config root.
String _logsDirectory(AiProvider provider, String root) => switch (provider) {
  // `projects/<mangled-cwd>/<session>.jsonl`.
  AiProvider.claudeCode => '$root/projects',
  // `sessions/YYYY/MM/DD/rollout-<time>-<session>.jsonl`. Pointed at `sessions`
  // rather than the root on purpose: `archived_sessions` sits alongside it and
  // holds copies, so walking the root would count everything in it twice.
  AiProvider.codex => '$root/sessions',
};

/// Every `.jsonl` beneath [directory], and whether the walk finished.
///
/// A denied directory is not an empty one. `listSync` gives up at the first
/// refusal, so the flag is the only way the caller can tell a genuinely empty
/// tree from one it was not allowed to finish reading — and the page has to say
/// which, rather than reporting a confident total that is short.
({List<File> files, bool complete}) _jsonlFilesUnder(Directory directory) {
  final files = <File>[];
  try {
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.jsonl')) files.add(entity);
    }
  } on FileSystemException {
    return (files: files, complete: false);
  }
  return (files: files, complete: true);
}

Future<FileUsage?> _parseFile({
  required File file,
  required AiProvider provider,
  required int modifiedMs,
  required int size,
}) async {
  final sessionId = _sessionIdFrom(file.path);
  final rollup = FileUsage(
    path: file.path,
    modifiedMs: modifiedMs,
    size: size,
    provider: provider,
    sessionId: sessionId,
  );

  // Dedup is per file, and that is not a shortcut: measured over a real
  // `~/.claude/projects`, 43% of usage rows repeat an earlier row in the same
  // file and *no* row's key appears in two different files.
  final dedup = <String>{};
  final codex =
      provider == AiProvider.codex ? CodexParser(sessionId: sessionId) : null;

  try {
    final lines = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.isEmpty) continue;
      final entry = switch (provider) {
        AiProvider.claudeCode => ClaudeCodeParser.parseLine(line, dedup: dedup),
        AiProvider.codex => codex!.parseLine(line),
      };
      if (entry != null) rollup.add(entry);
    }
  } on FileSystemException {
    return null;
  } on FormatException {
    // Not valid UTF-8 anywhere in the file. Nothing to salvage, and treating it
    // as empty would quietly undercount.
    return null;
  }

  return codex?.rateLimit != null
      ? rollup.withRateLimit(codex!.rateLimit)
      : rollup;
}

/// The session id a log's filename carries.
///
/// Claude Code names the file after the session; Codex prefixes a timestamp
/// (`rollout-2026-08-17T20-29-37-<uuid>.jsonl`). Either way the tail is stable
/// and unique, which is all the per-day session count needs.
String _sessionIdFrom(String path) {
  final slash = path.lastIndexOf('/');
  var name = slash < 0 ? path : path.substring(slash + 1);
  if (name.endsWith('.jsonl')) {
    name = name.substring(0, name.length - '.jsonl'.length);
  }
  return name;
}

UsageScanResult _decodeResult(Map<dynamic, dynamic> message) => UsageScanResult(
  files: {
    for (final entry in (message['files'] as Map).entries)
      if (FileUsage.fromJson('${entry.key}', entry.value) case final file?)
        '${entry.key}': file,
  },
  missingRoots: [for (final root in message['missingRoots'] as List) '$root'],
  unreadablePaths: [
    for (final path in message['unreadablePaths'] as List? ?? const []) '$path',
  ],
  unreadableFiles: message['unreadableFiles'] as int? ?? 0,
  filesScanned: message['filesScanned'] as int? ?? 0,
  filesParsed: message['filesParsed'] as int? ?? 0,
);
