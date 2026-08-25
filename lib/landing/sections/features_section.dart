import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';
import 'package:tidy/landing/preview/preview_mac.dart';
import 'package:tidy/landing/widgets/feature_card.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/landing_pill.dart';

/// Every module, generated from the app's own navigation model.
///
/// The labels, the glyphs, the one-line blurbs and the colours are
/// [AppDestination]'s — not a copy of them. A module added to the app appears
/// here on the next deploy, and one whose description is reworded is reworded
/// here too. A marketing page that has its own list of features is a marketing
/// page that will eventually be wrong.
class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key, this.anchor});

  final GlobalKey? anchor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Everything except the shell's supporting views, which are places rather
    // than features: All Tools, Activity, Assistant, Settings.
    const skipped = {
      AppDestination.allTools,
      AppDestination.activity,
      AppDestination.assistant,
      AppDestination.settings,
    };
    final modules =
        AppDestination.values
            .where((destination) => !skipped.contains(destination))
            .toList();

    return LandingSection(
      anchor: anchor,
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            eyebrow: 'What is in it',
            // Counted, not typed. A module added to the app must not leave a
            // number on the marketing page quietly saying otherwise.
            title: '${modules.length} modules, one window',
            lead:
                'Each one owns a colour of light, so you know where you are '
                'before you have read the page title. The ones that are not '
                'built yet say so — a cleaner reporting "0 threats found" from '
                'a scanner that does not exist is lying, and this app does not '
                'do that.',
          ),
          const SizedBox(height: AppSpacing.xxxl),
          LandingGrid(
            columns: LandingGrid.columnsFor(context),
            children: [
              for (final destination in modules)
                FeatureCard(
                  icon: destination.icon,
                  tone: colors.modulePalette(destination.tone).accent,
                  title: destination.label,
                  body: destination.blurb,
                  badge:
                      kPlannedDestinations.contains(destination)
                          ? const LandingPill(label: 'Planned')
                          : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
