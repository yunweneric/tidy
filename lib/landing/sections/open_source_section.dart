import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/data/tidy_repo.dart';
import 'package:tidy/landing/state/landing_controller.dart';
import 'package:tidy/landing/widgets/landing_button.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// Free, and the source is the whole argument.
///
/// An app that asks for Full Disk Access and then walks your Library is exactly
/// the kind of app whose source you should be able to read.
class OpenSourceSection extends StatelessWidget {
  const OpenSourceSection({super.key, required this.controller});

  final LandingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final narrow = context.windowSize.isBelow(WindowSizeClass.expanded);
    final stars = controller.stars;

    return LandingSection(
      child: Reveal(
        child: Container(
          padding: EdgeInsets.all(narrow ? AppSpacing.xxl : 48),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.unlocked, size: 30, color: colors.accent),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Free, and open source under GPL-3.0',
                style: TextStyle(
                  fontSize: narrow ? 26 : 32,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(
                  'Every guard described on this page is a few lines you can '
                  'go and read — the path checks in Swift, the safety grading '
                  'in Dart, the one network call. Copyleft, so a modified Tidy '
                  'has to stay as readable as this one.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  LandingButton(
                    label:
                        stars == null
                            ? 'Read the source'
                            : 'Read the source · $stars★',
                    icon: AppIcons.openExternal,
                    url: TidyRepo.url,
                  ),
                  LandingButton(
                    label: 'The licence',
                    icon: AppIcons.document,
                    kind: LandingButtonKind.secondary,
                    url: TidyRepo.license,
                  ),
                  LandingButton(
                    label: 'Report something',
                    icon: AppIcons.error,
                    kind: LandingButtonKind.secondary,
                    url: TidyRepo.issues,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
