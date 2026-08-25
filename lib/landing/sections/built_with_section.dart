import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';
import 'package:tidy/landing/widgets/feature_card.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// How it is put together. The audience for this band is the person deciding
/// whether the app is likely to be any good, and for them the architecture *is*
/// a feature.
class BuiltWithSection extends StatelessWidget {
  const BuiltWithSection({super.key, this.anchor});

  final GlobalKey? anchor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LandingSection(
      anchor: anchor,
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading(
            eyebrow: 'Under it',
            title: 'Flutter on top, Swift underneath',
            lead:
                'The interface is Flutter, so light mode, dark mode and Reduce '
                'Motion are all one switch. Everything that touches the '
                'filesystem is native, because that is the part that has to be '
                'fast and has to be careful.',
          ),
          const SizedBox(height: AppSpacing.xxxl),
          LandingGrid(
            columns: LandingGrid.columnsFor(context),
            children: [
              FeatureCard(
                icon: AppIcons.cpu,
                tone: colors.accent,
                title: 'Sizing walks the tree itself',
                body:
                    'Directory sizes come from an fts(3) walk in Swift, not '
                    'from shelling out to du. It reports allocated blocks, '
                    'which is the number that actually comes back when you '
                    'delete something.',
              ),
              FeatureCard(
                icon: AppIcons.clipboard,
                tone: colors.info,
                title: 'The clipboard store is native',
                body:
                    'Capture has to keep working with no window open, and two '
                    'Flutter engines in separate isolates would be two writers '
                    'racing on every copy. The store is Swift; each engine '
                    'gets a channel onto it.',
              ),
              FeatureCard(
                icon: AppIcons.dashboard,
                tone: colors.safe,
                title: 'The menu bar is a second engine',
                body:
                    'The popover runs its own Flutter engine, so live vitals, '
                    'recent clips and Trash size stay one click away with the '
                    'main window closed.',
              ),
              FeatureCard(
                icon: AppIcons.locked,
                tone: colors.review,
                title: 'One shortcut, no keylogger',
                body:
                    '⌘⇧V is registered through Carbon rather than a global '
                    'NSEvent monitor. The monitor route needs Accessibility '
                    'permission and sees every keystroke you type; this one '
                    'asks for nothing.',
              ),
              FeatureCard(
                icon: AppIcons.refresh,
                tone: colors.upstream,
                title: 'It updates itself, carefully',
                body:
                    'Download, verify the checksum and the code signature, '
                    'confirm it is genuinely newer, then swap the bundle '
                    'atomically with renamex_np. A half-written app is never a '
                    'state it can end up in.',
              ),
              FeatureCard(
                icon: AppIcons.light,
                tone: colors.upstream,
                title: 'Every colour is a token',
                body:
                    'No widget hard-codes a colour, size, radius or duration. '
                    'It is why light mode works and why Reduce Motion is a '
                    'switch rather than a scavenger hunt — including on this '
                    'page, which is built from the same tokens.',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          const Reveal(child: _Stats()),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats();

  /// Counted off the app's own navigation model, minus the four supporting
  /// views, so this figure cannot fall out of step with the grid above it.
  static int get _moduleCount =>
      AppDestination.values.length -
      const {
        AppDestination.allTools,
        AppDestination.activity,
        AppDestination.assistant,
        AppDestination.settings,
      }.length;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final stats = <({String value, String label})>[
      (value: '1', label: 'codebase'),
      (value: '$_moduleCount', label: 'modules'),
      (value: '1', label: 'network request, daily'),
      (value: '0', label: 'accounts, ever'),
    ];

    return Wrap(
      spacing: 64,
      runSpacing: AppSpacing.xl,
      children: [
        for (final stat in stats)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stat.value,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(stat.label, style: context.text.bodyM),
            ],
          ),
      ],
    );
  }
}
