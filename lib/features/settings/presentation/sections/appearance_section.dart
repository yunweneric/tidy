import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/settings/app_settings.dart';
import 'package:mac_uninstaller/features/settings/presentation/widgets/settings_controls.dart';

class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      children: [
        SettingsChoiceRow<ThemeMode>(
          title: 'Theme',
          detail: 'Follows your macOS appearance unless you pick one.',
          options: const {
            ThemeMode.system: 'System',
            ThemeMode.light: 'Light',
            ThemeMode.dark: 'Dark',
          },
          value: settings.themeMode,
          onChanged: (value) => settings.themeMode = value,
        ),
        SettingsSwitchRow(
          title: 'Reduce motion',
          detail:
              'Turns off the scan animations and counters. Results appear '
              'immediately instead of counting up.',
          value: settings.reduceMotion,
          onChanged: (value) => settings.reduceMotion = value,
        ),
      ],
    );
  }
}
