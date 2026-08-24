import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/bundle_icon.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_button.dart';
import 'package:tidy/core/vitals/process_sample.dart';

/// One live process in the panel.
///
/// Quitting confirms inline rather than in a dialog — a modal over a popover
/// dismisses the popover underneath it on macOS, and the inline state is where
/// the row can say what "quit" actually means before anything happens.
class MenuBarProcessRow extends StatelessWidget {
  const MenuBarProcessRow({
    super.key,
    required this.process,
    required this.sort,
    required this.confirming,
    required this.onQuitPressed,
    required this.onCancel,
    this.onConfirm,
    this.icon,
    this.busy = false,
    this.enabled = true,
  });

  final ProcessSample process;
  final Uint8List? icon;

  /// Which number is the headline. The other one becomes the caption, so the
  /// list re-reads as a ranking of whatever the user asked to rank by.
  final ProcessSort sort;

  final bool confirming;
  final bool busy;
  final bool enabled;
  final VoidCallback onQuitPressed;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final byCpu = sort == ProcessSort.cpu;
    final cpu = process.cpuPercent;
    final cpuLabel = cpu == null ? '—' : '${cpu.toStringAsFixed(1)}%';
    final memoryLabel = formatBytes(process.memoryBytes);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: AppSpacing.xs + 1,
      ),
      color: confirming ? colors.surfaceHover : Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              BundleIcon(
                bytes: icon,
                size: 22,
                fallback:
                    process.isApp ? AppIcons.appPlaceholder : AppIcons.cpu,
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      process.name,
                      style: context.text.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      byCpu ? '$memoryLabel memory' : '$cpuLabel CPU',
                      style: context.text.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                byCpu ? cpuLabel : memoryLabel,
                style: context.text.bodyS.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: Padding(
                    padding: EdgeInsets.all(7),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (!confirming)
                MenuBarIconButton(
                  icon: AppIcons.close,
                  tooltip:
                      process.quittable
                          ? 'Quit ${process.name}'
                          : 'Quitting ${process.name} would end your login session',
                  color: colors.risky,
                  onPressed:
                      enabled && process.quittable ? onQuitPressed : null,
                )
              else
                const SizedBox(width: 28),
            ],
          ),
          if (confirming) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Asks ${process.name} to quit — it can still save first.',
                    style: context.text.caption.copyWith(color: colors.review),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                MenuBarButton(label: 'Cancel', onPressed: onCancel),
                const SizedBox(width: AppSpacing.xs),
                MenuBarButton(
                  label: 'Quit',
                  tone: MenuBarButtonTone.danger,
                  onPressed: onConfirm,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
