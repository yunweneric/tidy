import 'package:mac_uninstaller/core/design/app_icons.dart';
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
    path: '/smart-care',
    label: 'Smart Care',
    icon: AppIcons.smartCare,
    group: NavGroup.primary,
    blurb: 'One pass over everything, then a single review.',
  ),
  cleanup(
    path: '/cleanup',
    label: 'Cleanup',
    icon: AppIcons.cleanup,
    group: NavGroup.primary,
    blurb: 'Reclaim space from caches, logs and build artefacts.',
  ),
  protection(
    path: '/protection',
    label: 'Protection',
    icon: AppIcons.protection,
    group: NavGroup.primary,
    blurb: 'Check for known adware and unusual background items.',
  ),
  performance(
    path: '/performance',
    label: 'Performance',
    icon: AppIcons.performance,
    group: NavGroup.primary,
    blurb: 'Tune startup items and run macOS upkeep.',
  ),
  applications(
    path: '/applications',
    label: 'Applications',
    icon: AppIcons.applications,
    group: NavGroup.primary,
    blurb: 'Uninstall apps completely, and clean up after old ones.',
  ),
  clutter(
    path: '/clutter',
    label: 'My Clutter',
    icon: AppIcons.clutter,
    group: NavGroup.primary,
    blurb: 'Find duplicates, near-identical photos and forgotten files.',
  ),
  spaceLens(
    path: '/space-lens',
    label: 'Space Lens',
    icon: AppIcons.spaceLens,
    group: NavGroup.secondary,
    blurb: 'See what is actually filling your disk.',
  ),
  allTools(
    path: '/all-tools',
    label: 'All Tools',
    icon: AppIcons.allTools,
    group: NavGroup.secondary,
    blurb: 'Every scanner on its own, without the modules.',
  ),
  activity(
    path: '/activity',
    label: 'Activity',
    icon: AppIcons.activity,
    group: NavGroup.secondary,
    blurb: 'What has been cleaned, and what to look at next.',
  ),
  assistant(
    path: '/assistant',
    label: 'Assistant',
    icon: AppIcons.assistant,
    group: NavGroup.footer,
    blurb: 'How your Mac is doing, and what would help most.',
  ),
  settings(
    path: '/settings',
    label: 'Settings',
    icon: AppIcons.settings,
    group: NavGroup.footer,
    blurb: 'Appearance, scanning and permissions.',
  );

  const AppDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.group,
    required this.blurb,
  });

  /// The route this destination lives at. Each one is a branch of the shell
  /// route, so its state survives navigating elsewhere and back.
  final String path;

  final String label;
  final IconData icon;
  final NavGroup group;

  /// The one-line subtitle shown under the page title. Non-technical on
  /// purpose — the modules are for people who do not know what a plist is.
  final String blurb;

  static List<AppDestination> of(NavGroup group) =>
      values.where((d) => d.group == group).toList();

  /// Branch index in the shell route. Branches are declared in enum order, so
  /// this is the index — but going through a named getter means the router and
  /// the sidebar cannot disagree about it.
  int get branchIndex => values.indexOf(this);

  static AppDestination fromBranchIndex(int index) =>
      values[index.clamp(0, values.length - 1)];

  /// Where the app opens.
  static const AppDestination initial = AppDestination.smartCare;
}
