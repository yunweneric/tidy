import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/widgets/feature_card.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';

/// Why anyone needs this. Four things a Mac does quietly, in the user's words
/// rather than the filesystem's.
class ProblemSection extends StatelessWidget {
  const ProblemSection({super.key, this.anchor});

  final GlobalKey? anchor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LandingSection(
      anchor: anchor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading(
            eyebrow: 'The problem',
            title: 'Your Mac fills up quietly',
            lead:
                'Nothing announces itself. A hundred gigabytes go missing over '
                'a couple of years, and every explanation lives somewhere you '
                'were never meant to look.',
          ),
          const SizedBox(height: AppSpacing.xxxl),
          LandingGrid(
            columns: LandingGrid.columnsFor(context, wide: 4),
            children: [
              FeatureCard(
                icon: AppIcons.cleanup,
                tone: colors.safe,
                title: 'Caches nobody clears',
                body:
                    'Every browser, every editor, every chat app keeps its own '
                    'cache. They are regenerated on demand and they are never '
                    'cleaned up.',
              ),
              FeatureCard(
                icon: AppIcons.applications,
                tone: colors.info,
                title: 'Apps that never really left',
                body:
                    'Dragging an app to the Trash leaves its preferences, its '
                    'application support folder, its launch agents and its '
                    'logs exactly where they were.',
              ),
              FeatureCard(
                icon: AppIcons.loginItems,
                tone: colors.review,
                title: 'Startup you never approved',
                body:
                    'Installers add login items and background agents without '
                    'asking. They are still starting up years after you '
                    'stopped using what put them there.',
              ),
              FeatureCard(
                icon: AppIcons.recycleBin,
                tone: colors.risky,
                title: 'A Trash you are afraid of',
                body:
                    'Emptying it is irreversible and nothing tells you what is '
                    'actually in there, so it sits full — on every volume, not '
                    'just the one.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
