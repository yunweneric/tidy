import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/scanning/presentation/scan_view.dart';
import 'package:tidy/core/widgets/tidy_card.dart';

/// The Cleanup module.
///
/// Almost nothing here: the page is the generic [ScanView] pointed at a module,
/// reading its `ScanBloc` from the shell above so the sidebar can show the same
/// reclaimable figure without running a second scan. That is the payoff of the
/// scan contract — every module from here on is a data source plus some copy.
class CleanupPage extends StatelessWidget {
  const CleanupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScanView(
      title: 'Cleanup',
      subtitle: 'Reclaim space macOS and your tools will rebuild on their own.',
      idleHeadline: 'Find space you can get back',
      idleMessage:
          'Caches, logs, window-restore data and the build output your '
          'developer tools leave behind. None of it is your work — the things '
          'that made it will make it again.',
      actionLabel: 'Scan for junk',
      onGrantAccess: locator<FullDiskAccessService>().openSettings,
      banner: const _LeftAloneNote(),
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
