import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/di/service_locator.dart';
import 'package:mac_uninstaller/core/platform/full_disk_access_service.dart';
import 'package:mac_uninstaller/core/scanning/logic/scan_bloc.dart';
import 'package:mac_uninstaller/core/scanning/presentation/scan_view.dart';
import 'package:mac_uninstaller/core/widgets/tidy_card.dart';
import 'package:mac_uninstaller/features/smart_care/data/smart_care_module.dart';

/// The Smart Care module.
///
/// Like every other module page, this is [ScanView] pointed at a module — the
/// only addition is a note saying what the sweep does and does not cover, since
/// "Smart Care" sounds comprehensive and right now it is not.
class SmartCarePage extends StatelessWidget {
  const SmartCarePage({super.key});

  @override
  Widget build(BuildContext context) {
    final fullDiskAccess = locator<FullDiskAccessService>();

    // Its own bloc, nested inside the shell's. The shell provides Cleanup's so
    // the sidebar can read it; Smart Care runs a different, wider scan and must
    // not overwrite that one.
    return BlocProvider(
      create: (_) => ScanBloc(
        locator<SmartCareModule>(),
        hasFullDiskAccess: fullDiskAccess.granted ?? true,
      ),
      child: ScanView(
        title: 'Smart Care',
        subtitle: 'Every check that is built, in one pass, reviewed in one place.',
        idleHeadline: 'Give your Mac a once-over',
        idleMessage:
            'Runs the checks below together and puts everything they find in a '
            'single list. Nothing is removed until you have looked at it.',
        actionLabel: 'Run Smart Care',
        onGrantAccess: fullDiskAccess.openSettings,
        banner: const _CoverageNote(),
      ),
    );
  }
}

/// States plainly which checks ran and which do not exist yet.
class _CoverageNote extends StatelessWidget {
  const _CoverageNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.accentMuted,
              borderRadius: AppRadii.mdAll,
            ),
            child: Icon(AppIcons.info, size: 16, color: colors.accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What this sweep covers', style: context.text.titleS),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final item in SmartCareModule.covered)
                      _Item(label: item, included: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final item in SmartCareModule.notYetCovered)
                      _Item(label: item, included: false),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'The greyed-out checks are not built yet, so this is not a '
                  'clean bill of health — only a clean result for what ran.',
                  style: context.text.bodyS,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.label, required this.included});

  final String label;
  final bool included;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = included ? colors.safe : colors.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(included ? AppIcons.check : AppIcons.close, size: 12, color: tint),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: context.text.bodyS.copyWith(
            color: included ? colors.textSecondary : colors.textMuted,
          ),
        ),
      ],
    );
  }
}
