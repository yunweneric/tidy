import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/settings/app_settings.dart';
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
      banner: const Column(children: [_CoverageNote(), _LeftAloneNote()]),
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

/// States plainly which checks ran and which do not exist yet.
///
/// Shown on the first visit to Smart Care and never again. The information is
/// essential once — "Smart Care" sounds comprehensive and it is not — and it is
/// clutter above every scan after that. The checkbox is for someone who wants
/// it gone before they have finished reading; ticking it and simply leaving the
/// page have the same lasting effect, which is why the checkbox dismisses
/// rather than needing a separate confirm.
class _CoverageNote extends StatefulWidget {
  const _CoverageNote();

  @override
  State<_CoverageNote> createState() => _CoverageNoteState();
}

class _CoverageNoteState extends State<_CoverageNote> {
  final AppSettings _settings = locator<AppSettings>();

  /// Captured once, in initState, rather than read on every build: the visit
  /// is marked seen immediately, and reading the flag live would make the note
  /// vanish out from under whoever is still reading it.
  late final bool _visible = !_settings.hasSeenSmartCareCoverage;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _settings.markSmartCareCoverageSeen();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The gap below belongs to this card rather than to the banner column, so
    // that dismissing it takes its spacing with it.
    if (!_visible || _dismissed) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TidyCard(
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
                  const SizedBox(height: AppSpacing.md),
                  _NeverAgain(
                    onChanged: () => setState(() => _dismissed = true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dismiss control. A checkbox rather than an X, because the question is
/// "should this come back?" and not "close this".
class _NeverAgain extends StatelessWidget {
  const _NeverAgain({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged,
      borderRadius: AppRadii.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 18,
              child: Checkbox(value: false, onChanged: (_) => onChanged()),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text("Don't show this again", style: context.text.bodyS),
          ],
        ),
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
