import 'package:flutter/material.dart';
import 'package:tidy/features/settings/presentation/sections/ai_usage_section.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/widgets/fade_through.dart';
import 'package:tidy/core/widgets/module_scaffold.dart';
import 'package:tidy/features/settings/domain/settings_section.dart';
import 'package:tidy/features/settings/presentation/sections/about_section.dart';
import 'package:tidy/features/settings/presentation/sections/appearance_section.dart';
import 'package:tidy/features/settings/presentation/sections/clipboard_section.dart';
import 'package:tidy/features/settings/presentation/sections/general_section.dart';
import 'package:tidy/features/settings/presentation/sections/history_section.dart';
import 'package:tidy/features/settings/presentation/sections/network_section.dart';
import 'package:tidy/features/settings/presentation/sections/permissions_section.dart';
import 'package:tidy/features/settings/presentation/sections/updates_section.dart';
import 'package:tidy/features/settings/presentation/widgets/settings_rail.dart';

/// Settings, as two panes: the sections down the left, the chosen one's
/// controls on the right.
///
/// One scrolling column put the clipboard's nine rows between the theme picker
/// and the permission everything else depends on, so both ends of the page
/// were reachable only by scrolling past a feature you might not use. The tabs
/// are the same settings, addressed rather than scrolled.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.initialSection = SettingsSection.initial,
  });

  /// Which tab to open on. Comes from `?section=` on the route, so a toast or a
  /// menu item can point at one setting rather than at Settings in general.
  final SettingsSection initialSection;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsSection _section = widget.initialSection;

  /// One controller for the detail pane, reset on every tab change: keeping a
  /// tall section's scroll offset while showing a short one leaves the new
  /// section scrolled past its own top.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _select(SettingsSection section) {
    if (section == _section) return;
    setState(() => _section = section);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final settings = locator<AppSettings>();

    return ModuleScaffold(
      title: 'Settings',
      subtitle:
          'Appearance, the clipboard history and the permissions '
          '${Brand.name} needs.',
      scrollable: false,
      // Stretch, not start: the detail pane is a scroll view, and a Row that
      // sizes its children to their own height hands it unbounded constraints.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsRail(current: _section, onSelect: _select),
          const SizedBox(width: AppSpacing.xxl),
          Expanded(
            child: FadeThrough(
              trigger: _section,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionHeading(section: _section),
                    const SizedBox(height: AppSpacing.lg),
                    _body(settings),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(AppSettings settings) => switch (_section) {
    SettingsSection.general => GeneralSection(settings: settings),
    SettingsSection.appearance => AppearanceSection(settings: settings),
    SettingsSection.clipboard => ClipboardSection(settings: settings),
    SettingsSection.network => NetworkSection(settings: settings),
    SettingsSection.aiUsage => AiUsageSection(settings: settings),
    SettingsSection.history => const HistorySection(),
    SettingsSection.permissions => PermissionsSection(
      service: locator<FullDiskAccessService>(),
    ),
    SettingsSection.updates => UpdatesSection(settings: settings),
    SettingsSection.about => const AboutSection(),
  };
}

/// Names the pane you are looking at. The page header says "Settings" for all
/// five sections, so without this the right-hand column is unlabelled.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.label, style: context.text.titleM),
        const SizedBox(height: AppSpacing.xxs),
        Text(section.blurb, style: context.text.bodyM),
      ],
    );
  }
}
