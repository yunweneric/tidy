import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/features/apps/data/models/mac_app_model.dart';

export 'package:tidy/core/utils/byte_format.dart' show formatBytes;

/// Total bytes occupied by [apps].
int totalBytes(Iterable<MacApp> apps) =>
    apps.fold<int>(0, (sum, app) => sum + app.sizeBytes);

/// Formatted total size of [apps].
String formatAppsTotalSize(Iterable<MacApp> apps) =>
    formatBytes(totalBytes(apps));
