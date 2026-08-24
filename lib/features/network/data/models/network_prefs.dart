import 'package:equatable/equatable.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/features/network/data/models/network_units.dart';

/// How the menu bar readout draws itself.
///
/// Raw names cross the channel and land in the Swift `NetworkMenuBarStyle`, so
/// they must stay in step with it.
enum NetworkMenuBarStyle {
  twoLine(
    'Two lines',
    'Download above upload, the way a network monitor usually reads.',
  ),
  sparkline(
    'Graph and rates',
    'A small live graph of the last minute beside the numbers.',
  ),
  compact('Compact', 'One line. The least menu bar space.');

  const NetworkMenuBarStyle(this.label, this.blurb);

  final String label;
  final String blurb;

  static NetworkMenuBarStyle fromName(String? name) =>
      values.firstWhere((style) => style.name == name, orElse: () => twoLine);
}

/// The network settings, as one value the service can diff.
///
/// Mirrors `ClipboardPrefs`: the point of bundling them is that
/// [NetworkService] can tell a real change from a rebuild and only cross the
/// channel when something actually moved.
class NetworkPrefs extends Equatable {
  const NetworkPrefs({
    this.menuBarEnabled = false,
    this.menuBarStyle = NetworkMenuBarStyle.twoLine,
    this.units = NetworkUnits.bytes,
  });

  factory NetworkPrefs.from(AppSettings settings) => NetworkPrefs(
    menuBarEnabled: settings.networkMenuBarEnabled,
    menuBarStyle: settings.networkMenuBarStyle,
    units: settings.networkUnits,
  );

  final bool menuBarEnabled;
  final NetworkMenuBarStyle menuBarStyle;
  final NetworkUnits units;

  /// Keys match `AppSettings` exactly — the native store reads the same file at
  /// launch, before any engine has run.
  Map<String, dynamic> toMap() => {
    'networkMenuBarEnabled': menuBarEnabled,
    'networkMenuBarStyle': menuBarStyle.name,
    'networkUseBits': units.isBits,
  };

  @override
  List<Object?> get props => [menuBarEnabled, menuBarStyle, units];
}
