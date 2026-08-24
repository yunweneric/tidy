import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/widgets/animated_bytes.dart';
import 'package:mac_uninstaller/core/widgets/gauge_ring.dart';

/// The centrepiece of every module: ring, running total, one clear action.
///
/// Idle and scanning share a layout so starting a scan animates rather than
/// swapping screens — the ring is already there, it just starts moving.
class ScanHero extends StatelessWidget {
  const ScanHero({
    super.key,
    required this.headline,
    required this.actionLabel,
    required this.onAction,
    this.icon,
    this.message,
    this.bytes,
    this.fraction,
    this.statusLine,
    this.scanning = false,
    this.secondaryAction,
  });

  final String headline;

  /// One reassuring, non-technical line.
  final String? message;

  final IconData? icon;

  /// Shown inside the ring once there is something to report.
  final int? bytes;

  /// 0–1, or null for an indeterminate sweep.
  final double? fraction;

  /// The path currently being examined. Truncated from the left, because the
  /// informative end of a long path is the tail.
  final String? statusLine;

  final bool scanning;

  final String actionLabel;
  final VoidCallback? onAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: AppSpacing.xxl),
            GaugeRing(
              progress: scanning ? fraction : (bytes == null ? 1 : null),
              size: 210,
              child: Center(
                child: bytes != null
                    ? AnimatedBytes(
                        bytes: bytes!,
                        valueStyle: context.text.displayL,
                      )
                    : Icon(
                        icon ?? Brand.mark,
                        size: 44,
                        color: colors.accent,
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: context.text.titleM,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.text.bodyM,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl + AppSpacing.sm,
                  vertical: AppSpacing.lg,
                ),
              ),
              child: Text(actionLabel),
            ),
            if (secondaryAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              secondaryAction!,
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 18,
              child: statusLine == null
                  ? null
                  : Text(
                      statusLine!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: context.text.mono,
                    ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  /// Convenience for the "nothing to do" state.
  static Widget allClear(
    BuildContext context, {
    required String headline,
    required String message,
    required VoidCallback onRescan,
  }) {
    return ScanHero(
      headline: headline,
      message: message,
      icon: Icons.check_rounded,
      actionLabel: 'Scan again',
      onAction: onRescan,
    );
  }
}

/// A path shortened for the rolling status line.
String shortenPath(String path, {String? home}) {
  final collapsed = collapseHome(path, home);
  const limit = 52;
  if (collapsed.length <= limit) return collapsed;
  return '…${collapsed.substring(collapsed.length - limit)}';
}
