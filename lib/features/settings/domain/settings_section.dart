import 'package:flutter/widgets.dart';
import 'package:tidy/core/design/design.dart';

/// The tabs down the left of the Settings page.
///
/// Settings is the one page whose contents are unrelated to each other —
/// appearance, a recorder that writes a file of everything you copy, a system
/// permission, and a paragraph about the app. Stacked in one column they read
/// as a single long list to scroll past; split into named tabs, each one is a
/// question you either have or do not have.
///
/// Declaration order is display order.
enum SettingsSection {
  general(
    label: 'General',
    icon: AppIcons.settings,
    blurb: 'What ${Brand.name} does when your Mac starts, and when it opens.',
  ),
  appearance(
    label: 'Appearance',
    icon: AppIcons.light,
    blurb: 'Light or dark, and how much of the app moves while it works.',
  ),
  clipboard(
    label: 'Clipboard',
    icon: AppIcons.clipboard,
    blurb: 'What the clipboard history records, and how long it keeps it.',
  ),
  network(
    label: 'Network',
    icon: AppIcons.network,
    blurb: 'The menu bar readout, and what the usage history keeps.',
  ),
  permissions(
    label: 'Permissions',
    icon: AppIcons.locked,
    blurb: 'What macOS lets ${Brand.name} see, and how to widen it.',
  ),
  about(
    label: 'About',
    icon: AppIcons.info,
    blurb: 'What ${Brand.name} is, and what it does with your data.',
  );

  const SettingsSection({
    required this.label,
    required this.icon,
    required this.blurb,
  });

  final String label;
  final IconData icon;

  /// One line under the section's heading in the detail pane.
  final String blurb;

  static const SettingsSection initial = SettingsSection.general;
}
