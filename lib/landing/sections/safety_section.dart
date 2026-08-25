import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/widgets/feature_card.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// The promises, with the real chips.
///
/// A cleaner asks for a lot of trust, and the honest way to earn it is to be
/// specific about what it will not do. Every claim here is a rule that exists
/// in the code, not a value.
class SafetySection extends StatelessWidget {
  const SafetySection({super.key, this.anchor});

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
            eyebrow: 'Safety',
            title: 'Nothing goes without your say-so',
            lead:
                'Every finding is graded, listed with its size and its path, '
                'and shown to you before anything is touched.',
          ),
          const SizedBox(height: AppSpacing.xxl),
          Reveal(
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                // The app's own chips, so the words on the page are the words
                // on the screen.
                for (final level in SafetyLevel.values)
                  StatusChip.safety(level, context),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          LandingGrid(
            columns: LandingGrid.columnsFor(context),
            children: [
              FeatureCard(
                icon: AppIcons.safe,
                tone: colors.safe,
                title: 'Only the safe tier is pre-ticked',
                body:
                    'An inference about what a file probably is — an orphan, '
                    'an app you have not opened in six months — is never '
                    'marked safe, and never selected for you.',
              ),
              FeatureCard(
                icon: AppIcons.putBack,
                tone: colors.info,
                title: 'Removal means the Trash',
                body:
                    'Everything goes through FileManager.trashItem, so it is '
                    'recoverable and macOS’s own Put Back works. Permanent '
                    'deletion is a deliberate switch, behind a confirmation '
                    'that names the count and the size.',
              ),
              FeatureCard(
                icon: AppIcons.locked,
                tone: colors.risky,
                title: 'Some things are off limits',
                body:
                    'The native layer refuses /System, volume roots, mount '
                    'points, ~/Library and its standard subfolders, and your '
                    'home directory — whatever asks. It resolves symlinks '
                    'first, so a link cannot be used to reach past the guard.',
              ),
              FeatureCard(
                icon: AppIcons.search,
                tone: colors.review,
                title: 'Matched exactly, never loosely',
                body:
                    'Leftovers are found by bundle id and exact display name. '
                    'Never by substring, which is how cleaners end up deleting '
                    '~/Library/Mail because an app was called "Mail".',
              ),
              FeatureCard(
                icon: AppIcons.analytics,
                tone: colors.accent,
                title: 'Honest accounting',
                body:
                    'Sizes are what a file occupies, not its logical length — '
                    'on APFS a sparse Docker.raw reports 64 GB while using 8. '
                    'And "moved to Trash" is never reported as space reclaimed.',
              ),
              FeatureCard(
                icon: AppIcons.error,
                tone: colors.textMuted,
                title: 'Failures are reported',
                body:
                    'Per item, not swallowed. A leftover that needs '
                    'administrator rights says so instead of quietly appearing '
                    'to have worked.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
