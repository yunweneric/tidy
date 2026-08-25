import 'package:flutter/widgets.dart';
import 'package:tidy/core/design/app_icons.dart';

/// One feature that can show up in the menu bar.
///
/// This list used to be nine lists. "Which features have a menu bar surface"
/// was spelled out separately in three Swift fields, three autosave names, two
/// `switch`es on a section string, an enum in the panel, four more `switch`es
/// on that enum, and a copy in the landing page that duplicated the popover
/// widths with a comment admitting it. Adding a fifth surface meant finding all
/// nine, and missing one failed quietly — a section with no width, or an icon
/// with no panel behind it.
///
/// The [id] is the string that already crosses the channel to Swift, so nothing
/// about the wire format changed when this arrived.
enum MenuBarSurface {
  /// The machine: vitals, what is using it, what can be handed back.
  ///
  /// First, and the one that stays. In [MenuBarLayout.consolidated] this is the
  /// only item on the bar, and in [MenuBarLayout.separate] it is the fallback
  /// anchor for any surface whose own icon is switched off.
  dashboard(
    id: 'dashboard',
    label: 'Overview',
    icon: AppIcons.dashboard,
    autosaveName: 'TidyVitals',
    tooltip: 'Tidy',
    width: 460,
  ),
  aiUsage(
    id: 'ai-usage',
    label: 'AI',
    icon: AppIcons.aiUsage,
    autosaveName: 'TidyAiUsage',
    tooltip: 'AI usage today',
    width: 320,
  ),
  clipboard(
    id: 'clipboard',
    label: 'Clipboard',
    icon: AppIcons.clipboard,
    autosaveName: 'TidyClipboard',
    tooltip: 'Clipboard history',
    width: 320,
  ),
  network(
    id: 'network',
    label: 'Network',
    icon: AppIcons.network,
    autosaveName: 'TidyNetwork',
    tooltip: 'Network activity',
    width: 320,
  );

  const MenuBarSurface({
    required this.id,
    required this.label,
    required this.icon,
    required this.autosaveName,
    required this.tooltip,
    required this.width,
  });

  /// What crosses the channel, and what the panel's remembered heights are
  /// filed under. Not [name] — `aiUsage` would put a camel-cased identifier on
  /// the wire, and the three that existed before this enum were already
  /// hyphenated strings chosen for the wire rather than for Dart.
  final String id;

  /// What the tab says in the consolidated panel.
  final String label;

  final IconData icon;

  /// What AppKit files this item's visibility under.
  ///
  /// **Load-bearing, and the reason it lives here rather than in Swift.**
  /// Without a name of its own AppKit files a status item under an ordinal
  /// (`Item-0`, `Item-1`…) in a namespace shared with *every other app on the
  /// machine* — and Control Center's menu bar switches write into exactly
  /// those keys. See `MenuBarController.claim(_:as:)` for the incident.
  final String autosaveName;

  final String tooltip;

  /// The popover's width in points when this surface is the whole panel.
  ///
  /// Only consulted in [MenuBarLayout.separate]; the consolidated panel is one
  /// fixed width for every tab, because a tab strip that resizes its own
  /// container moves the thing you are about to click.
  final double width;

  /// Whether this surface draws text in the bar rather than just a glyph.
  ///
  /// The two that do are the two that cost real width, and between them the
  /// reason the consolidated layout exists. Mirrored in `MenuBarPrefs.swift`.
  bool get hasReadout =>
      this == MenuBarSurface.aiUsage || this == MenuBarSurface.network;

  static MenuBarSurface? tryParse(String? id) {
    if (id == null) return null;
    for (final surface in values) {
      if (surface.id == id) return surface;
    }
    return null;
  }

  /// The surface a `null` section means — an icon that asked for nothing.
  static const MenuBarSurface fallback = MenuBarSurface.dashboard;
}

/// How many status items Tidy puts on the bar.
///
/// The trade is menu bar width, and it is real rather than cosmetic: a menu bar
/// has only what is left after the frontmost app's menus, and on a notched Mac
/// only what is left to the *right* of the notch. Past that, macOS does not
/// shrink anything or drop the widest item — it hands out slots underneath the
/// notch, where nothing is drawn, and icons the user already had disappear.
enum MenuBarLayout {
  /// One icon. Every surface is a tab in its popover.
  consolidated(
    'One item',
    'A single Tidy icon. Everything else is a tab inside it — the least menu '
        'bar space, and nothing to lose track of.',
  ),

  /// An icon per surface, each with its own switch.
  separate(
    'Separate items',
    'One icon per feature, and you choose which. Readouts live here too, and '
        'they are what cost the room.',
  );

  const MenuBarLayout(this.label, this.blurb);

  final String label;
  final String blurb;

  bool get isConsolidated => this == MenuBarLayout.consolidated;

  static MenuBarLayout fromName(String? name) => values.firstWhere(
    (layout) => layout.name == name,
    orElse: () => MenuBarLayout.consolidated,
  );
}
