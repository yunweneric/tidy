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

/// The number and its unit, split so a hero can render them at different sizes
/// ("12.4" large, "GB" small) without re-parsing a formatted string.
({String value, String unit}) splitBytes(int bytes) {
  final formatted = formatBytes(bytes);
  final gap = formatted.lastIndexOf(' ');
  if (gap < 0) return (value: formatted, unit: '');
  return (value: formatted.substring(0, gap), unit: formatted.substring(gap + 1));
}

/// `~/Library/Caches` rather than `/Users/you/Library/Caches`.
String collapseHome(String path, String? home) {
  if (home == null || home.isEmpty) return path;
  if (path == home) return '~';
  if (path.startsWith('$home/')) return '~${path.substring(home.length)}';
  return path;
}
