import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/outline_action_button.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/features/space_lens/data/models/space_level.dart';

/// What is selected, and the two things that can be done about it.
///
/// With nothing selected it describes the folder on screen instead of
/// collapsing, so the column beside the map keeps its shape while you click
/// around it rather than jumping every time something is picked or dropped.
class SpaceSelectionCard extends StatelessWidget {
  const SpaceSelectionCard({
    super.key,
    required this.entry,
    required this.level,
    required this.busy,
    required this.onOpen,
    required this.onReveal,
    required this.onTrash,
    required this.short,
  });

  final SpaceEntry? entry;
  final SpaceLevel? level;
  final bool busy;
  final ValueChanged<SpaceEntry> onOpen;
  final ValueChanged<SpaceEntry> onReveal;
  final ValueChanged<SpaceEntry> onTrash;
  final String Function(String path) short;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child:
          entry == null
              ? _Folder(level: level, short: short)
              : _Selected(
                entry: entry,
                level: level,
                busy: busy,
                onOpen: onOpen,
                onReveal: onReveal,
                onTrash: onTrash,
                short: short,
              ),
    );
  }
}

class _Folder extends StatelessWidget {
  const _Folder({required this.level, required this.short});

  final SpaceLevel? level;
  final String Function(String path) short;

  @override
  Widget build(BuildContext context) {
    final level = this.level;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'THIS FOLDER',
          style: context.text.overline.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          level == null ? '—' : short(level.path),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.titleS.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          level == null
              ? 'Nothing measured yet.'
              : 'Measured ${_ago(level.measuredAt)}. Pick a bubble to see what '
                  'it is.',
          style: context.text.bodyS,
        ),
        if (level != null && level.unreadable > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            // A hole in the map, said out loud. A total that quietly leaves out
            // what it could not read is the same class of wrong as a scanner
            // reporting nothing found because it never looked.
            'macOS would not let Tidy read part of this folder, so the total '
            'is a floor rather than the whole of it.',
            style: context.text.caption.copyWith(color: colors.review),
          ),
        ],
      ],
    );
  }
}

class _Selected extends StatelessWidget {
  const _Selected({
    required this.entry,
    required this.level,
    required this.busy,
    required this.onOpen,
    required this.onReveal,
    required this.onTrash,
    required this.short,
  });

  final SpaceEntry entry;
  final SpaceLevel? level;
  final bool busy;
  final ValueChanged<SpaceEntry> onOpen;
  final ValueChanged<SpaceEntry> onReveal;
  final ValueChanged<SpaceEntry> onTrash;
  final String Function(String path) short;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = level?.totalBytes ?? 0;
    final share = total == 0 ? 0.0 : entry.sizeBytes / total;

    // The gathered bubble is a count, not a thing. It has no path to reveal and
    // nothing to move to the Trash, so it says what it stands for and stops.
    if (entry.isGroup) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GATHERED',
            style: context.text.overline.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            entry.name,
            style: context.text.titleS.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${formatBytes(entry.sizeBytes)} between them — too small to draw '
            'apart. They are listed in full below.',
            style: context.text.bodyS,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(entry.icon, size: 16, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleS.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          short(entry.path),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatBytes(entry.sizeBytes),
              style: context.text.titleL.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${(share * 100).toStringAsFixed(share < 1 ? 1 : 0)}% of this '
                'folder',
                style: context.text.caption,
              ),
            ),
          ],
        ),
        if (entry.modified != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text('Changed ${_ago(entry.modified!)}', style: context.text.caption),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (entry.isDrillable)
              OutlineActionButton(
                icon: AppIcons.folder,
                label: 'Open',
                onPressed: busy ? null : () => onOpen(entry),
              ),
            OutlineActionButton(
              icon: AppIcons.revealInFinder,
              label: 'Reveal',
              onPressed: busy ? null : () => onReveal(entry),
            ),
            OutlineActionButton(
              icon: AppIcons.delete,
              label: 'Move to Trash',
              onPressed: busy ? null : () => onTrash(entry),
            ),
          ],
        ),
      ],
    );
  }
}

/// Rough, and rough on purpose: the exact minute a folder was measured is never
/// the question, and "3 minutes ago" answers the one that is — whether this is
/// still a picture of the disk you are looking at.
String _ago(DateTime at) {
  final gap = DateTime.now().difference(at);
  if (gap.inSeconds < 45) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  if (gap.inHours < 24) return '${gap.inHours}h ago';
  return '${gap.inDays}d ago';
}
