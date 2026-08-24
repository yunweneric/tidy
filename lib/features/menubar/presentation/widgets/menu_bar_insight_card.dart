import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/widgets/tidy_card.dart';
import 'package:mac_uninstaller/features/menubar/domain/menu_bar_insight.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_button.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_vitals.dart';

/// The panel's headline: one sentence about the machine, and the one button
/// that does something about it.
class MenuBarInsightCard extends StatelessWidget {
  const MenuBarInsightCard({
    super.key,
    required this.insight,
    this.enabled = true,
    this.onAction,
  });

  final MenuBarInsight insight;
  final bool enabled;
  final ValueChanged<MenuBarInsightAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = colorForLevel(context, insight.level);
    final action = insight.action;

    return TidyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md - 1,
      ),
      tint: insight.level == VitalLevel.good ? null : color,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: AppRadii.mdAll,
            ),
            child: Icon(_iconFor(insight.kind), size: 15, color: color),
          ),
          const SizedBox(width: AppSpacing.md - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  insight.headline,
                  style: context.text.label.copyWith(
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  insight.detail,
                  style: context.text.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (action != null && insight.actionLabel != null) ...[
            const SizedBox(width: AppSpacing.sm),
            MenuBarButton(
              label: insight.actionLabel!,
              tone: MenuBarButtonTone.filled,
              onPressed:
                  enabled && onAction != null ? () => onAction!(action) : null,
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(MenuBarInsightKind kind) => switch (kind) {
    MenuBarInsightKind.diskCritical ||
    MenuBarInsightKind.diskFilling => AppIcons.storage,
    MenuBarInsightKind.memoryPressure => AppIcons.memory,
    MenuBarInsightKind.thermal => AppIcons.risky,
    MenuBarInsightKind.cpuBusy => AppIcons.cpu,
    MenuBarInsightKind.reclaimable => AppIcons.cleanup,
    MenuBarInsightKind.healthy => AppIcons.safe,
  };
}
