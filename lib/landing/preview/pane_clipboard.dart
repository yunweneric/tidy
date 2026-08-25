import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/preview/preview_chrome.dart';
import 'package:tidy/landing/preview/preview_mac.dart';

/// Everything you have copied, and a way back to any of it.
class PreviewClipboardPane extends StatelessWidget {
  const PreviewClipboardPane({super.key, required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Pinned first, then newest — the order the real history keeps.
    final clips = [
      ...mac.clips.where((clip) => clip.pinned),
      ...mac.clips.where((clip) => !clip.pinned),
    ];

    return ModuleScaffold(
      title: PreviewScreen.clipboard.label,
      subtitle: PreviewScreen.clipboard.blurb,
      actions: [
        SizedBox(
          width: 220,
          child: AppSearchField(hintText: 'Search history…', onChanged: (_) {}),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TidyCard(
                  child: Row(
                    children: [
                      StatIconTile(
                        icon: AppIcons.clipboard,
                        color: colors.accent,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          // The part of the feature worth advertising: it asks
                          // for no Accessibility permission and only hears one
                          // combination.
                          'Press ⌘⇧V anywhere to open the history. The hotkey '
                          'is registered with Carbon, so it needs no '
                          'Accessibility permission and hears nothing else '
                          'you type.',
                          style: context.text.bodyM,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          PreviewTable(
            header: const PreviewTableHeader(
              cells: [(9, 'Content'), (3, 'From'), (3, 'When'), (2, '')],
            ),
            rows: [
              for (var i = 0; i < clips.length; i++)
                _ClipRow(mac: mac, clip: clips[i], last: i == clips.length - 1),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(AppIcons.privacy, size: 14, color: colors.textMuted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Password-manager copies are skipped outright. Anything '
                  'key- or card-shaped is masked before it is stored, and can '
                  'be dropped rather than kept. History is held for 7 days by '
                  'default and never leaves this Mac.',
                  style: context.text.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClipRow extends StatelessWidget {
  const _ClipRow({required this.mac, required this.clip, required this.last});

  final PreviewMac mac;
  final PreviewClip clip;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (icon, tone) = switch (clip.kind) {
      PreviewClipKind.link => (AppIcons.link, colors.info),
      PreviewClipKind.image => (AppIcons.image, colors.upstream),
      PreviewClipKind.file => (AppIcons.folder, colors.review),
      PreviewClipKind.text => (AppIcons.plainText, colors.textMuted),
    };

    return PreviewRow(
      last: last,
      onTap: () => mac.togglePin(clip),
      child: Row(
        children: [
          Expanded(
            flex: 9,
            child: Row(
              children: [
                Icon(icon, size: 15, color: tone),
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Text(
                    clip.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        clip.kind == PreviewClipKind.text && !clip.masked
                            ? context.text.bodyL.copyWith(
                              color: colors.textPrimary,
                            )
                            : context.text.mono.copyWith(fontSize: 13),
                  ),
                ),
                if (clip.masked) ...[
                  const SizedBox(width: AppSpacing.md),
                  StatusChip(
                    label: 'Masked',
                    color: colors.risky,
                    icon: AppIcons.locked,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(clip.source, style: context.text.bodyM),
          ),
          Expanded(flex: 3, child: Text(clip.age, style: context.text.caption)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(
                clip.pinned ? AppIcons.pin : AppIcons.unpin,
                size: 16,
                color: clip.pinned ? colors.accent : colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
