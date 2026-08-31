import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/scanning/presentation/coverage_note.dart';
import 'package:tidy/core/scanning/presentation/scan_view.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/features/smart_care/data/smart_care_module.dart';

/// The Smart Care module, and the app's only sweep.
///
/// Like every other module page this is [ScanView] pointed at a module, and it
/// reads its `ScanBloc` from the shell rather than creating one, so the sidebar
/// quotes the scan the user is looking at instead of running a second one.
///
/// The two additions are notes: what the sweep does and does not cover, since
/// "Smart Care" sounds comprehensive and right now it is not; and what it
/// deliberately walks past, since a developer who knows their pnpm store is
/// 12 GB deserves to know we saw it and left it alone on purpose.
class SmartCarePage extends StatelessWidget {
  const SmartCarePage({super.key});

  @override
  Widget build(BuildContext context) {
    final fullDiskAccess = locator<FullDiskAccessService>();
    final settings = locator<AppSettings>();

    return ScanView(
      title: 'Smart Care',
      subtitle:
          'Every check that is built, in one pass, reviewed in one place.',
      idleHeadline: 'Give your Mac a once-over',
      idleMessage:
          'Caches, logs, build output from your developer tools, and the apps '
          'you have not opened in months. Everything lands in one list, and '
          'nothing is removed until you have looked at it.',
      actionLabel: 'Run Smart Care',
      onGrantAccess: fullDiskAccess.openSettings,
      banner: Column(
        children: [
          CoverageNote(
            covered: SmartCareModule.covered,
            notYetCovered: SmartCareModule.notYetCovered,
            seen: settings.hasSeenSmartCareCoverage,
            onSeen: settings.markSmartCareCoverageSeen,
            footnote:
                'The pending checks are not built yet, so this is not a clean '
                'bill of health — only a clean result for what ran.',
            gapBelow: true,
          ),
          const _LeftAloneNote(),
        ],
      ),
    );
  }
}

/// Names the caches Tidy deliberately walks past, and what to run instead.
///
/// Every one of these is a place where deleting the folder breaks something
/// that no longer announces itself — a pnpm store the projects hardlink into,
/// the plist that indexes your simulators. Saying so is the honest version of
/// "prefer the tool's own cleanup command", and it is cheaper than a scan that
/// offers an action it cannot safely take.
class _LeftAloneNote extends StatelessWidget {
  const _LeftAloneNote();

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
            alignment: Alignment.center,
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
                Text('What this leaves alone', style: context.text.titleS),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "Tidy does not touch pnpm's store, Docker's disk image, your "
                  'simulator devices or installed SDKs — removing those breaks '
                  'projects that are still using them. Their own commands do '
                  'it safely: pnpm store prune, docker system prune, '
                  'xcrun simctl delete unavailable.',
                  style: context.text.bodyS.copyWith(
                    color: colors.textSecondary,
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
