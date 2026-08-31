import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/size_bar.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/features/space_lens/data/models/space_level.dart';

/// Everything in the folder, biggest first, exactly.
///
/// The map is the reading and this is the record. The map caps itself at forty
/// bubbles and clamps the smallest of them to a size the eye can find, so it is
/// approximate at the bottom by design — this list is where nothing is rounded,
/// gathered or left out, and it is why the map is allowed to simplify.
class SpaceEntryList extends StatelessWidget {
  const SpaceEntryList({
    super.key,
    required this.level,
    required this.onSelect,
    required this.onOpen,
    this.selectedPath,
  });

  final SpaceLevel? level;
  final String? selectedPath;
  final ValueChanged<SpaceEntry> onSelect;
  final ValueChanged<SpaceEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final level = this.level;

    return TidyCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child:
          level == null || level.isEmpty
              ? const SizedBox.shrink()
              : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xs,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      'EVERYTHING IN HERE',
                      style: context.text.overline.copyWith(
                        color: context.colors.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: level.entries.length,
                      itemBuilder: (context, index) {
                        final entry = level.entries[index];
                        return _Row(
                          entry: entry,
                          fraction:
                              level.totalBytes == 0
                                  ? 0
                                  : entry.sizeBytes / level.totalBytes,
                          selected: entry.path == selectedPath,
                          onTap: () => onSelect(entry),
                          onDoubleTap:
                              entry.isDrillable ? () => onOpen(entry) : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.fraction,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
  });

  final SpaceEntry entry;
  final double fraction;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        color: selected ? colors.surfaceHover : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm - 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  entry.icon,
                  size: 14,
                  color:
                      entry.isDirectory
                          ? colors.textSecondary
                          : colors.textMuted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyM.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  formatBytes(entry.sizeBytes),
                  style: context.text.label.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SizeBar(fraction: fraction, height: 3),
          ],
        ),
      ),
    );
  }
}
