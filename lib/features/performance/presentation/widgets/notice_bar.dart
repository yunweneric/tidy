import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/widgets/tidy_card.dart';
import 'package:mac_uninstaller/features/performance/logic/performance_state.dart';

/// What the last action did, said out loud.
///
/// Everything on this page acts immediately and persistently — a disabled agent
/// stays disabled across reboots, a quit app is gone — so none of it is allowed
/// to just silently redraw. A row that changes with no confirmation leaves the
/// user unsure whether they pressed the thing at all.
class NoticeBar extends StatelessWidget {
  const NoticeBar({super.key, required this.notice, required this.onDismiss});

  final PerformanceNotice notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = notice.ok ? colors.safe : colors.risky;

    return TidyCard(
      accent: accent,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(notice.ok ? AppIcons.safe : AppIcons.error, size: 17, color: accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(notice.message, style: context.text.bodyM)),
          const SizedBox(width: AppSpacing.md),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(AppIcons.close, size: 15),
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
