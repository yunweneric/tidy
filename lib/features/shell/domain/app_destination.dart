import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/design/tokens/app_color_tokens.dart';
import 'package:flutter/material.dart';

/// Where a sidebar entry sits.
///
/// The split that matters is [soon] against the rest: everything in the other
/// three groups opens onto something that works, and everything in [soon]
/// opens onto a [ComingSoonPage]. Keeping that visible in the rail means a
/// user finds out what is built by reading the sidebar rather than by clicking
/// six things that turn out to be a roadmap.
enum NavGroup {
  /// The modules that do the work.
  primary,

  /// Supporting views. Built, but somewhere you go to look rather than to act.
  secondary,

  /// Not built yet. Every member routes to a [ComingSoonPage], and the rail
  /// heads the group with a SOON badge so that is clear before the click.
  soon,

  /// Pinned to the bottom, always reachable.
  footer,
}

/// Every top-level view in the app.
///
/// Previously the sidebar navigated by `AppFilter`, which meant the nav model
/// and the applications table's filter were the same enum — fine with one
/// screen, impossible with ten.
enum AppDestination {
  /// First on purpose, and the only value ever inserted rather than appended.
  ///
  /// The warnings below about branch indices being positional are about not
  /// *accidentally* reordering the sidebar. Here the reorder is the point: this
  /// is the screen the app opens on and the first row in the rail. It is safe
  /// because nothing persists a branch index — `branchIndex` is derived from
  /// this list, `AppSettings` stores no route, and the menu-bar popover deep
  /// links by `path` string.
  dashboard(
    path: '/dashboard',
    label: 'Dashboard',
    icon: AppIcons.dashboard,
    group: NavGroup.primary,
    blurb: 'How your Mac is doing, and what Tidy has done about it.',
  ),
  smartCare(
    path: '/smart-care',
    label: 'Smart Care',
    icon: AppIcons.smartCare,
    group: NavGroup.primary,
    blurb: 'One pass over everything, then a single review.',
    tone: ModuleTone.smartCare,
  ),
  cleanup(
    path: '/cleanup',
    label: 'Cleanup',
    icon: AppIcons.cleanup,
    group: NavGroup.primary,
    blurb: 'Reclaim space from caches, logs and build artefacts.',
    tone: ModuleTone.cleanup,
  ),
  protection(
    path: '/protection',
    label: 'Protection',
    icon: AppIcons.protection,
    group: NavGroup.soon,
    blurb: 'Check for known adware and unusual background items.',
    tone: ModuleTone.protection,
  ),
  performance(
    path: '/performance',
    label: 'Performance',
    icon: AppIcons.performance,
    group: NavGroup.primary,
    blurb: 'Tune startup items and run macOS upkeep.',
    tone: ModuleTone.performance,
  ),
  applications(
    path: '/applications',
    label: 'Applications',
    icon: AppIcons.applications,
    group: NavGroup.primary,
    blurb: 'Uninstall apps completely, and clean up after old ones.',
    tone: ModuleTone.applications,
  ),
  clutter(
    path: '/clutter',
    label: 'My Clutter',
    icon: AppIcons.clutter,
    group: NavGroup.primary,
    blurb: 'Find duplicates, near-identical photos and forgotten files.',
    tone: ModuleTone.clutter,
  ),
  spaceLens(
    path: '/space-lens',
    label: 'Space Lens',
    icon: AppIcons.spaceLens,
    group: NavGroup.soon,
    blurb: 'See what is actually filling your disk.',
    tone: ModuleTone.spaceLens,
  ),
  allTools(
    path: '/all-tools',
    label: 'All Tools',
    icon: AppIcons.allTools,
    group: NavGroup.soon,
    blurb: 'Every scanner on its own, without the modules.',
  ),
  activity(
    path: '/activity',
    label: 'Activity',
    icon: AppIcons.activity,
    group: NavGroup.soon,
    blurb: 'What has been cleaned, and what to look at next.',
  ),

  /// Under SOON rather than pinned to the footer beside Settings, which is
  /// where it used to sit. The footer is for what is always one click away,
  /// and a row that opens onto a roadmap is not that.
  assistant(
    path: '/assistant',
    label: 'Assistant',
    icon: AppIcons.assistant,
    group: NavGroup.soon,
    blurb: 'How your Mac is doing, and what would help most.',
  ),
  settings(
    path: '/settings',
    label: 'Settings',
    icon: AppIcons.settings,
    group: NavGroup.footer,
    blurb: 'Appearance, scanning and permissions.',
  ),

  /// Appended rather than slotted in next to Space Lens: branches are declared
  /// in enum order, so inserting in the middle renumbers every branch after it.
  /// The sidebar groups by [NavGroup] regardless, so this still lists under
  /// MORE with the other supporting views.
  recycleBin(
    path: '/recycle-bin',
    label: 'Recycle Bin',
    icon: AppIcons.recycleBin,
    group: NavGroup.secondary,
    blurb: 'See what is in the Trash, put things back, or clear it for good.',
  ),

  /// Appended for the same reason [recycleBin] was, and listed under the
  /// working modules because it is one — it is somewhere you go to get
  /// something back, not a supporting view.
  clipboard(
    path: '/clipboard',
    label: 'Clipboard',
    icon: AppIcons.clipboard,
    group: NavGroup.primary,
    blurb: 'Everything you have copied, and a way back to any of it.',
  ),

  /// Appended, like the two above it, because branch indices are positional.
  ///
  /// Listed under MORE rather than with the working modules, and toned anyway:
  /// it is somewhere you go to *watch* rather than to act, and it still earns
  /// a colour — the window says which view you are looking at before the title
  /// has been read.
  network(
    path: '/network',
    label: 'Network',
    icon: AppIcons.network,
    group: NavGroup.secondary,
    blurb: 'What your Mac is sending and receiving, now and over time.',
    tone: ModuleTone.network,
  ),

  /// Appended, like everything since Recycle Bin, because branch indices are
  /// positional. Under MORE with Network: somewhere you go to watch something
  /// rather than to change something.
  aiUsage(
    path: '/ai-usage',
    label: 'AI Usage',
    icon: AppIcons.aiUsage,
    group: NavGroup.secondary,
    blurb:
        'What your AI coding tools have got through, and what it would cost.',
    tone: ModuleTone.aiUsage,
  );

  const AppDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.group,
    required this.blurb,
    this.tone = ModuleTone.brand,
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

  /// The colour of light this destination gives the window. Defaults to the
  /// brand violet, which is what the supporting views (Recycle Bin, Settings)
  /// and the unbuilt ones keep — a hue per module means something only while
  /// there are six of them, not eleven.
  final ModuleTone tone;

  static List<AppDestination> of(NavGroup group) =>
      values.where((d) => d.group == group).toList();

  /// Branch index in the shell route. Branches are declared in enum order, so
  /// this is the index — but going through a named getter means the router and
  /// the sidebar cannot disagree about it.
  int get branchIndex => values.indexOf(this);

  static AppDestination fromBranchIndex(int index) =>
      values[index.clamp(0, values.length - 1)];

  /// Where the app opens.
  static const AppDestination initial = AppDestination.dashboard;
}
