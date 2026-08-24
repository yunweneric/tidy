import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/features/clipboard/data/models/clipboard_prefs.dart';
import 'package:tidy/features/clipboard/data/services/clipboard_service.dart';
import 'package:tidy/features/settings/presentation/widgets/settings_controls.dart';

/// Everything that governs the clipboard recorder.
///
/// The Clipboard page carries the two limits people reach for while looking at
/// a full history; this is the whole set, split by the question each answers —
/// what gets written down, and how long it stays.
class ClipboardSection extends StatelessWidget {
  const ClipboardSection({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final on = settings.clipboardEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Leads with what it stores and where. Someone deciding whether to
        // turn this on is deciding about a file of everything they copy, and
        // that should not be something they have to work out.
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
                  'The history is kept on this Mac only, in an unencrypted '
                  'file in your Application Support folder. Nothing is sent '
                  'anywhere. Copies from password managers are never recorded.',
                  style: context.text.bodyM,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'Recording',
          children: [
            SettingsSwitchRow(
              title: 'Record what I copy',
              detail:
                  'Keeps text, links, images and files you copy, so you can '
                  'get any of them back later.',
              value: on,
              onChanged: (value) => settings.clipboardEnabled = value,
            ),
            SettingsSwitchRow(
              title: 'Include images',
              detail:
                  'Screenshots and copied pictures are stored as files. They '
                  'are the only part of the history big enough to notice on '
                  'disk.',
              value: settings.clipboardCaptureImages,
              enabled: on,
              onChanged: (value) => settings.clipboardCaptureImages = value,
            ),
            SettingsSwitchRow(
              title: 'Keep items that look like secrets',
              detail:
                  'Off means API keys, private keys and card numbers are never '
                  'written to disk at all. On means they are kept but hidden '
                  'in the list until you reveal them.',
              value: settings.clipboardStoreSensitive,
              enabled: on,
              onChanged: (value) => settings.clipboardStoreSensitive = value,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroup(
          title: 'History',
          children: [
            SettingsChoiceRow<int>(
              title: 'Keep the last',
              detail:
                  'Older items drop off as new ones arrive. Pinned items do '
                  'not count towards this and are never dropped.',
              options: {for (final size in clipboardHistorySizes) size: '$size'},
              value: clipboardHistorySizes.contains(settings.clipboardMaxItems)
                  ? settings.clipboardMaxItems
                  : clipboardHistorySizes[1],
              enabled: on,
              onChanged: (value) => settings.clipboardMaxItems = value,
            ),
            SettingsChoiceRow<ClipboardRetention>(
              title: 'Clear items after',
              detail:
                  'Anything older than this goes, whether or not the history '
                  'is full. Pinned items stay.',
              options: {
                for (final retention in ClipboardRetention.values)
                  retention: retention.label,
              },
              value: settings.clipboardRetention,
              enabled: on,
              onChanged: (value) => settings.clipboardRetention = value,
            ),
            SettingsSwitchRow(
              title: 'Clear the history when I quit',
              detail:
                  'Everything except pinned items is removed when ${Brand.name} '
                  'closes.',
              value: settings.clipboardClearOnQuit,
              enabled: on,
              onChanged: (value) => settings.clipboardClearOnQuit = value,
            ),
            SettingsActionRow(
              title: 'Clear the history now',
              detail:
                  'Removes everything except pinned items, and the images and '
                  'files stored with them.',
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
      title: 'Clear the clipboard history?',
      message:
          'This removes everything except your pinned items, along with the '
          'images and files stored with them. It cannot be undone.',
      confirmLabel: 'Clear History',
      tone: FeedbackTone.danger,
      icon: AppIcons.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    await locator<ClipboardService>().clear(keepPinned: true);
    if (!context.mounted) return;
    context.toastSuccess('Clipboard history cleared.');
  }
}
