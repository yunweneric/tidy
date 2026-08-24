import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/clipboard/data/models/clipboard_prefs.dart';

/// The two limits that govern this page, stated on it.
///
/// The full set lives in Settings; these two are here because they are the ones
/// someone looking at a full history wants to change, and sending them to
/// another page to find out why an item vanished is a poor answer.
class ClipboardQuickSettings extends StatelessWidget {
  const ClipboardQuickSettings({
    super.key,
    required this.settings,
    required this.entryCount,
    required this.pinnedCount,
    required this.onClear,
    required this.onOpenSettings,
  });

  final AppSettings settings;
  final int entryCount;
  final int pinnedCount;
  final VoidCallback onClear;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final retention = settings.clipboardRetention;

    // The sentence and the buttons must not disagree. Only the presets are
    // reachable through the UI, but a hand-edited settings file can hold
    // anything, and a strip reading "keeping the last 137" over a highlighted
    // 200 tells the user nothing they can act on.
    final limit =
        clipboardHistorySizes.contains(settings.clipboardMaxItems)
            ? settings.clipboardMaxItems
            : clipboardHistorySizes[1];

    return TidyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(AppIcons.clipboard, size: 17, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: context.text.bodyM,
                children: [
                  TextSpan(
                    text: '$entryCount item${entryCount == 1 ? '' : 's'}',
                    style: context.text.bodyM.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (pinnedCount > 0) TextSpan(text: ', $pinnedCount pinned'),
                  TextSpan(text: ' · keeping the last $limit'),
                  TextSpan(
                    text:
                        retention == ClipboardRetention.never
                            ? ' · kept until you clear it'
                            : ' · clearing after ${retention.label.toLowerCase()}',
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _Limit(
            value: limit,
            onChanged: (value) => settings.clipboardMaxItems = value,
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton.icon(
            onPressed: onOpenSettings,
            icon: const Icon(AppIcons.settings, size: 15),
            label: const Text('More'),
          ),
          TextButton.icon(
            onPressed: entryCount == 0 ? null : onClear,
            icon: const Icon(AppIcons.delete, size: 15),
            label: const Text('Clear now'),
            style: TextButton.styleFrom(foregroundColor: colors.risky),
          ),
        ],
      ),
    );
  }
}

/// Presets rather than a number field. The size of a history is a rough
/// preference, not a measurement, and a free-form box invites picking 137.
class _Limit extends StatelessWidget {
  const _Limit({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final size in clipboardHistorySizes)
          ButtonSegment(value: size, label: Text('$size')),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
