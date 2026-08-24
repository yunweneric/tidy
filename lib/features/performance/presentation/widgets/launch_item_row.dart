import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/utils/home_dir.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/performance/data/models/launch_item.dart';

/// One launchd job.
///
/// The row's whole job is to make an unreadable reverse-DNS label into
/// something a person can decide about: what it is, when it runs, and whether
/// anything is wrong with it.
class LaunchItemRow extends StatefulWidget {
  const LaunchItemRow({
    super.key,
    required this.item,
    required this.icon,
    required this.busy,
    required this.onToggle,
    required this.onRemove,
    this.isLast = false,
  });

  final LaunchItem item;
  final Uint8List? icon;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;

  /// Suppresses the divider so the list meets the card's rounded edge cleanly.
  final bool isLast;

  @override
  State<LaunchItemRow> createState() => _LaunchItemRowState();
}

class _LaunchItemRowState extends State<LaunchItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final item = widget.item;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: context.motion.fast,
        curve: context.motion.standard,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: _hovered ? colors.surfaceHover : Colors.transparent,
          border:
              widget.isLast
                  ? null
                  : Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            BundleIcon(
              bytes: widget.icon,
              size: 32,
              fallback:
                  item.kind == LaunchItemKind.daemon
                      ? AppIcons.backgroundItems
                      : AppIcons.loginItems,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleS.copyWith(
                            color:
                                item.enabled
                                    ? colors.textPrimary
                                    : colors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ..._chips(context),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    item.trigger,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              flex: 2,
              child: Text(
                collapseHome(item.program ?? item.path, kHomeDir),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: context.text.mono,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(width: 132, child: _actions(context)),
          ],
        ),
      ),
    );
  }

  List<Widget> _chips(BuildContext context) {
    final colors = context.colors;
    final item = widget.item;

    return switch (item.health) {
      LaunchItemHealth.broken => [
        StatusChip(
          label: item.emptyStub ? 'Empty — starts nothing' : 'Program missing',
          color: colors.safe,
          icon: AppIcons.safe,
        ),
      ],
      LaunchItemHealth.unreadable => [
        StatusChip(
          label: 'Cannot be read',
          color: colors.review,
          icon: AppIcons.review,
        ),
      ],
      LaunchItemHealth.disabled => [
        StatusChip(label: 'Off', color: colors.info, icon: AppIcons.close),
      ],
      LaunchItemHealth.active =>
        item.requiresAdmin
            ? [
              StatusChip(
                label: 'Needs administrator',
                color: colors.review,
                icon: AppIcons.locked,
              ),
            ]
            : const [],
    };
  }

  Widget _actions(BuildContext context) {
    final colors = context.colors;
    final item = widget.item;

    if (widget.busy) {
      return const Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // Root-owned items get Reveal in Finder rather than a dead switch. Showing a
    // control that cannot work is worse than showing none.
    //
    // The exception is one that cannot start anything — its program is gone, or
    // the file is an empty stub. Removing that changes no behaviour, so it is
    // worth one password prompt, and it is offered here alongside Finder.
    if (item.requiresAdmin) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (item.canRemoveWithAdmin)
            AnimatedOpacity(
              duration: context.motion.fast,
              opacity: _hovered ? 1 : 0,
              child: IconButton(
                onPressed: _hovered ? widget.onRemove : null,
                icon: Icon(AppIcons.delete, size: 16, color: colors.risky),
                tooltip: 'Move to Trash — asks for your password',
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            onPressed: () => SystemBridge.revealInFinder(item.path),
            icon: const Icon(AppIcons.revealInFinder, size: 16),
            tooltip: 'Show in Finder',
            visualDensity: VisualDensity.compact,
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Destructive actions on hover only: a red glyph on every row turns a
        // list of your own software into a wall of warnings.
        AnimatedOpacity(
          duration: context.motion.fast,
          opacity: _hovered ? 1 : 0,
          child: IconButton(
            onPressed: _hovered ? widget.onRemove : null,
            icon: Icon(AppIcons.delete, size: 16, color: colors.risky),
            tooltip: 'Move to Trash',
            visualDensity: VisualDensity.compact,
          ),
        ),
        Switch(
          value: item.enabled,
          onChanged: item.canToggle ? widget.onToggle : null,
        ),
      ],
    );
  }
}
