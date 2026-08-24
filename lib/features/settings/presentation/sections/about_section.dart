import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/tidy_card.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors.accentGradient,
                  ),
                  borderRadius: AppRadii.mdAll,
                ),
                child: Icon(Brand.mark, size: 19, color: colors.textOnAccent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Brand.name, style: context.text.titleM),
                    Text(Brand.tagline, style: context.text.bodyM),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: AppSpacing.xxl, color: colors.border),
          Text(
            'Runs outside the App Sandbox, which is what lets it read '
            '/Applications and ~/Library at all. Nothing leaves your Mac: '
            'every scan, every size and the clipboard history stay on this '
            'machine, and none of it is ever sent anywhere.',
            style: context.text.bodyM,
          ),
          const SizedBox(height: AppSpacing.md),
          // Stated here rather than left to be discovered. This is the one
          // request the app makes, and an app that claims to send nothing while
          // quietly contacting a server has spent the trust the rest of this
          // paragraph is asking for.
          Text(
            '${Brand.name} makes exactly one network request: once a day it '
            'asks GitHub whether a newer release has been published. It sends '
            'nothing but that question — no identifier, no usage, nothing '
            'about your Mac — and you can turn it off in Settings → Updates.',
            style: context.text.bodyM,
          ),
        ],
      ),
    );
  }
}
