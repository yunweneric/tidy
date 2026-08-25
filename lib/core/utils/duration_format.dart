/// How long until something happens, in the fewest units that stay accurate.
///
/// `6d 1h 4m`, `1h 4m`, `4m`, `now`. Leading units are dropped when they are
/// zero, trailing ones are kept: `2d 0h 5m` reads as a mistake, while `2d 5m`
/// reads as a fact. Seconds are never shown — every caller is counting down a
/// window measured in hours, and a ticking seconds digit in a menu bar popover
/// is movement that means nothing.
String formatCountdown(Duration left) {
  if (left <= Duration.zero) return 'now';

  final days = left.inDays;
  final hours = left.inHours % 24;
  final minutes = left.inMinutes % 60;

  return [
    if (days > 0) '${days}d',
    if (days > 0 || hours > 0) '${hours}h',
    '${minutes}m',
  ].join(' ');
}
