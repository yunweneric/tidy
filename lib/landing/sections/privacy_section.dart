import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// One claim, stated once, with the number that makes it checkable.
class PrivacySection extends StatelessWidget {
  const PrivacySection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final narrow = context.windowSize.isBelow(WindowSizeClass.expanded);

    return LandingSection(
      child: Reveal(
        child: Container(
          padding: EdgeInsets.all(narrow ? AppSpacing.xxl : 48),
          decoration: BoxDecoration(
            color: colors.accentMuted,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: colors.accentMuted),
          ),
          child: Flex(
            direction: narrow ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment:
                narrow ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadii.lgAll,
                ),
                child: Icon(AppIcons.privacy, size: 30, color: colors.accent),
              ),
              SizedBox(
                width: narrow ? 0 : AppSpacing.xxxl,
                height: narrow ? AppSpacing.xl : 0,
              ),
              Expanded(
                flex: narrow ? 0 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'One network request, ever',
                      style: TextStyle(
                        fontSize: narrow ? 26 : 32,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Tidy checks GitHub once a day to see whether there is a '
                      'newer version. That request sends nothing but the '
                      'question, and you can switch it off in Settings. '
                      'Nothing else leaves your Mac: no account, no telemetry, '
                      'no analytics, no list of what you have installed.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
