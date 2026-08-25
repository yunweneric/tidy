import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/features/ai_usage/data/models/ai_menu_bar_style.dart';
import 'package:tidy/features/menubar/data/models/menu_bar_prefs.dart';
import 'package:tidy/features/menubar/domain/menu_bar_surface.dart';
import 'package:tidy/features/network/data/models/network_prefs.dart';
import 'package:tidy/features/settings/presentation/widgets/settings_controls.dart';

/// What Tidy puts in the menu bar.
///
/// The one settings section whose cost is measured in pixels the user cannot
/// get back by scrolling, which is why it leads with the count rather than
/// burying it: a menu bar has only what is left after the frontmost app's
/// menus, and past that macOS hands out slots underneath the notch where
/// nothing is drawn.
class MenuBarSection extends StatefulWidget {
  const MenuBarSection({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<MenuBarSection> createState() => _MenuBarSectionState();
}

class _MenuBarSectionState extends State<MenuBarSection> {
  AppSettings get _settings => widget.settings;

  /// Roughly what each item asks macOS for.
  ///
  /// A glyph is the 18pt canvas plus AppKit's own padding either side. A
  /// readout is text, and how wide it is depends on the style and on how fast
  /// the numbers are moving — the figure below is a working average rather than
  /// a promise, which is why the line says "about".
  static const double _glyphWidth = 38;
  static const double _readoutWidth = 96;

  @override
  Widget build(BuildContext context) {
    final layout = _settings.menuBarLayout;
    final separate = !layout.isConsolidated;
    final prefs = MenuBarPrefs.from(_settings);
    final visible = prefs.visibleSurfaces;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Budget(surfaces: visible, glyph: _glyphWidth, readout: _readoutWidth),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'Layout',
          children: [
            SettingsChoiceRow<MenuBarLayout>(
              title: 'Menu bar items',
              detail: layout.blurb,
              options: {
                for (final option in MenuBarLayout.values) option: option.label,
              },
              value: layout,
              onChanged:
                  (value) => setState(() => _settings.menuBarLayout = value),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'What to show',
          children: [
            for (final surface in MenuBarSurface.values)
              SettingsSwitchRow(
                title:
                    surface.label == 'Overview'
                        ? 'System gauge'
                        : surface.label,
                detail: _detailFor(surface),
                value: _settings.showInMenuBar(surface),
                // Greyed rather than hidden in the consolidated layout. The
                // switches are the *separate* layout's controls, and honouring
                // them in both would make "one item" a suggestion — but hiding
                // them would leave the layout choice looking like it did
                // nothing.
                enabled: separate,
                onChanged:
                    (value) => setState(
                      () => _settings.setShowInMenuBar(surface, value),
                    ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'Readouts',
          children: [
            SettingsChoiceRow<AiMenuBarStyle>(
              title: 'AI usage style',
              detail: _settings.aiMenuBarStyle.blurb,
              options: {
                for (final style in AiMenuBarStyle.values) style: style.label,
              },
              value: _settings.aiMenuBarStyle,
              // Gated on its own switch as well as the layout: a style picker
              // for an item that is not on the bar is a control with nothing
              // on the other end of it.
              enabled:
                  separate && _settings.showInMenuBar(MenuBarSurface.aiUsage),
              onChanged:
                  (value) => setState(() => _settings.aiMenuBarStyle = value),
            ),
            SettingsChoiceRow<NetworkMenuBarStyle>(
              title: 'Network style',
              detail: _settings.networkMenuBarStyle.blurb,
              options: {
                for (final style in NetworkMenuBarStyle.values)
                  style: style.label,
              },
              value: _settings.networkMenuBarStyle,
              enabled:
                  separate && _settings.showInMenuBar(MenuBarSurface.network),
              onChanged:
                  (value) =>
                      setState(() => _settings.networkMenuBarStyle = value),
            ),
          ],
        ),
      ],
    );
  }

  String _detailFor(MenuBarSurface surface) => switch (surface) {
    MenuBarSurface.dashboard =>
      'Disk, memory and what is running. Also the way back into ${Brand.name} '
          'with no window open, so this is the one that stays when everything '
          'else is off.',
    MenuBarSurface.aiUsage =>
      'Today’s AI spend at published API rates — not a bill. Carries a live '
          'readout, which is what costs the room.',
    MenuBarSurface.clipboard =>
      'What you have copied, and a click to put any of it back.',
    MenuBarSurface.network =>
      'A running download and upload rate. Turning it off gives the space '
          'back; the history keeps recording either way.',
  };
}

/// What the current choice is costing, before it is spent.
///
/// On screen rather than left to be discovered, because the failure it warns
/// about is invisible: macOS does not shrink a crowded menu bar or drop the
/// widest item — it hands out slots under the notch, and the icons that vanish
/// are as likely to be another app's as ours.
class _Budget extends StatelessWidget {
  const _Budget({
    required this.surfaces,
    required this.glyph,
    required this.readout,
  });

  final List<MenuBarSurface> surfaces;
  final double glyph;
  final double readout;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final points = surfaces.fold<double>(
      0,
      (sum, surface) => sum + (surface.hasReadout ? readout : glyph),
    );

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: 17, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${surfaces.length} '
                  '${surfaces.length == 1 ? 'item' : 'items'} · about '
                  '${points.round()} points of menu bar',
                  style: context.text.titleS,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'A menu bar has only what is left after the frontmost app’s '
                  'menus, and on a notched Mac only what is left to the right '
                  'of the notch. Past that macOS does not shrink anything or '
                  'drop the widest item — it hands out slots underneath the '
                  'notch, where nothing is drawn, and icons you already had '
                  'disappear.',
                  style: context.text.bodyM,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
