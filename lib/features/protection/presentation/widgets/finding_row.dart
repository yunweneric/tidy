import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/bundle_icon.dart';
import 'package:tidy/core/widgets/status_chip.dart';
import 'package:tidy/features/protection/data/models/protection_finding.dart';

/// One thing Protection looked at, and what it found.
///
/// Modelled on Performance's launch-item row, and for the same reason: a
/// domain-specific verdict rendered through the generic [StatusChip] rather
/// than through `SafetyLevel`, whose tiers mean something else entirely.
class FindingRow extends StatefulWidget {
  const FindingRow({
    super.key,
    required this.finding,
    required this.onAction,
    required this.onIgnore,
    this.iconBytes,
    this.ignored = false,
    this.busy = false,
    this.note,
  });

  final ProtectionFinding finding;
  final Uint8List? iconBytes;
  final bool ignored;
  final bool busy;

  /// The answer to a check the user asked for, shown under the row until they
  /// navigate away. Not a toast: it is about this row and belongs beside it.
  final String? note;

  final void Function(ProtectionAction action) onAction;
  final ValueChanged<bool> onIgnore;

  @override
  State<FindingRow> createState() => _FindingRowState();
}

class _FindingRowState extends State<FindingRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final finding = widget.finding;
    final verdict = finding.verdict;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: _hovered ? colors.surfaceHover : null,
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: widget.ignored ? 0.45 : 1,
                  child: BundleIcon(
                    bytes: widget.iconBytes,
                    size: 28,
                    fallback: finding.area.icon,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              finding.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleS.copyWith(
                                color:
                                    widget.ignored
                                        ? colors.textMuted
                                        : colors.textPrimary,
                              ),
                            ),
                          ),
                          if (widget.ignored) ...[
                            const SizedBox(width: AppSpacing.sm),
                            StatusChip(
                              label: 'Settled',
                              color: colors.textMuted,
                            ),
                          ],
                        ],
                      ),
                      if (finding.subtitle.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          finding.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.caption,
                        ),
                      ],
                      if (!widget.ignored && finding.chips.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (final fact in finding.chips)
                              Tooltip(
                                message: fact.detail,
                                child: StatusChip(
                                  label: fact.label,
                                  color:
                                      fact.isUnreadable
                                          ? colors.textMuted
                                          : verdict ==
                                              ProtectionVerdict.unverified
                                          ? colors.textMuted
                                          : colors.review,
                                  icon:
                                      fact.isUnreadable
                                          ? AppIcons.locked
                                          : AppIcons.review,
                                ),
                              ),
                          ],
                        ),
                      ],
                      // The one fact worth reading in full sits under the chips,
                      // because a tooltip is where an explanation goes to be
                      // missed by everyone who most needs it.
                      if (!widget.ignored && finding.chips.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          finding.chips.first.detail,
                          style: context.text.bodyS,
                        ),
                      ],
                      if (widget.note != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: colors.surfaceRaised,
                            borderRadius: AppRadii.smAll,
                          ),
                          child: Text(
                            widget.note!,
                            style: context.text.bodyS.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _Actions(
                  finding: finding,
                  busy: widget.busy,
                  visible: _hovered,
                  ignored: widget.ignored,
                  onAction: widget.onAction,
                  onIgnore: widget.onIgnore,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.finding,
    required this.busy,
    required this.visible,
    required this.ignored,
    required this.onAction,
    required this.onIgnore,
  });

  final ProtectionFinding finding;
  final bool busy;
  final bool visible;
  final bool ignored;
  final void Function(ProtectionAction action) onAction;
  final ValueChanged<bool> onIgnore;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    // Hover-revealed, like the Performance rows: four buttons on every row of a
    // seventy-row list is a wall, and the destructive one should not be the
    // easiest thing on screen to hit.
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: context.motion.fast,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (finding.verdict != ProtectionVerdict.ordinary)
            _button(
              context,
              icon: ignored ? AppIcons.restore : AppIcons.safe,
              tooltip:
                  ignored ? 'Raise this again' : 'Settled — stop mentioning it',
              onPressed: visible ? () => onIgnore(!ignored) : null,
            ),
          for (final action in finding.actions)
            _button(
              context,
              icon: _iconFor(action),
              tooltip: _tooltipFor(action),
              onPressed: visible ? () => onAction(action) : null,
              destructive: action == ProtectionAction.remove,
            ),
        ],
      ),
    );
  }

  Widget _button(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) => Tooltip(
    message: tooltip,
    child: IconButton(
      icon: Icon(icon, size: 16),
      color: destructive ? context.colors.risky : context.colors.textSecondary,
      splashRadius: 16,
      onPressed: onPressed,
    ),
  );

  static IconData _iconFor(ProtectionAction action) => switch (action) {
    ProtectionAction.reveal => AppIcons.revealInFinder,
    ProtectionAction.disable => AppIcons.locked,
    ProtectionAction.enable => AppIcons.unlocked,
    ProtectionAction.remove => AppIcons.delete,
    ProtectionAction.validate => AppIcons.protection,
    ProtectionAction.assess => AppIcons.info,
    ProtectionAction.openSettings => AppIcons.settings,
    ProtectionAction.openApps => AppIcons.applications,
    ProtectionAction.allowBrowserAccess => AppIcons.unlocked,
  };

  static String _tooltipFor(ProtectionAction action) => switch (action) {
    ProtectionAction.reveal => 'Reveal in Finder',
    ProtectionAction.disable => 'Stop this starting itself',
    ProtectionAction.enable => 'Let this start itself again',
    ProtectionAction.remove => 'Remove it',
    ProtectionAction.validate => 'Check the seal — takes a few seconds',
    ProtectionAction.assess => 'Ask macOS whether it would open this',
    ProtectionAction.openSettings => 'Open System Settings',
    ProtectionAction.openApps => 'Uninstall in Applications',
    ProtectionAction.allowBrowserAccess => 'Let Tidy look at your extensions',
  };
}
