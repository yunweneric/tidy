import 'dart:io';

/// Where a leftover lives, used to group the preview list.
enum LeftoverCategory {
  appBundle('Application'),
  applicationSupport('Application Support'),
  caches('Caches'),
  preferences('Preferences'),
  logs('Logs'),
  containers('Containers'),
  savedState('Saved State'),
  launchAgents('Launch Agents & Daemons'),
  other('Other');

  const LeftoverCategory(this.label);

  final String label;
}

/// A single path that would be removed when uninstalling an app.
class LeftoverItem {
  const LeftoverItem({
    required this.path,
    required this.sizeBytes,
    required this.category,
    this.requiresAdmin = false,
  });

  final String path;
  final int sizeBytes;
  final LeftoverCategory category;

  /// Lives under `/Library`, so removal needs admin rights and will usually
  /// fail unless the app has been granted them.
  final bool requiresAdmin;

  /// Last path component, which is what the preview list shows.
  String get displayName => path.split('/').last;

  /// Parent directory, shown as the secondary line in the preview.
  String get location {
    final parts = path.split('/');
    if (parts.length <= 1) return path;
    final parent = parts.sublist(0, parts.length - 1).join('/');
    final home = Platform.environment['HOME'];
    if (home != null && parent.startsWith(home)) {
      return '~${parent.substring(home.length)}';
    }
    return parent;
  }
}
