import 'dart:io';

/// The user's home directory, read once.
///
/// `Platform.environment` rebuilds its map on every access, and this is read
/// per row in lists that redraw on hover. Null only in the odd environment
/// where `HOME` is unset, which `collapseHome` already handles.
final String? kHomeDir = Platform.environment['HOME'];
