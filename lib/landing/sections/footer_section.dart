import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/data/tidy_repo.dart';
import 'package:tidy/landing/state/landing_controller.dart';
import 'package:tidy/landing/widgets/landing_button.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';

class FooterSection extends StatelessWidget {
  const FooterSection({super.key, required this.controller});

  final LandingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final narrow = context.windowSize.isBelow(WindowSizeClass.expanded);
    final version = controller.version;

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.canvas),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.sidebar),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 44),
          child: LandingContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flex(
                  direction: narrow ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment:
                      narrow
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrandMark(size: 32),
                        const SizedBox(width: AppSpacing.md),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              Brand.name,
                              style: context.text.titleM.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(Brand.tagline, style: context.text.caption),
                          ],
                        ),
                      ],
                    ),
                    if (narrow)
                      const SizedBox(height: AppSpacing.xl)
                    else
                      const Spacer(),
                    Wrap(
                      spacing: AppSpacing.xl,
                      runSpacing: AppSpacing.md,
                      children: const [
                        LandingLink(label: 'GitHub', url: TidyRepo.url),
                        LandingLink(label: 'Releases', url: TidyRepo.releases),
                        LandingLink(label: 'Issues', url: TidyRepo.issues),
                        LandingLink(label: 'Licence', url: TidyRepo.license),
                        LandingLink(label: 'Readme', url: TidyRepo.readme),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                Divider(height: 1, color: colors.border),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '© 2026 Yunweneric · GPL-3.0',
                      style: context.text.caption,
                    ),
                    Text('·', style: context.text.caption),
                    Text(
                      version == null
                          ? 'macOS 11 or later'
                          : 'v$version · macOS 11 or later',
                      style: context.text.caption,
                    ),
                    Text('·', style: context.text.caption),
                    Text(
                      'This page is Tidy, compiled for the web.',
                      style: context.text.caption,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
