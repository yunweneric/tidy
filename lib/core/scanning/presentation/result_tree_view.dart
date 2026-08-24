import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/core/scanning/domain/scan_selection.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/size_bar.dart';
import 'package:tidy/core/widgets/status_chip.dart';

/// The drill-down: an expandable, checkable tree over a [ScanNode].
///
/// One widget for every module. It renders whatever depth a scanner returns, so
/// a flat list of caches and a three-level Xcode breakdown both work without a
/// bespoke screen.
class ResultTreeView extends StatelessWidget {
  const ResultTreeView({
    super.key,
    required this.node,
    required this.selection,
    required this.onToggle,
    this.initiallyExpandedDepth = 1,
  });

  final ScanNode node;
  final ScanSelection selection;
  final void Function(ScanNode node, bool select) onToggle;

  /// How many levels open by default. One means categories show their contents
  /// but deep trees stay collapsed.
  final int initiallyExpandedDepth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.surfaceGradient,
        ),
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in node.children)
            _TreeRow(
              node: child,
              parentBytes: node.totalBytes,
              depth: 0,
              selection: selection,
              onToggle: onToggle,
              expandedDepth: initiallyExpandedDepth,
            ),
          if (node.children.isEmpty)
            _TreeRow(
              node: node,
              parentBytes: node.totalBytes,
              depth: 0,
              selection: selection,
              onToggle: onToggle,
              expandedDepth: initiallyExpandedDepth,
            ),
        ],
      ),
    );
  }
}

class _TreeRow extends StatefulWidget {
  const _TreeRow({
    required this.node,
    required this.parentBytes,
    required this.depth,
    required this.selection,
    required this.onToggle,
    required this.expandedDepth,
  });

  final ScanNode node;
  final int parentBytes;
  final int depth;
  final ScanSelection selection;
  final void Function(ScanNode node, bool select) onToggle;
  final int expandedDepth;

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  late bool _expanded = widget.depth < widget.expandedDepth;
  bool _hovered = false;

  /// Long tails are noise. Show the biggest few, then offer the rest.
  static const int _initialChildLimit = 8;
  bool _showAllChildren = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final node = widget.node;
    final state = widget.selection.stateOf(node);
    final fraction =
        widget.parentBytes == 0 ? 0.0 : node.totalBytes / widget.parentBytes;

    final blocked = node.isLeaf && !node.isRemovable;
    final visibleChildren =
        _showAllChildren
            ? node.children
            : node.children.take(_initialChildLimit).toList();
    final hiddenCount = node.children.length - visibleChildren.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap:
                node.isLeaf
                    ? null
                    : () => setState(() => _expanded = !_expanded),
            child: Container(
              color: _hovered ? colors.surfaceHover : Colors.transparent,
              padding: EdgeInsets.only(
                left: AppSpacing.md + widget.depth * AppSpacing.xl,
                right: AppSpacing.lg,
                top: AppSpacing.sm,
                bottom: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child:
                        node.isLeaf
                            ? null
                            : Icon(
                              _expanded ? AppIcons.expand : AppIcons.collapse,
                              size: 18,
                              color: colors.textMuted,
                            ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Checkbox(
                      value: blocked ? false : state,
                      tristate: !node.isLeaf,
                      onChanged:
                          blocked
                              ? null
                              : (_) => widget.onToggle(node, state != true),
                    ),
                  ),
                  Expanded(child: _title(context, node, blocked)),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 60,
                    child: SizeBar(fraction: fraction, height: 4),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 78,
                    child: Text(
                      formatBytes(node.totalBytes),
                      textAlign: TextAlign.right,
                      style: context.text.bodyM.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child:
                        _hovered && node.paths.isNotEmpty
                            ? IconButton(
                              icon: const Icon(
                                AppIcons.revealInFinder,
                                size: 15,
                              ),
                              color: colors.textMuted,
                              tooltip: 'Reveal in Finder',
                              visualDensity: VisualDensity.compact,
                              onPressed:
                                  () => SystemBridge.revealInFinder(
                                    node.paths.first,
                                  ),
                            )
                            : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded && node.children.isNotEmpty) ...[
          for (final child in visibleChildren)
            _TreeRow(
              node: child,
              parentBytes: node.totalBytes,
              depth: widget.depth + 1,
              selection: widget.selection,
              onToggle: widget.onToggle,
              expandedDepth: widget.expandedDepth,
            ),
          if (hiddenCount > 0)
            Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.huge + widget.depth * AppSpacing.xl,
                bottom: AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showAllChildren = true),
                  child: Text('Show $hiddenCount more'),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _title(BuildContext context, ScanNode node, bool blocked) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                node.title,
                overflow: TextOverflow.ellipsis,
                style: context.text.label.copyWith(
                  color: blocked ? colors.textMuted : colors.textPrimary,
                ),
              ),
            ),
            if (node.safety == SafetyLevel.risky) ...[
              const SizedBox(width: AppSpacing.sm),
              StatusChip.safety(SafetyLevel.risky, context),
            ],
            if (node.requiresAdmin) ...[
              const SizedBox(width: AppSpacing.sm),
              StatusChip(
                label: 'Needs admin',
                color: colors.textMuted,
                icon: AppIcons.locked,
              ),
            ],
            if (node.sharesStorage) ...[
              const SizedBox(width: AppSpacing.sm),
              Tooltip(
                message:
                    'These bytes are shared with another file (an APFS clone or '
                    'hard link), so removing this will not free space.',
                child: StatusChip(
                  label: 'Shared storage',
                  color: colors.info,
                  icon: AppIcons.sharedStorage,
                ),
              ),
            ],
          ],
        ),
        if (node.subtitle != null)
          Text(
            node.subtitle!,
            overflow: TextOverflow.ellipsis,
            style: context.text.caption,
          ),
      ],
    );
  }
}
