import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/preview/preview_mac.dart';

/// Reclaim space from caches, logs and build artefacts.
///
/// The pane the tour opens on second, and the one that carries the product's
/// central promise: you see everything first, only what is genuinely safe is
/// ticked for you, and what goes, goes to the Trash.
class PreviewCleanupPane extends StatelessWidget {
  const PreviewCleanupPane({super.key, required this.mac, this.onNavigate});

  final PreviewMac mac;
  final ValueChanged<PreviewScreen>? onNavigate;

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: PreviewScreen.smartCare.label,
      subtitle: PreviewScreen.smartCare.blurb,
      actions: [
        if (mac.phase != PreviewScanPhase.idle)
          OutlineActionButton(
            label: 'Scan again',
            icon: AppIcons.refresh,
            onPressed: mac.scan,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The hero is the readout for a scan that has found something. With
          // nothing found it would say "nothing yet" directly above a card
          // saying the same thing, so before the first scan the invitation is
          // the whole screen.
          if (mac.found.isEmpty)
            _Idle(mac: mac)
          else ...[
            _ScanHero(mac: mac),
            const SizedBox(height: AppSpacing.xl),
            for (var i = 0; i < mac.found.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              _JunkCard(mac: mac, junk: mac.found[i]),
            ],
            const SizedBox(height: AppSpacing.xl),
            _Actions(mac: mac, onNavigate: onNavigate),
          ],
        ],
      ),
    );
  }
}

class _ScanHero extends StatelessWidget {
  const _ScanHero({required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scanning = mac.phase == PreviewScanPhase.scanning;
    final found = mac.found.fold(0, (total, kind) => total + kind.bytes);

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Row(
        children: [
          GaugeRing(
            // Null while the sweep is still indeterminate, which is what makes
            // the ring spin instead of sitting at a figure it could not know.
            progress: scanning ? mac.scanProgress : (found > 0 ? 1 : 0),
            size: 96,
            strokeWidth: 8,
            child: Icon(AppIcons.cleanup, size: 30, color: colors.safe),
          ),
          const SizedBox(width: AppSpacing.xxl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (found > 0)
                  AnimatedBytes(
                    bytes: found,
                    textAlign: TextAlign.left,
                    valueStyle: context.text.displayXl,
                  )
                else
                  Text(
                    scanning ? 'Looking…' : 'Nothing found yet',
                    style: context.text.displayL,
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(switch (mac.phase) {
                  PreviewScanPhase.idle when found == 0 =>
                    'Run a scan to find out what is reclaimable.',
                  PreviewScanPhase.scanning =>
                    'Sweeping ~/Library — results appear as they land.',
                  _ => 'Reclaimable, across ${mac.found.length} categories.',
                }, style: context.text.bodyM),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        children: [
          GaugeRing(
            // Null while the sweep is still indeterminate, which is what makes
            // the ring spin rather than sit at a figure it could not know yet.
            progress:
                mac.phase == PreviewScanPhase.scanning ? mac.scanProgress : 0,
            size: 88,
            strokeWidth: 8,
            child: Icon(AppIcons.cleanup, size: 30, color: context.colors.safe),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            mac.phase == PreviewScanPhase.scanning
                ? 'Sweeping ~/Library…'
                : 'Nothing has been scanned yet',
            style: context.text.titleL,
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              mac.phase == PreviewScanPhase.scanning
                  // The real scan streams results in category by category, so
                  // the screen is never empty during a slow orphan sweep.
                  ? 'Results appear as they land, category by category.'
                  // A confident "0 B" from a scan that never happened is the
                  // same lie as a virus checker reporting no threats without
                  // looking.
                  : 'Tidy does not guess. Until a scan has run it says so, '
                      'rather than reporting a confident zero.',
              textAlign: TextAlign.center,
              style: context.text.bodyL,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          GradientButton(
            label: 'Scan for junk',
            icon: AppIcons.cleanup,
            onPressed: mac.phase == PreviewScanPhase.scanning ? null : mac.scan,
          ),
        ],
      ),
    );
  }
}

class _JunkCard extends StatelessWidget {
  const _JunkCard({required this.mac, required this.junk});

  final PreviewMac mac;
  final PreviewJunk junk;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = mac.isSelected(junk);

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      selected: selected,
      onTap: () => mac.toggleJunk(junk),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Check(checked: selected),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(junk.title, style: context.text.titleM),
                        const SizedBox(width: AppSpacing.md),
                        StatusChip.safety(junk.safety, context),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(junk.blurb, style: context.text.bodyM),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Text(
                formatBytes(junk.bytes),
                style: context.text.titleM.copyWith(
                  color: selected ? colors.safe : colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs + 2,
              children: [
                for (final path in junk.items)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      borderRadius: AppRadii.smAll,
                    ),
                    child: Text(path, style: context.text.mono),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's checkbox shape, without a Material `Checkbox`'s ripple.
class _Check extends StatelessWidget {
  const _Check({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AnimatedContainer(
      duration: context.motion.fast,
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: checked ? colors.accent : Colors.transparent,
        borderRadius: AppRadii.xsAll,
        border: Border.all(
          color: checked ? colors.accent : colors.borderStrong,
          width: 1.4,
        ),
      ),
      child:
          checked
              ? Icon(AppIcons.check, size: 13, color: colors.textOnAccent)
              : null,
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.mac, this.onNavigate});

  final PreviewMac mac;
  final ValueChanged<PreviewScreen>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final selected = mac.selectedBytes;

    return Row(
      children: [
        GradientButton(
          label:
              selected > 0
                  ? 'Move ${formatBytes(selected)} to Trash'
                  : 'Nothing selected',
          icon: AppIcons.trash,
          size: GradientButtonSize.large,
          onPressed:
              selected == 0
                  ? null
                  : () {
                    mac.reclaimSelected();
                    onNavigate?.call(PreviewScreen.recycleBin);
                  },
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Text(
            // The distinction the whole app is careful about, and the reason
            // the free-space bar does not move on this screen.
            'Removal goes to the Trash, so it is recoverable and Put Back '
            'works. Nothing is freed until the Trash is emptied — and Tidy '
            'will not claim space back it has not returned yet.',
            style: context.text.bodyS,
          ),
        ),
      ],
    );
  }
}
