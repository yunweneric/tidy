import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/platform/full_disk_access_service.dart';
import 'package:mac_uninstaller/core/settings/app_settings.dart';
import 'package:mac_uninstaller/core/widgets/module_scaffold.dart';
import 'package:mac_uninstaller/core/widgets/status_chip.dart';
import 'package:mac_uninstaller/core/widgets/tidy_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.fullDiskAccess,
  });

  final AppSettings settings;
  final FullDiskAccessService fullDiskAccess;

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Settings',
      subtitle: 'Appearance, motion and the permissions ${Brand.name} needs.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            title: 'Appearance',
            child: Column(
              children: [
                _ThemeChoice(settings: settings),
                Divider(height: AppSpacing.xxl, color: context.colors.border),
                _SwitchRow(
                  title: 'Reduce motion',
                  detail:
                      'Turns off the scan animations and counters. Results appear '
                      'immediately instead of counting up.',
                  value: settings.reduceMotion,
                  onChanged: (value) => settings.reduceMotion = value,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Section(
            title: 'Permissions',
            child: _FullDiskAccessRow(service: fullDiskAccess),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Section(
            title: 'About',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${Brand.name} — ${Brand.tagline}', style: context.text.bodyL),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Runs outside the App Sandbox, which is what lets it read '
                  '/Applications and ~/Library at all. Nothing leaves your Mac.',
                  style: context.text.bodyM,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(title.toUpperCase(), style: context.text.overline),
        ),
        TidyCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: child,
        ),
      ],
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    const options = {
      ThemeMode.system: 'System',
      ThemeMode.light: 'Light',
      ThemeMode.dark: 'Dark',
    };

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Theme', style: context.text.titleS),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Follows your macOS appearance unless you pick one.',
                style: context.text.bodyS,
              ),
            ],
          ),
        ),
        SegmentedButton<ThemeMode>(
          segments: [
            for (final entry in options.entries)
              ButtonSegment(value: entry.key, label: Text(entry.value)),
          ],
          selected: {settings.themeMode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => settings.themeMode = selection.first,
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleS),
              const SizedBox(height: AppSpacing.xxs),
              Text(detail, style: context.text.bodyS),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// Explains what Full Disk Access unlocks, shows whether we have it, and links
/// to the pane. There is no API to request it, and the grant only takes effect
/// after a relaunch — both facts have to be on screen or the flow reads broken.
class _FullDiskAccessRow extends StatelessWidget {
  const _FullDiskAccessRow({required this.service});

  final FullDiskAccessService service;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final granted = service.granted;

        return Column(
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
                        'macOS keeps other apps’ data — Mail, Messages, Safari, '
                        'app containers, iOS backups — behind this permission. '
                        'Without it, scans quietly see less than half your disk.',
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
                  'In System Settings, click +, choose ${Brand.name}, then quit '
                  'and reopen it. macOS caches the decision for the lifetime of '
                  'the process, so the change will not take effect until then.',
                  style: context.text.bodyS,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
