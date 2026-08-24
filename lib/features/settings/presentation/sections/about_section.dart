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
            'machine, and ${Brand.name} makes no network requests of its own.',
            style: context.text.bodyM,
          ),
        ],
      ),
    );
  }
}
