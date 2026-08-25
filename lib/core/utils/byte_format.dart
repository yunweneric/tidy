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
  return (
    value: formatted.substring(0, gap),
    unit: formatted.substring(gap + 1),
  );
}

/// `~/Library/Caches` rather than `/Users/you/Library/Caches`.
String collapseHome(String path, String? home) {
  if (home == null || home.isEmpty) return path;
  if (path == home) return '~';
  if (path.startsWith('$home/')) return '~${path.substring(home.length)}';
  return path;
}

const int _thousand = 1000;
const int _million = _thousand * 1000;
const int _billion = _million * 1000;

/// Formats a plain count using decimal units, e.g. `1.2M`.
///
/// Separate from [formatBytes] because these are not bytes. Token counts run to
/// billions and would come out of the binary formatter as `1.1 GiB`, which
/// invites the reader to think they are looking at a file size.
String formatCount(int count) {
  if (count <= 0) return '0';
  if (count >= _billion) return '${(count / _billion).toStringAsFixed(2)}B';
  if (count >= _million) return '${(count / _million).toStringAsFixed(1)}M';
  if (count >= _thousand) return '${(count / _thousand).toStringAsFixed(1)}K';
  return '$count';
}

/// The number and its unit, split so a hero can render them at different sizes.
({String value, String unit}) splitCount(int count) {
  final formatted = formatCount(count);
  final last = formatted.substring(formatted.length - 1);
  if (last == 'K' || last == 'M' || last == 'B') {
    return (value: formatted.substring(0, formatted.length - 1), unit: last);
  }
  return (value: formatted, unit: '');
}

/// A US dollar amount with thousands separators, e.g. `$1,204.30`.
///
/// Two decimal places above a dollar and four below it: a day can genuinely
/// cost eight cents, and `$0.08` rounded to `$0.08` is fine while a single
/// cache read rounded to `$0.00` reads as free when it was not.
String formatUsd(double amount) {
  if (amount <= 0) return r'$0.00';
  final decimals = amount < 1 ? 4 : 2;
  final text = amount.toStringAsFixed(decimals);
  final dot = text.indexOf('.');
  final whole = text.substring(0, dot);
  final fraction = text.substring(dot);

  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '\$$grouped$fraction';
}
