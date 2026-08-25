import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/preview/preview_chrome.dart';
import 'package:tidy/landing/preview/preview_mac.dart';

/// What your Mac is sending and receiving, now and over time.
class PreviewNetworkPane extends StatelessWidget {
  const PreviewNetworkPane({super.key, required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ModuleScaffold(
      title: PreviewScreen.network.label,
      subtitle: PreviewScreen.network.blurb,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TidyCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Right now', style: context.text.titleM),
                    const Spacer(),
                    _Rate(
                      icon: AppIcons.downstream,
                      color: colors.downstream,
                      label: '${formatBytes(mac.downNowBytes)}/s',
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    _Rate(
                      icon: AppIcons.upstream,
                      color: colors.upstream,
                      label: '${formatBytes(mac.upNowBytes)}/s',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                // Mirrored about a midline rather than overlaid: on a network
                // chart the two series cross constantly, because a download's
                // acknowledgements make the upload track it.
                SparkChart(
                  down: mac.down,
                  up: mac.up,
                  capacity: 60,
                  height: 150,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'The last minute. Tidy only records while it is running, so '
                  'gaps in the history are drawn as gaps rather than smoothed '
                  'over.',
                  style: context.text.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Downloaded today',
                  value: formatBytes(mac.todayDownBytes),
                  detail: 'Across every interface',
                  icon: AppIcons.downstream,
                  color: colors.downstream,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: StatTile(
                  label: 'Uploaded today',
                  value: formatBytes(mac.todayUpBytes),
                  detail: 'Across every interface',
                  icon: AppIcons.upstream,
                  color: colors.upstream,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: StatTile(
                  label: 'Interfaces',
                  value: '3',
                  detail: '2 active · 1 idle',
                  icon: AppIcons.ethernet,
                  color: colors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          PreviewTable(
            header: const PreviewTableHeader(
              cells: [
                (5, 'Interface'),
                (4, 'Kind'),
                (4, 'Down'),
                (4, 'Up'),
                (3, 'State'),
              ],
            ),
            rows: const [
              _InterfaceRow(
                name: 'en0',
                kind: 'Wi-Fi',
                down: '3.9 GB',
                up: '680 MB',
                active: true,
              ),
              _InterfaceRow(
                name: 'utun4',
                kind: 'VPN',
                down: '480 MB',
                up: '60 MB',
                active: true,
              ),
              _InterfaceRow(
                name: 'en5',
                kind: 'Ethernet adapter',
                down: '0 B',
                up: '0 B',
                active: false,
                last: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rate extends StatelessWidget {
  const _Rate({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: context.text.titleM.copyWith(color: color)),
      ],
    );
  }
}

class _InterfaceRow extends StatelessWidget {
  const _InterfaceRow({
    required this.name,
    required this.kind,
    required this.down,
    required this.up,
    required this.active,
    this.last = false,
  });

  final String name;
  final String kind;
  final String down;
  final String up;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return PreviewRow(
      last: last,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(name, style: context.text.mono.copyWith(fontSize: 13)),
          ),
          Expanded(flex: 4, child: Text(kind, style: context.text.bodyM)),
          Expanded(
            flex: 4,
            child: Text(
              down,
              style: context.text.bodyM.copyWith(color: colors.downstream),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              up,
              style: context.text.bodyM.copyWith(color: colors.upstream),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                label: active ? 'Active' : 'Idle',
                color: active ? colors.safe : colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
