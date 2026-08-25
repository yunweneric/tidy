import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// Download to first clean, including the part most pages leave out.
class StepsSection extends StatelessWidget {
  const StepsSection({super.key, this.anchor});

  final GlobalKey? anchor;

  static const List<({String title, String body})> _steps = [
    (
      title: 'Download the disk image',
      body:
          'One file, about 21 MB. Open it and drag Tidy into Applications, '
          'the way every Mac app has always worked.',
    ),
    (
      title: 'Open it once the long way',
      body:
          'Builds from CI are ad-hoc signed rather than notarised, so the '
          'first launch is blocked. System Settings → Privacy & Security → '
          'Open Anyway, and that is the last you will see of it.',
    ),
    (
      title: 'Grant Full Disk Access',
      body:
          'Optional, but without it a scan cannot see into every folder. Tidy '
          'tells you when a figure is under-reported rather than quietly '
          'showing you a smaller number.',
    ),
    (
      title: 'Run Smart Care',
      body:
          'One pass over every built module, reviewed in one place. Untick '
          'anything you want to keep, and press the button.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LandingSection(
      anchor: anchor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading(
            eyebrow: 'Getting started',
            title: 'Four steps, about two minutes',
          ),
          const SizedBox(height: AppSpacing.xxxl),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = context.windowSize.resolve<int>(
                compact: 1,
                medium: 2,
                large: 4,
              );
              const gap = AppSpacing.xxl;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;

              return Wrap(
                spacing: gap,
                runSpacing: AppSpacing.xxxl,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    SizedBox(
                      width: width,
                      child: StaggeredReveal(
                        index: i,
                        child: _Step(index: i, step: _steps[i]),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.step});

  final int index;
  final ({String title, String body}) step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Borderless: four cards in a row would read as four separate things, and
    // these are one sequence.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '0${index + 1}',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            color: colors.accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Divider(height: 1, color: colors.border),
        const SizedBox(height: AppSpacing.lg),
        Text(step.title, style: context.text.titleM),
        const SizedBox(height: AppSpacing.sm),
        Text(
          step.body,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.55,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
