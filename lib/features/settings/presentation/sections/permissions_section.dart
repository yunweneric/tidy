import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/platform/full_disk_access_service.dart';
import 'package:mac_uninstaller/core/widgets/status_chip.dart';
import 'package:mac_uninstaller/core/widgets/tidy_card.dart';

/// Explains what Full Disk Access unlocks, shows whether we have it, and links
/// to the pane. There is no API to request it, and the grant only takes effect
/// after a relaunch — both facts have to be on screen or the flow reads broken.
class PermissionsSection extends StatelessWidget {
  const PermissionsSection({super.key, required this.service});

  final FullDiskAccessService service;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
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
                            Text(
                              'Full Disk Access',
                              style: context.text.titleS,
                            ),
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
      },
    );
  }
}
