import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/vitals/system_vitals.dart';

/// The readings under the gauges: pressure, swap, load and — when it is worth
/// saying — heat.
///
/// All of them were already sampled every two seconds and shown nowhere — the
/// popover drew three gauges and then changed the subject to clipboard history.
/// They are the numbers that explain the gauges above them: 85% memory is
/// ordinary on a Mac and means nothing on its own, while 85% memory *with*
/// pressure high and swap in use is the machine actually struggling.
///
/// Anything unmeasured is left out rather than drawn as a zero. A row of
/// confident zeroes from a sampler that has not answered yet is the same class
/// of wrong as a scanner reporting nothing found without having looked.
///
/// Uptime is deliberately not here. The panel's footer already carries it, and
/// the same number twice on one panel reads as two different numbers that
/// happen to agree.
class MenuBarVitalsDetail extends StatelessWidget {
  const MenuBarVitalsDetail({super.key, required this.vitals});

  final SystemVitals vitals;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final readings = <_Reading>[];

    if (vitals.memoryPressurePercent case final pressure?) {
      readings.add(
        _Reading(
          label: 'PRESSURE',
          value: '${pressure.round()}%',
          // The one of the four with a threshold worth colouring. Pressure is
          // macOS's own answer to "is memory actually a problem", which is the
          // question the memory gauge cannot answer by itself.
          tone: switch (pressure) {
            >= 85 => colors.risky,
            >= 70 => colors.review,
            _ => null,
          },
        ),
      );
    }

    if (vitals.isKnown) {
      readings.add(
        _Reading(
          label: 'SWAP',
          value: vitals.isSwapping ? formatBytes(vitals.swapUsedBytes) : 'none',
          // Swapping at all is normal on macOS; swapping *heavily* is the
          // machine paging to disk to keep up, which is worth a colour.
          tone: vitals.isSwapHeavy ? colors.review : null,
        ),
      );
    }

    if (vitals.loadAverage case final load?) {
      readings.add(
        _Reading(
          label: 'LOAD',
          value: load.toStringAsFixed(2),
          // Against cores, not against a fixed number: 5.6 is busy on a
          // four-core Mac and unremarkable on a sixteen-core one.
          tone:
              vitals.coreCount > 0 && load > vitals.coreCount
                  ? colors.review
                  : null,
        ),
      );
    }

    if (vitals.thermal.isNotable) {
      readings.add(
        _Reading(
          label: 'HEAT',
          value: vitals.thermal.label,
          tone:
              vitals.thermal == ThermalState.critical
                  ? colors.risky
                  : colors.review,
        ),
      );
    }

    if (readings.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md + 2,
        AppSpacing.sm + 2,
        AppSpacing.md + 2,
        0,
      ),
      child: Row(
        children: [
          for (var i = 0; i < readings.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.md),
            Expanded(child: readings[i]),
          ],
        ],
      ),
    );
  }
}

/// One label over one figure. Deliberately not a card: three tinted tiles above
/// this already carry the weight, and five more would leave the panel with
/// nothing on it but boxes.
class _Reading extends StatelessWidget {
  const _Reading({required this.label, required this.value, this.tone});

  final String label;
  final String value;

  /// Null for an ordinary reading, which is most of them. A colour here means
  /// the number has crossed something, so an uncoloured row reads as "nothing
  /// to see" without having to say it.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.overline.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.label.copyWith(color: tone ?? colors.textPrimary),
        ),
      ],
    );
  }
}
