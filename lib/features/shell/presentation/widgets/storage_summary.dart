import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/widgets/size_bar.dart';

/// Disk usage at the foot of the sidebar, with the reclaimable figure alongside.
///
/// The bar turns amber past 85% and red past 95%: at that point free space is
/// the user's actual problem and the UI should say so without being asked.
class StorageSummary extends StatelessWidget {
  const StorageSummary({
    super.key,
    required this.disk,
    this.reclaimableBytes = 0,
    this.onPressed,
  });

  final DiskUsage disk;
  final int reclaimableBytes;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final loading = disk.totalBytes == 0;
    final fraction = disk.usedFraction;

    final barColor = switch (fraction) {
      >= 0.95 => colors.risky,
      >= 0.85 => colors.review,
      _ => colors.accent,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.mdAll,
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('STORAGE', style: context.text.overline),
                const Spacer(),
                if (!loading)
                  Text(
                    '${(fraction * 100).round()}%',
                    style: context.text.caption.copyWith(
                      color: barColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizeBar(fraction: loading ? 0 : fraction, color: barColor, height: 5),
            const SizedBox(height: AppSpacing.sm),
            Text(
              loading
                  ? 'Reading disk usage…'
                  : '${formatBytes(disk.freeBytes)} free of ${formatBytes(disk.totalBytes)}',
              style: context.text.caption,
            ),
            if (reclaimableBytes > 0) ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onPressed,
                  child: Text('Reclaim ${formatBytes(reclaimableBytes)}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
