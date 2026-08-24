import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/scanning/domain/scan_node.dart';
import 'package:mac_uninstaller/core/scanning/domain/scan_selection.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/widgets/size_bar.dart';
import 'package:mac_uninstaller/core/widgets/status_chip.dart';
import 'package:mac_uninstaller/core/widgets/tidy_card.dart';

/// The results grid: one tile per category, each with a headline number, a
/// plain-language line, and a way in.
///
/// This is the piece that decides whether a cleaner feels calm or alarming.
/// Dropping a user straight into a list of four thousand cache paths is
/// technically more informative and practically useless; a tile that says
/// "4.2 GB of caches your apps will rebuild" is what they can actually act on.
class ResultTiles extends StatelessWidget {
  const ResultTiles({
    super.key,
    required this.roots,
    required this.selection,
    required this.onReview,
    required this.onToggle,
  });

  final List<ScanNode> roots;
  final ScanSelection selection;
  final ValueChanged<ScanNode> onReview;
  final void Function(ScanNode node, bool select) onToggle;

  @override
  Widget build(BuildContext context) {
    final largest = roots.fold<int>(
      0,
      (max, node) => node.totalBytes > max ? node.totalBytes : max,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Tiles want ~300px to fit a headline number and a line of prose
        // without wrapping awkwardly.
        final columns = (constraints.maxWidth / 300).floor().clamp(1, 4);
        const gap = AppSpacing.lg;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final node in roots)
              SizedBox(
                width: tileWidth,
                child: _ResultTile(
                  node: node,
                  fractionOfLargest: largest == 0 ? 0 : node.totalBytes / largest,
                  state: selection.stateOf(node),
                  onReview: () => onReview(node),
                  onToggle: (select) => onToggle(node, select),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.node,
    required this.fractionOfLargest,
    required this.state,
    required this.onReview,
    required this.onToggle,
  });

  final ScanNode node;
  final double fractionOfLargest;
  final bool? state;
  final VoidCallback onReview;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final safety = node.effectiveSafety;
    final accent = switch (safety) {
      SafetyLevel.safe => colors.safe,
      SafetyLevel.review => colors.review,
      SafetyLevel.risky => colors.risky,
    };

    return TidyCard(
      onTap: onReview,
      selected: state != false,
      accent: accent,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.title,
                  style: context.text.titleS,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: state,
                  tristate: true,
                  onChanged: (_) => onToggle(state != true),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            formatBytes(node.totalBytes),
            style: context.text.displayL.copyWith(color: accent),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizeBar(fraction: fractionOfLargest, color: accent, height: 4),
          const SizedBox(height: AppSpacing.md),
          Text(
            node.detail ?? node.subtitle ?? '',
            style: context.text.bodyS,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              StatusChip.safety(safety, context),
              const Spacer(),
              Text(
                '${node.leafCount} item${node.leafCount == 1 ? '' : 's'}',
                style: context.text.caption,
              ),
            ],
          ),
          if (node.containsAdminItems) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(AppIcons.locked, size: 12, color: colors.textMuted),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Some items need an administrator',
                    style: context.text.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
