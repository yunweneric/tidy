import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';

const int _kb = 1024;
const int _mb = _kb * 1024;
const int _gb = _mb * 1024;
const int _tb = _gb * 1024;

/// Formats a byte count using binary units, e.g. `1.4 GB`.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes >= _tb) return '${(bytes / _tb).toStringAsFixed(2)} TB';
  if (bytes >= _gb) return '${(bytes / _gb).toStringAsFixed(1)} GB';
  if (bytes >= _mb) return '${(bytes / _mb).toStringAsFixed(1)} MB';
  if (bytes >= _kb) return '${(bytes / _kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// Total bytes occupied by [apps].
int totalBytes(Iterable<MacApp> apps) =>
    apps.fold<int>(0, (sum, app) => sum + app.sizeBytes);

/// Formatted total size of [apps].
String formatAppsTotalSize(Iterable<MacApp> apps) => formatBytes(totalBytes(apps));
