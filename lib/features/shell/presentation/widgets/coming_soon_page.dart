import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/widgets/module_scaffold.dart';
import 'package:mac_uninstaller/core/widgets/tidy_card.dart';
import 'package:mac_uninstaller/features/shell/domain/app_destination.dart';

/// Placeholder for a module that isn't built yet.
///
/// It says so plainly and lists what it will do. The alternative — a Scan
/// button that finds nothing — is worse than an empty page: a cleaner that
/// reports "0 threats found" from a scanner that does not exist is lying.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.destination, this.planned = const []});

  final AppDestination destination;

  /// The tools this module will hold, so the page still explains the plan.
  final List<String> planned;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ModuleScaffold(
      title: destination.label,
      subtitle: destination.blurb,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TidyCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.accentMuted,
                    borderRadius: AppRadii.mdAll,
                  ),
                  child: Icon(destination.icon, size: 20, color: colors.accent),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Not built yet', style: context.text.titleM),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'This module is on the roadmap. Rather than show you a '
                        'scan button that finds nothing, here is what it will do.',
                        style: context.text.bodyM,
                      ),
                      if (planned.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        for (final item in planned)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: colors.textMuted,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Text(item, style: context.text.bodyM),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
