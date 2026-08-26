import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/platform/app_data_access_service.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/widgets/status_chip.dart';
import 'package:tidy/core/widgets/tidy_card.dart';

/// The two grants Tidy needs, what each unlocks, and what can be done about
/// them.
///
/// They behave differently and the screen has to reflect that: Full Disk Access
/// cannot be requested at all and only takes effect after a relaunch, while
/// other apps' data is requested by *using* it — macOS shows its own dialog on
/// the first read. Flattening the two into one "grant permissions" button would
/// be wrong about both.
class PermissionsSection extends StatelessWidget {
  const PermissionsSection({
    super.key,
    required this.service,
    required this.appData,
  });

  final FullDiskAccessService service;
  final AppDataAccessService appData;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([service, appData]),
      builder:
          (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FullDisk(service: service),
              const SizedBox(height: AppSpacing.lg),
              _AppData(service: appData),
            ],
          ),
    );
  }
}

class _FullDisk extends StatelessWidget {
  const _FullDisk({required this.service});

  final FullDiskAccessService service;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final granted = service.granted;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Full Disk Access', style: context.text.titleS),
                        const SizedBox(width: AppSpacing.sm),
                        if (granted == true)
                          StatusChip(
                            label: 'Granted',
                            color: colors.safe,
                            icon: AppIcons.safe,
                          )
                        else if (granted == false)
                          StatusChip(
                            label: 'Not granted',
                            color: colors.review,
                            icon: AppIcons.locked,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'macOS keeps other apps’ data — Mail, Messages, '
                      'Safari, app containers, iOS backups — behind this '
                      'permission. Without it, scans quietly see less than '
                      'half your disk.',
                      style: context.text.bodyS,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Column(
                children: [
                  OutlinedButton(
                    onPressed: service.openSettings,
                    child: const Text('Open Settings'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: service.isChecking ? null : service.refresh,
                    child: const Text('Re-check'),
                  ),
                ],
              ),
            ],
          ),
          if (granted == false) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: AppRadii.mdAll,
              ),
              child: Text(
                'In System Settings, click +, choose ${Brand.name}, then '
                'quit and reopen it. macOS caches the decision for the '
                'lifetime of the process, so the change will not take '
                'effect until then.',
                style: context.text.bodyS,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Other apps' data — the one grant that can actually be asked for.
class _AppData extends StatefulWidget {
  const _AppData({required this.service});

  final AppDataAccessService service;

  @override
  State<_AppData> createState() => _AppDataState();
}

class _AppDataState extends State<_AppData> {
  @override
  void initState() {
    super.initState();
    // After the frame rather than during it. This card is built inside the
    // `AnimatedBuilder` that listens to the same service, and `refresh` sets
    // `isChecking` and notifies before it reaches its first `await` — so
    // calling it here notifies a listener that is *currently building*, which
    // is an assertion in debug and a dropped rebuild in release.
    //
    // Only ever fired once the question has already been put to macOS, which
    // is why it went unseen for so long: until then `refresh` returns without
    // touching anything.
    //
    // Silent either way: a no-op until macOS has already been asked, because
    // the probe is the request. Opening this tab must not be what springs the
    // dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.service.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final colors = context.colors;
    final granted = service.granted;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Other apps’ data', style: context.text.titleS),
                        const SizedBox(width: AppSpacing.sm),
                        if (granted == true)
                          StatusChip(
                            label: 'Granted',
                            color: colors.safe,
                            icon: AppIcons.safe,
                          )
                        else if (granted == false)
                          StatusChip(
                            label: 'Not granted',
                            color: colors.review,
                            icon: AppIcons.locked,
                          )
                        else
                          StatusChip(
                            label: 'Not asked yet',
                            color: colors.textMuted,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Sonoma split this out of Full Disk Access: reading '
                      'inside another app’s container needs its own grant, and '
                      'macOS asks for it the first time ${Brand.name} looks. A '
                      'good deal of cache and leftover data lives in there.',
                      style: context.text.bodyS,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Column(
                children: [
                  if (!service.hasBeenAsked)
                    OutlinedButton(
                      onPressed: service.isChecking ? null : service.request,
                      child: const Text('Ask macOS'),
                    )
                  else ...[
                    OutlinedButton(
                      onPressed: service.openSettings,
                      child: const Text('Open Settings'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextButton(
                      onPressed: service.isChecking ? null : service.refresh,
                      child: const Text('Re-check'),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (service.hasBeenAsked && granted == false) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: AppRadii.mdAll,
              ),
              child: Text(
                'macOS only asks once. To change the answer, find ${Brand.name} '
                'under Privacy & Security → Files and Folders — not under Full '
                'Disk Access, which is where most people look for it.',
                style: context.text.bodyS,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
