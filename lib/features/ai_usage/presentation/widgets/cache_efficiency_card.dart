import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/model_pricing.dart';
import 'package:tidy/features/ai_usage/presentation/widgets/usage_note.dart';

/// What prompt caching is doing to the bill.
///
/// The one figure here that is worth the card: a cache read bills at a tenth of
/// fresh input, so the difference between what the reads cost and what the same
/// tokens would have cost sent fresh is a real saving, computed from numbers
/// the logs actually contain rather than estimated. It is only quoted for
/// models with a published rate — Codex has none, so its cache reads are
/// counted and left out of the money line.
class CacheEfficiencyCard extends StatelessWidget {
  const CacheEfficiencyCard({super.key, required this.report});

  final AiUsageReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final tokens = report.tokens;

    var cacheReadCost = 0.0;
    var uncachedCost = 0.0;
    var pricedRead = 0;
    for (final entry in report.modelBreakdown) {
      final rate = ModelPricing.of(entry.key);
      if (rate == null) continue;
      cacheReadCost += entry.value.cacheRead * rate.cacheRead / 1000000;
      uncachedCost += entry.value.uncachedCostAt(rate);
      pricedRead += entry.value.cacheRead;
    }
    final saved = uncachedCost - cacheReadCost;

    final input = tokens.input;
    final write = tokens.cacheWrite;
    final read = tokens.cacheRead;
    final whole = input + write + read;
    final hitRate = whole == 0 ? 0.0 : read / whole;

    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel(
            label: 'Where the input came from',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.lg),
          StackedBar(
            height: 12,
            slices: [
              BarSlice(
                label: 'Fresh input',
                bytes: input,
                color: colors.seriesAt(0),
              ),
              BarSlice(
                label: 'Written to cache',
                bytes: write,
                color: colors.seriesAt(1),
              ),
              BarSlice(
                label: 'Read from cache',
                bytes: read,
                color: colors.seriesAt(2),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _Key(
                label: 'Fresh input',
                value: formatCount(input),
                color: colors.seriesAt(0),
              ),
              _Key(
                label: 'Cache writes',
                value: formatCount(write),
                color: colors.seriesAt(1),
              ),
              _Key(
                label: 'Cache reads',
                value: formatCount(read),
                color: colors.seriesAt(2),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Figure(
                  label: 'Served from cache',
                  value: '${(hitRate * 100).toStringAsFixed(0)}%',
                  detail: 'of everything sent in',
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Those reads cost',
                  value: formatUsd(cacheReadCost),
                  detail: 'a tenth of the input rate',
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Sending them fresh',
                  value: formatUsd(uncachedCost),
                  detail: 'is what caching avoided',
                  tone: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: AppRadii.mdAll,
            ),
            child: Row(
              children: [
                Icon(AppIcons.info, size: 17, color: colors.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Caching saved ${formatUsd(saved)} against sending the '
                    'same ${formatCount(pricedRead)} tokens fresh every time.',
                    style: text.bodyM.copyWith(color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          if (report.unpricedModels.isNotEmpty)
            UsageNote(
              'The money on this card covers only models with a published '
              'rate. ${report.unpricedModels.join(", ")} '
              '${report.unpricedModels.length == 1 ? "has" : "have"} none, so '
              '${report.unpricedModels.length == 1 ? "its" : "their"} cache '
              'reads are counted above and left out of the figures.',
            ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadii.pillAll,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            '$label  $value',
            style: context.text.caption,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.detail,
    this.tone,
  });

  final String label;
  final String value;
  final String detail;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.overline.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: text.displayL.copyWith(color: tone ?? colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(detail, style: text.caption),
      ],
    );
  }
}
