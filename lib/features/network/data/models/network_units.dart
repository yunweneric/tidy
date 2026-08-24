/// How a rate is written down.
///
/// Bytes by default: everything else in Tidy — a cache, a download, a Trash
/// total — is measured in bytes, and a readout that says 36 Mbps beside a page
/// that says 4.5 MB is asking the user to convert in their head. Bits are here
/// because that is what an ISP sells and what a speed test reports, so someone
/// checking whether they are getting the line they pay for needs them.
enum NetworkUnits {
  bytes('Bytes per second', 'MB/s'),
  bits('Bits per second', 'Mbps');

  const NetworkUnits(this.label, this.example);

  final String label;
  final String example;

  bool get isBits => this == NetworkUnits.bits;
}

/// A transfer rate, at three significant digits.
///
/// **Must stay in step with `NetworkMonitor.formatRate` in
/// `macos/Runner/NetworkMonitor.swift`.** The menu bar and the panel are two
/// different renderers reading the same sample, and showing different numbers
/// for the same instant is the bug this would otherwise ship with.
///
/// Three significant digits rather than a fixed decimal count so the field stays
/// the same width whether the number is 4.47 or 447 — which is what stops the
/// menu bar item shuffling its neighbours every second.
String formatRate(
  double bytesPerSecond, {
  NetworkUnits units = NetworkUnits.bytes,
}) {
  if (units.isBits) {
    // Decimal, not binary. A megabit has always been a million bits, and
    // rendering 1024-based "Mbps" would disagree with every speed test.
    return _format(
      bytesPerSecond * 8,
      base: 1000,
      units: const ['bps', 'Kbps', 'Mbps', 'Gbps'],
    );
  }
  return _format(
    bytesPerSecond,
    base: 1024,
    units: const ['B/s', 'KB/s', 'MB/s', 'GB/s'],
  );
}

String _format(
  double value, {
  required double base,
  required List<String> units,
}) {
  var amount = value < 0 ? 0.0 : value;
  var index = 0;
  while (amount >= base && index < units.length - 1) {
    amount /= base;
    index += 1;
  }

  // Bytes per second is never worth a decimal place; above that, keep three
  // significant digits.
  final int decimals;
  if (index == 0) {
    decimals = 0;
  } else if (amount < 10) {
    decimals = 2;
  } else if (amount < 100) {
    decimals = 1;
  } else {
    decimals = 0;
  }

  return '${amount.toStringAsFixed(decimals)} ${units[index]}';
}
