import 'package:flutter/material.dart';

/// Where a sidebar entry sits.
enum NavGroup {
  /// The six modules that do the work.
  primary,

  /// Supporting views.
  secondary,

  /// Pinned to the bottom, always reachable.
  footer,
}

/// Every top-level view in the app.
///
/// Previously the sidebar navigated by `AppFilter`, which meant the nav model
/// and the applications table's filter were the same enum — fine with one
/// screen, impossible with ten.
enum AppDestination {
  smartCare(
    label: 'Smart Care',
    icon: Icons.auto_awesome_rounded,
    group: NavGroup.primary,
    blurb: 'One pass over everything, then a single review.',
  ),
  cleanup(
    label: 'Cleanup',
    icon: Icons.cleaning_services_rounded,
    group: NavGroup.primary,
    blurb: 'Reclaim space from caches, logs and build artefacts.',
  ),
  protection(
    label: 'Protection',
    icon: Icons.shield_rounded,
    group: NavGroup.primary,
    blurb: 'Check for known adware and unusual background items.',
  ),
  performance(
    label: 'Performance',
    icon: Icons.speed_rounded,
    group: NavGroup.primary,
    blurb: 'Tune startup items and run macOS upkeep.',
  ),
  applications(
    label: 'Applications',
    icon: Icons.grid_view_rounded,
    group: NavGroup.primary,
    blurb: 'Uninstall apps completely, and clean up after old ones.',
  ),
  clutter(
    label: 'My Clutter',
    icon: Icons.folder_copy_rounded,
    group: NavGroup.primary,
    blurb: 'Find duplicates, near-identical photos and forgotten files.',
  ),
  spaceLens(
    label: 'Space Lens',
    icon: Icons.donut_large_rounded,
    group: NavGroup.secondary,
    blurb: 'See what is actually filling your disk.',
  ),
  allTools(
    label: 'All Tools',
    icon: Icons.widgets_rounded,
    group: NavGroup.secondary,
    blurb: 'Every scanner on its own, without the modules.',
  ),
  activity(
    label: 'Activity',
    icon: Icons.history_rounded,
    group: NavGroup.secondary,
    blurb: 'What has been cleaned, and what to look at next.',
  ),
  assistant(
    label: 'Assistant',
    icon: Icons.monitor_heart_rounded,
    group: NavGroup.footer,
    blurb: 'How your Mac is doing, and what would help most.',
  ),
  settings(
    label: 'Settings',
    icon: Icons.settings_rounded,
    group: NavGroup.footer,
    blurb: 'Appearance, scanning and permissions.',
  );

  const AppDestination({
    required this.label,
    required this.icon,
    required this.group,
    required this.blurb,
  });

  final String label;
  final IconData icon;
  final NavGroup group;

  /// The one-line subtitle shown under the page title. Non-technical on
  /// purpose — the modules are for people who do not know what a plist is.
  final String blurb;

  static List<AppDestination> of(NavGroup group) =>
      values.where((d) => d.group == group).toList();

  /// Where the app opens.
  static const AppDestination initial = AppDestination.smartCare;
}
