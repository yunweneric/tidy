import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/widgets/brand_mark.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/core/widgets/usage_window_row.dart';
import 'package:tidy/features/ai_usage/data/models/ai_menu_bar_style.dart';
import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_readout_scope.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_summary.dart';
import 'package:tidy/features/ai_usage/data/models/ai_window_style.dart';
import 'package:tidy/features/menubar/data/models/menu_bar_prefs.dart';
import 'package:tidy/features/menubar/domain/menu_bar_surface.dart';
import 'package:tidy/features/network/data/models/network_prefs.dart';
import 'package:tidy/features/settings/presentation/widgets/settings_controls.dart';

/// What Tidy puts in the menu bar.
///
/// Leads with a drawing of the bar itself rather than with a list of switches,
/// because every setting here is about something the user cannot see while they
/// are setting it — it is twenty pixels tall, at the other end of the screen,
/// and behind whatever window is in front. Every control below changes the
/// strip at the top, which is the only place the choices can be compared.
///
/// It is also the one settings section whose cost is measured in pixels the
/// user cannot get back by scrolling, which is why the width is on screen next
/// to the drawing: a menu bar has only what is left after the frontmost app's
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

  /// Roughly what an item asks macOS for.
  ///
  /// A glyph is the 18pt canvas plus AppKit's own padding either side. A
  /// readout is text, and how wide it is depends on the style and on how fast
  /// the numbers are moving — the figures here are a working average rather
  /// than a promise, which is why the line says "about".
  static const double _glyphWidth = 38;
  static const double _readoutWidth = 96;

  /// What one surface costs in the style it is currently set to.
  ///
  /// Only the AI item varies enough to be worth asking about: its widest style
  /// with both tools on it is twice its narrowest, which is the difference
  /// between fitting on a 13" bar and not.
  double _widthOf(MenuBarSurface surface) => switch (surface) {
    MenuBarSurface.dashboard || MenuBarSurface.clipboard => _glyphWidth,
    MenuBarSurface.network => _readoutWidth,
    MenuBarSurface.aiUsage => switch (_settings.aiMenuBarStyle) {
      AiMenuBarStyle.cost => 54,
      AiMenuBarStyle.costAndTokens => 58,
      AiMenuBarStyle.block => 80,
      // Two bars and two figures where the scope asks for both tools, one of
      // each where it asks for one.
      AiMenuBarStyle.percentAndBlock =>
        _settings.aiReadoutScope == AiReadoutScope.both ? 116 : 60,
    },
  };

  @override
  Widget build(BuildContext context) {
    final layout = _settings.menuBarLayout;
    final separate = !layout.isConsolidated;
    final visible = MenuBarPrefs.from(_settings).visibleSurfaces;

    // A style picker for an item that is not on the bar is a control with
    // nothing on the other end of it, so both readout pickers are gated the
    // same way: the layout has to be `separate`, and the item switched on.
    final aiOnBar = separate && _settings.showInMenuBar(MenuBarSurface.aiUsage);
    final networkOnBar =
        separate && _settings.showInMenuBar(MenuBarSurface.network);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BarPreview(
          surfaces: visible,
          aiStyle: _settings.aiMenuBarStyle,
          aiScope: _settings.aiReadoutScope,
          networkStyle: _settings.networkMenuBarStyle,
          points: visible.fold<double>(0, (sum, s) => sum + _widthOf(s)),
        ),
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
        // The AI item's three settings together, bar and panel, rather than
        // split across a "readouts" group and a "windows" one. They are one
        // feature to the person setting them: what the icon says, and what
        // opens when it is clicked.
        SettingsGroup(
          title: 'AI usage',
          children: [
            SettingsChoiceRow<AiMenuBarStyle>(
              title: 'What the icon shows',
              detail: _settings.aiMenuBarStyle.blurb,
              options: {
                for (final style in AiMenuBarStyle.values) style: style.label,
              },
              value: _settings.aiMenuBarStyle,
              enabled: aiOnBar,
              onChanged:
                  (value) => setState(() => _settings.aiMenuBarStyle = value),
            ),
            SettingsChoiceRow<AiReadoutScope>(
              title: 'Whose usage',
              detail:
                  '${_settings.aiReadoutScope.blurb} The panel behind the icon '
                  'draws every tool it found either way — this is the bar, '
                  'which has no room to say whose figure it is showing.',
              options: {
                for (final scope in AiReadoutScope.values) scope: scope.label,
              },
              value: _settings.aiReadoutScope,
              enabled: aiOnBar,
              // Its options are short enough to sit on the line, but the row
              // above it cannot — and one control on the right of a group whose
              // others are underneath reads as a mistake rather than as a
              // saving.
              stacked: true,
              onChanged:
                  (value) => setState(() => _settings.aiReadoutScope = value),
            ),
            _PanelRows(
              style: _settings.aiWindowStyle,
              // Not gated on the AI icon or on the layout, unlike the two
              // above. These rows are drawn in the *panel*, which is a tab of
              // the consolidated item as well as a popover of its own — so the
              // choice always has something on the other end of it.
              onChanged:
                  (value) => setState(() => _settings.aiWindowStyle = value),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'Network',
          children: [
            SettingsChoiceRow<NetworkMenuBarStyle>(
              title: 'What the icon shows',
              detail: _settings.networkMenuBarStyle.blurb,
              options: {
                for (final style in NetworkMenuBarStyle.values)
                  style: style.label,
              },
              value: _settings.networkMenuBarStyle,
              enabled: networkOnBar,
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

// ─── The bar itself ──────────────────────────────────────────────────────────

/// The invented figures every preview on this page draws.
///
/// One set, named once, because two previews showing the same bar with
/// different numbers in it would read as two different bars. They are split so
/// that a scoped readout adds up to the unscoped one — $8.10 and $4.30 really
/// do make $12.40 — which is the sort of thing a reader checks without meaning
/// to, and disbelieves the whole drawing over.
class _Sample {
  const _Sample._();

  static const double claudeCost = 8.10;
  static const double codexCost = 4.30;
  static const String claudeTokens = '2.9M';
  static const String codexTokens = '1.2M';
  static const String bothTokens = '4.1M';

  /// Claude Code part-way through a five-hour block, Codex part-way through
  /// its published allowance. Two different facts, which is the point of
  /// drawing both — see [AiMenuBarStyle.percentAndBlock].
  static const double claudeShare = 0.47;
  static const double codexShare = 0.27;

  static const String down = '1.2 MB/s';
  static const String up = '240 KB/s';
}

/// Tidy's items as the bar will draw them, with what they cost underneath.
///
/// A second renderer for something Swift already draws, which is a real cost —
/// the two can drift, and only a comment holds them together. It earns it: the
/// styles differ in *what they claim*, not only in width, and the only other
/// way to compare two of them is to change the setting, look up at the corner
/// of the screen, and change it back.
class _BarPreview extends StatelessWidget {
  const _BarPreview({
    required this.surfaces,
    required this.aiStyle,
    required this.aiScope,
    required this.networkStyle,
    required this.points,
  });

  final List<MenuBarSurface> surfaces;
  final AiMenuBarStyle aiStyle;
  final AiReadoutScope aiScope;
  final NetworkMenuBarStyle networkStyle;

  /// What the current choice asks the bar for, in points.
  final double points;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              // The popover's own surface, which is the one solid neutral in
              // the palette — see ui.md. This is a piece of system chrome, not
              // a card inside the page.
              color: colors.surfaceOpaque,
              borderRadius: AppRadii.mdAll,
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                // Ours sit to the right of everything the system puts up
                // there, which is where the eye goes looking for them.
                const Spacer(),
                for (final surface in surfaces) ...[
                  _Item(
                    surface: surface,
                    aiStyle: aiStyle,
                    aiScope: aiScope,
                    networkStyle: networkStyle,
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                // A clock, because a strip of numbers with nothing familiar on
                // it does not read as a menu bar at all.
                Text(
                  '9:41',
                  style: text.mono.copyWith(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
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
                      style: text.titleS,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Sample figures above. A menu bar has only what is left '
                      'after the frontmost app’s menus, and on a notched Mac '
                      'only what is left to the right of the notch. Past that '
                      'macOS does not shrink anything or drop the widest item '
                      '— it hands out slots underneath the notch, where '
                      'nothing is drawn, and icons you already had disappear.',
                      style: text.bodyM,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One status item: a glyph, or the readout its style asks for.
class _Item extends StatelessWidget {
  const _Item({
    required this.surface,
    required this.aiStyle,
    required this.aiScope,
    required this.networkStyle,
  });

  final MenuBarSurface surface;
  final AiMenuBarStyle aiStyle;
  final AiReadoutScope aiScope;
  final NetworkMenuBarStyle networkStyle;

  @override
  Widget build(BuildContext context) => switch (surface) {
    // The app's own mark, not a stock glyph: on the bar these are the same
    // drawing at two sizes, and a preview that borrowed something else would
    // be showing an icon the user will never see.
    MenuBarSurface.dashboard => const BrandMark(size: 16, tile: false),
    MenuBarSurface.clipboard => Icon(
      surface.icon,
      size: 15,
      color: context.colors.textPrimary,
    ),
    MenuBarSurface.aiUsage => _AiReadout(style: aiStyle, scope: aiScope),
    MenuBarSurface.network => _NetworkReadout(style: networkStyle),
  };
}

/// The AI item, in the style and scope it is set to.
class _AiReadout extends StatelessWidget {
  const _AiReadout({required this.style, required this.scope});

  final AiMenuBarStyle style;
  final AiReadoutScope scope;

  @override
  Widget build(BuildContext context) {
    final claude = scope.covers(AiProvider.claudeCode);
    final codex = scope.covers(AiProvider.codex);

    final cost =
        (claude ? _Sample.claudeCost : 0.0) + (codex ? _Sample.codexCost : 0.0);
    final tokens = switch (scope) {
      AiReadoutScope.both => _Sample.bothTokens,
      AiReadoutScope.claudeCode => _Sample.claudeTokens,
      AiReadoutScope.codex => _Sample.codexTokens,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: switch (style) {
        AiMenuBarStyle.cost => [_Figure(_usd(cost))],
        AiMenuBarStyle.costAndTokens => [
          _Stacked(top: _usd(cost), bottom: tokens),
        ],
        AiMenuBarStyle.block => [
          const _ReadoutBar(share: _Sample.claudeShare),
          const SizedBox(width: AppSpacing.xs),
          _Figure(_usd(cost)),
        ],
        // A bar and a figure per provider, in bar order, with a wider gap
        // between the pairs than inside one — the same spacing the native
        // readout uses, and what keeps it reading as two pairs rather than
        // four loose things.
        AiMenuBarStyle.percentAndBlock => [
          if (claude) ...[
            const _ReadoutBar(share: _Sample.claudeShare),
            const SizedBox(width: AppSpacing.xs),
            const _Figure('47%'),
          ],
          if (claude && codex) const SizedBox(width: AppSpacing.sm),
          if (codex) ...[
            const _ReadoutBar(share: _Sample.codexShare),
            const SizedBox(width: AppSpacing.xs),
            const _Figure('27%'),
          ],
        ],
      },
    );
  }

  static String _usd(double amount) => '\$${amount.toStringAsFixed(2)}';
}

/// The network item, in the style it is set to.
class _NetworkReadout extends StatelessWidget {
  const _NetworkReadout({required this.style});

  final NetworkMenuBarStyle style;

  @override
  Widget build(BuildContext context) => switch (style) {
    NetworkMenuBarStyle.compact => _Figure(
      '↓ ${_Sample.down}  ↑ ${_Sample.up}',
    ),
    NetworkMenuBarStyle.twoLine => _Stacked(
      top: '↓ ${_Sample.down}',
      bottom: '↑ ${_Sample.up}',
    ),
    NetworkMenuBarStyle.sparkline => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Sparkline(),
        const SizedBox(width: AppSpacing.xs),
        _Stacked(top: '↓ ${_Sample.down}', bottom: '↑ ${_Sample.up}'),
      ],
    ),
  };
}

/// One figure, in the face the bar draws it in: tabular digits, so nothing
/// jiggles as the numbers change.
class _Figure extends StatelessWidget {
  const _Figure(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.text.mono.copyWith(
      fontSize: 12,
      color: context.colors.textPrimary,
    ),
  );
}

/// Two lines, the way the native readouts stack a pair.
class _Stacked extends StatelessWidget {
  const _Stacked({required this.top, required this.bottom});

  final String top;
  final String bottom;

  @override
  Widget build(BuildContext context) {
    final style = context.text.mono.copyWith(
      fontSize: 10,
      height: 1.15,
      color: context.colors.textPrimary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [Text(top, style: style), Text(bottom, style: style)],
    );
  }
}

/// The bar the AI item draws: six segments in 24 points.
///
/// Mirrors `MenuBarController.blockImage`. If one of the two changes the other
/// is wrong, and there is no compiler between them.
class _ReadoutBar extends StatelessWidget {
  const _ReadoutBar({required this.share});

  final double share;

  static const int _segments = 6;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filled = (_segments * share.clamp(0.0, 1.0)).round();

    return SizedBox(
      width: 24,
      height: 7,
      child: Row(
        children: [
          for (var i = 0; i < _segments; i++) ...[
            if (i > 0) const SizedBox(width: 1),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1.5),
                  // Lit segments at full strength, unlit ones at a third of it.
                  // The bar is 24pt wide in a 22pt bar and gets a fraction of a
                  // second's attention; anything subtler than this is not a
                  // reading, it is a smudge.
                  color:
                      i < filled
                          ? colors.textPrimary
                          : colors.textPrimary.withValues(alpha: 0.32),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A stand-in for the live graph, drawn from a fixed shape.
///
/// Not a real sample: this pane has no network reading and starting one to
/// decorate a settings preview would be a monitor running for a picture.
class _Sparkline extends StatelessWidget {
  const _Sparkline();

  static const List<double> _shape = [
    0.2,
    0.5,
    0.35,
    0.8,
    0.55,
    0.9,
    0.4,
    0.6,
    0.3,
    0.7,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: 26,
      height: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final value in _shape) ...[
            Expanded(
              child: Container(
                height: 14 * value,
                margin: const EdgeInsets.only(right: 1),
                decoration: BoxDecoration(
                  color: colors.textPrimary.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(0.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── The panel behind it ─────────────────────────────────────────────────────

/// The panel's row style, with the rows themselves underneath it.
///
/// A picker and its preview in one row rather than two siblings, because the
/// preview is the only part of it that answers the question the picker asks.
class _PanelRows extends StatelessWidget {
  const _PanelRows({required this.style, required this.onChanged});

  final AiWindowStyle style;
  final ValueChanged<AiWindowStyle> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsChoiceRow<AiWindowStyle>(
        title: 'Panel rows',
        detail: style.blurb,
        options: {for (final value in AiWindowStyle.values) value: value.label},
        value: style,
        // With the rest of its group, and because the preview underneath
        // belongs to this control — the two want the same column.
        stacked: true,
        onChanged: onChanged,
      ),
      const SizedBox(height: AppSpacing.md),
      _WindowPreview(style: style),
    ],
  );
}

/// The panel's usage rows, drawn in the chosen style on the sample figures.
///
/// Here rather than left to the next time the popover happens to be open: the
/// styles differ in what each row *says*, not only in how tall it is, and a
/// picker for that read blind is a picker for nothing.
class _WindowPreview extends StatelessWidget {
  const _WindowPreview({required this.style});

  final AiWindowStyle style;

  /// The popover's width, so the rows wrap and ellipsise here exactly where
  /// they will there. A preview at settings width would be a different panel.
  static const double _panelWidth = 320;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();

    // One measured window and one inferred, because the difference between
    // them is the thing worth seeing before choosing: only one of the two is
    // allowed to claim a share of an allowance.
    final windows = [
      AiUsageWindow(
        provider: AiProvider.claudeCode,
        label: 'Session (5h)',
        tokens: 1240000,
        resetsAt: now.add(const Duration(hours: 2, minutes: 39)),
        elapsed: _Sample.claudeShare,
      ),
      AiUsageWindow(
        provider: AiProvider.codex,
        label: 'Weekly',
        tokens: 4120000,
        resetsAt: now.add(const Duration(days: 3, hours: 4)),
        usedPercent: _Sample.codexShare * 100,
      ),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _panelWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceOpaque,
          borderRadius: AppRadii.lgAll,
          border: Border.all(color: colors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final window in windows)
                UsageWindowRow(window: window, now: now, style: style),
            ],
          ),
        ),
      ),
    );
  }
}
