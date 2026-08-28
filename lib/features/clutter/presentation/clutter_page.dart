import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/scanning/logic/scan_bloc.dart';
import 'package:tidy/core/scanning/presentation/scan_view.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/features/clutter/data/clutter_module.dart';

/// The My Clutter module.
///
/// Built on the generic [ScanView] like every other module. Like Smart Care, it
/// gets its own `ScanBloc` nested inside the shell's: the shell's `ScanBloc`
/// belongs to Cleanup, and My Clutter is a different scan that must not
/// overwrite it. The only addition over the bare scan view is a note saying what
/// the sweep covers and that duplicates/photos are on the way, so the page never
/// implies it is more thorough than it is.
class ClutterPage extends StatelessWidget {
  const ClutterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fullDiskAccess = locator<FullDiskAccessService>();

    return BlocProvider(
      create:
          (_) => ScanBloc(
            locator<ClutterModule>(),
            hasFullDiskAccess: fullDiskAccess.granted ?? true,
            store: locator<TidyStore>(),
          ),
      child: ScanView(
        title: 'My Clutter',
        subtitle: 'Find duplicates, near-identical photos and forgotten files.',
        idleHeadline: 'Reclaim the files you have forgotten',
        idleMessage:
            'Large files you have not touched in months, and old downloads and '
            'installers still in Downloads. Nothing is removed until you have '
            'looked at it.',
        actionLabel: 'Scan for clutter',
        onGrantAccess: fullDiskAccess.openSettings,
        banner: const _CoverageNote(),
      ),
    );
  }
}

/// States plainly which checks run now and which are still on the way.
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
                    for (final item in ClutterModule.covered)
                      _Item(label: item, included: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final item in ClutterModule.notYetCovered)
                      _Item(label: item, included: false),
                  ],
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
