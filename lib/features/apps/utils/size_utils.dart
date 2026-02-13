import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';

/// Formats total size of a list of apps by parsing each app's size string.
String formatAppsTotalSize(List<MacApp> apps) {
  double totalBytes = 0;
  for (final app in apps) {
    final s = app.size.replaceAll(RegExp(r'[^0-9.]'), '');
    final num? n = double.tryParse(s);
    if (n != null) {
      if (app.size.toUpperCase().contains('G')) {
        totalBytes += n * 1024 * 1024 * 1024;
      } else if (app.size.toUpperCase().contains('M')) {
        totalBytes += n * 1024 * 1024;
      } else if (app.size.toUpperCase().contains('K')) {
        totalBytes += n * 1024;
      } else {
        totalBytes += n;
      }
    }
  }
  if (totalBytes >= 1024 * 1024 * 1024) {
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (totalBytes >= 1024 * 1024) {
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
}
