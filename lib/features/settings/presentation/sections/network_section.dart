import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/features/network/data/models/network_prefs.dart';
import 'package:tidy/features/network/data/models/network_units.dart';
import 'package:tidy/features/network/data/services/network_service.dart';
import 'package:tidy/features/settings/presentation/widgets/settings_controls.dart';

/// Everything that governs the network readout and its history.
class NetworkSection extends StatelessWidget {
  const NetworkSection({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final inMenuBar = settings.networkMenuBarEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Says what is and is not recorded up front. A monitor that watches
        // traffic sounds like one that watches *what* you send, and the honest
        // answer — it counts bytes per interface and nothing else — is better
        // stated than left to be assumed.
        TidyCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.info,
                size: 17,
                color: context.colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '${Brand.name} counts the bytes each network interface has '
                  'moved. It cannot see what was sent, which sites were '
                  'visited, or which app was responsible — and it needs no '
                  'permission to read any of it. Totals are recorded only '
                  'while ${Brand.name} is running.',
                  style: context.text.bodyM,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'Menu bar',
          children: [
            SettingsSwitchRow(
              title: 'Show the live readout',
              detail:
                  'A running download and upload rate in the menu bar. '
                  'Turning it off gives the space back; the history keeps '
                  'recording either way.',
              value: inMenuBar,
              onChanged: (value) => settings.networkMenuBarEnabled = value,
            ),
            SettingsChoiceRow<NetworkMenuBarStyle>(
              title: 'Style',
              detail: settings.networkMenuBarStyle.blurb,
              options: {
                for (final style in NetworkMenuBarStyle.values)
                  style: style.label,
              },
              value: settings.networkMenuBarStyle,
              enabled: inMenuBar,
              onChanged: (value) => settings.networkMenuBarStyle = value,
            ),
            SettingsChoiceRow<NetworkUnits>(
              title: 'Measure rates in',
              detail:
                  'Bytes match the rest of the app. Bits match what an '
                  'internet plan and a speed test quote. Totals stay in bytes '
                  'either way — nobody measures a month in gigabits.',
              options: {
                for (final units in NetworkUnits.values) units: units.label,
              },
              value: settings.networkUnits,
              onChanged: (value) => settings.networkUnits = value,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'History',
          children: [
            SettingsLabel(
              title: 'What is kept',
              detail:
                  'Minute by minute for two days, hour by hour for three '
                  'months, and a daily total that is never deleted. About a '
                  'quarter of a megabyte in total, whatever happens.',
            ),
            SettingsActionRow(
              title: 'Clear the usage history',
              detail:
                  'Removes every recorded total. The charts start again from '
                  'now.',
              actionLabel: 'Clear History',
              destructive: true,
              onPressed: () => _confirmClear(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await TidyAlert.confirm(
      context,
      title: 'Clear the usage history?',
      message:
          'This removes every recorded total, including the daily figures kept '
          'since ${Brand.name} was installed. It cannot be undone.',
      confirmLabel: 'Clear History',
      tone: FeedbackTone.danger,
      icon: AppIcons.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final outcome = await locator<NetworkService>().reset();
    if (!context.mounted) return;
    if (outcome.ok) {
      context.toastSuccess('Usage history cleared.');
    } else {
      context.toastError(outcome.message ?? 'That could not be cleared.');
    }
  }
}
