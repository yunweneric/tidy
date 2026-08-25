import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/features/ai_usage/data/models/ai_menu_bar_style.dart';
import 'package:tidy/features/menubar/domain/menu_bar_surface.dart';

/// What the native side needs to know to build the menu bar.
///
/// Keys match `AppSettings` exactly — `MenuBarPrefs.swift` reads the same file
/// at launch, before any engine has run, so a rename on one side and not the
/// other leaves the user with the wrong menu bar and no error anywhere.
class MenuBarPrefs {
  const MenuBarPrefs({
    required this.layout,
    required this.showVitals,
    required this.showAiUsage,
    required this.showClipboard,
    required this.showNetwork,
    required this.aiStyle,
  });

  factory MenuBarPrefs.from(AppSettings settings) => MenuBarPrefs(
    layout: settings.menuBarLayout,
    showVitals: settings.showInMenuBar(MenuBarSurface.dashboard),
    showAiUsage: settings.showInMenuBar(MenuBarSurface.aiUsage),
    showClipboard: settings.showInMenuBar(MenuBarSurface.clipboard),
    showNetwork: settings.showInMenuBar(MenuBarSurface.network),
    aiStyle: settings.aiMenuBarStyle,
  );

  final MenuBarLayout layout;
  final bool showVitals;
  final bool showAiUsage;
  final bool showClipboard;
  final bool showNetwork;
  final AiMenuBarStyle aiStyle;

  /// The surfaces that get an icon, in bar order.
  ///
  /// The same rule the native side applies, kept here so Settings can show the
  /// count without asking across the boundary: consolidated is always exactly
  /// one item whatever the switches say, and separate never falls to zero —
  /// an app with no icon has no way back into its own settings from the bar.
  List<MenuBarSurface> get visibleSurfaces {
    if (layout.isConsolidated) return const [MenuBarSurface.dashboard];
    final wanted = [
      for (final surface in MenuBarSurface.values)
        if (switch (surface) {
          MenuBarSurface.dashboard => showVitals,
          MenuBarSurface.aiUsage => showAiUsage,
          MenuBarSurface.clipboard => showClipboard,
          MenuBarSurface.network => showNetwork,
        })
          surface,
    ];
    return wanted.isEmpty ? const [MenuBarSurface.dashboard] : wanted;
  }

  Map<String, dynamic> toMap() => {
    'menuBarLayout': layout.name,
    'menuBarShowVitals': showVitals,
    'menuBarShowAiUsage': showAiUsage,
    'menuBarShowClipboard': showClipboard,
    'networkMenuBarEnabled': showNetwork,
    'aiMenuBarStyle': aiStyle.name,
  };

  @override
  bool operator ==(Object other) =>
      other is MenuBarPrefs &&
      other.layout == layout &&
      other.showVitals == showVitals &&
      other.showAiUsage == showAiUsage &&
      other.showClipboard == showClipboard &&
      other.showNetwork == showNetwork &&
      other.aiStyle == aiStyle;

  @override
  int get hashCode => Object.hash(
    layout,
    showVitals,
    showAiUsage,
    showClipboard,
    showNetwork,
    aiStyle,
  );
}
