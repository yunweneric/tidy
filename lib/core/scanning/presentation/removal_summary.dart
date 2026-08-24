import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/scanning/logic/scan_state.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/animated_bytes.dart';
import 'package:tidy/core/widgets/tidy_card.dart';

/// The completion screen.
///
/// The wording is deliberate: trashing something frees no space until the Trash
/// is emptied, so this says "moved to Trash" and names the amount still to be
/// reclaimed rather than claiming free space that does not exist yet.
class RemovalSummary extends StatelessWidget {
  const RemovalSummary({
    super.key,
    required this.outcome,
    required this.onDone,
    this.onEmptyTrash,
  });

  final CleanOutcome outcome;
  final VoidCallback onDone;
  final VoidCallback? onEmptyTrash;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trashed = outcome.movedToTrash;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.safe.withValues(alpha: 0.14),
                borderRadius: AppRadii.xlAll,
              ),
              child: Icon(AppIcons.check, size: 36, color: colors.safe),
            ),
            const SizedBox(height: AppSpacing.xl),
            AnimatedBytes(
              bytes: outcome.requestedBytes,
              valueStyle: context.text.displayL.copyWith(color: colors.safe),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              trashed
                  ? 'moved to Trash from ${outcome.removedCount} item'
                      '${outcome.removedCount == 1 ? '' : 's'}'
                  : 'removed from ${outcome.removedCount} item'
                      '${outcome.removedCount == 1 ? '' : 's'}',
              style: context.text.bodyM,
            ),
            if (trashed) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Your disk will not show the space as free until the Trash is '
                'emptied — everything here is still recoverable until then.',
                textAlign: TextAlign.center,
                style: context.text.bodyS,
              ),
            ],
            if (outcome.hasFailures) ...[
              const SizedBox(height: AppSpacing.xl),
              _Failures(outcome: outcome),
            ],
            const SizedBox(height: AppSpacing.xxl),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (trashed && onEmptyTrash != null)
                  OutlinedButton(
                    onPressed: onEmptyTrash,
                    child: const Text('Open Trash'),
                  ),
                ElevatedButton(onPressed: onDone, child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Failures extends StatelessWidget {
  const _Failures({required this.outcome});

  final CleanOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final failures = outcome.failures;

    return TidyCard(
      accent: colors.review,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.info, size: 16, color: colors.review),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${failures.length} item${failures.length == 1 ? '' : 's'} stayed put',
                style: context.text.titleS,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'These usually need administrator rights or Full Disk Access.',
            style: context.text.bodyS,
          ),
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final failure in failures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collapseHome(failure.path, _home),
                            style: context.text.mono.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          Text(
                            failure.error,
                            style: context.text.caption.copyWith(
                              color: colors.review,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String? get _home => Platform.environment['HOME'];
}
