import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/features/settings/presentation/widgets/settings_controls.dart';

/// What happens when the Mac starts, and when the app opens.
///
/// Stateful for the login item alone. macOS owns that switch — the user can
/// turn it off in System Settings → General → Login Items without telling us —
/// so a stored mirror would drift and then lie. It reads `SMAppService` every
/// time the section opens and writes nothing to the settings file.
class GeneralSection extends StatefulWidget {
  const GeneralSection({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<GeneralSection> createState() => _GeneralSectionState();
}

class _GeneralSectionState extends State<GeneralSection> {
  bool _available = false;
  bool _enabled = false;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final status = await SystemBridge.loginItemStatus();
    if (!mounted) return;
    setState(() {
      _available = status.available;
      _enabled = status.enabled;
      _busy = false;
    });
  }

  Future<void> _setLoginItem(bool value) async {
    setState(() => _busy = true);
    final outcome = await SystemBridge.setLoginItem(enabled: value);
    if (!mounted) return;

    if (!outcome.ok) {
      setState(() => _busy = false);
      context.toastWarning(outcome.message ?? 'macOS would not change that.');
      return;
    }
    setState(() {
      _enabled = value;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      children: [
        // Dropped entirely on macOS 11 and 12, where `SMAppService` does not
        // exist: there is nothing the user can do about their OS version, so a
        // greyed-out row with an explanation would be a dead end.
        if (_available || _busy)
          SettingsSwitchRow(
            title: 'Start ${Brand.name} at login',
            detail:
                'Starts with your Mac and sits in the menu bar. The clipboard '
                'only records while ${Brand.name} is running.',
            value: _enabled,
            enabled: !_busy,
            onChanged: _setLoginItem,
          ),
        SettingsActionRow(
          title: 'Show the intro again',
          detail:
              'Replays the first-run walkthrough, including the permission '
              'step, next time you open ${Brand.name}.',
          actionLabel: 'Replay intro',
          onPressed: widget.settings.resetOnboarding,
        ),
      ],
    );
  }
}
