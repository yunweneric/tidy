import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tidy/core/design/brand.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/features/ai_usage/data/parsing/file_usage.dart';

/// The per-file rollups, kept beside `settings.json`.
///
/// Not in `TidyStore`. That store's boxes are the record of what Tidy has
/// *done* — every row in it is an operation or a metric Tidy sampled, and it is
/// what makes a deletion auditable after the fact. This is a derived read cache
/// over somebody else's files: throwing it away costs a re-scan and nothing
/// else, which is the opposite of what belongs in an audit trail.
class AiUsageCache {
  AiUsageCache({File? file}) : _override = file;

  static const int _version = 1;

  final File? _override;
  File? _file;

  Future<File?> _resolve() async {
    if (_override != null) return _override;
    if (_file != null) return _file;

    final home = Platform.environment['HOME'];
    if (home == null) return null;

    final dir = Directory(
      p.join(
        home,
        'Library',
        'Application Support',
        Brand.supportDirectoryName,
      ),
    );
    try {
      if (!dir.existsSync()) await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      AppLog.aiUsage.failed(
        'create the support directory',
        e,
        fields: {'path': dir.path},
      );
      return null;
    }
    return _file = File(p.join(dir.path, 'ai_usage_cache.json'));
  }

  /// Everything the last sweep learned, or empty when there is nothing usable.
  ///
  /// Never throws. A cache that cannot be read is a slow first paint, not a
  /// broken page, so every failure here degrades to "scan it all again".
  Future<Map<String, FileUsage>> read() async {
    final file = await _resolve();
    if (file == null || !file.existsSync()) return {};

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      if (decoded['version'] != _version) return {};

      final files = decoded['files'];
      if (files is! Map) return {};

      return {
        for (final entry in files.entries)
          if (FileUsage.fromJson('${entry.key}', entry.value) case final f?)
            '${entry.key}': f,
      };
    } catch (e) {
      AppLog.aiUsage.failed(
        'read the usage cache',
        e,
        fields: {'path': file.path},
      );
      return {};
    }
  }

  Future<void> write(Map<String, FileUsage> files) async {
    final file = await _resolve();
    if (file == null) return;

    try {
      await file.writeAsString(
        jsonEncode({
          'version': _version,
          'files': {
            for (final entry in files.entries) entry.key: entry.value.toJson(),
          },
        }),
      );
    } catch (e) {
      AppLog.aiUsage.failed(
        'write the usage cache',
        e,
        fields: {'path': file.path},
      );
    }
  }

  Future<void> clear() async {
    final file = await _resolve();
    if (file == null || !file.existsSync()) return;
    try {
      await file.delete();
    } on FileSystemException catch (e) {
      AppLog.aiUsage.failed(
        'delete the usage cache',
        e,
        fields: {'path': file.path},
      );
    }
  }
}
