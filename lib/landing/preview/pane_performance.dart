import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/preview/preview_chrome.dart';
import 'package:tidy/landing/preview/preview_mac.dart';

/// Tune startup items and run macOS upkeep.
class PreviewPerformancePane extends StatelessWidget {
  const PreviewPerformancePane({super.key, required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final login =
        mac.launchItems
            .where((item) => item.kind == PreviewItemKind.login)
            .toList();
    final background =
        mac.launchItems
            .where((item) => item.kind == PreviewItemKind.background)
            .toList();

    return ModuleScaffold(
      title: PreviewScreen.performance.label,
      subtitle: PreviewScreen.performance.blurb,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            title: 'Login items',
            caption:
                '${mac.enabledLaunchItems} enabled. Turned off, not removed — '
                'a login item you can put back is a different promise.',
            items: login,
            mac: mac,
          ),
          const SizedBox(height: AppSpacing.xl),
          _Section(
            title: 'Background items',
            caption: 'Launch agents and daemons that start without you asking.',
            items: background,
            mac: mac,
          ),
          const SizedBox(height: AppSpacing.xl),
          _HeavyConsumers(),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.caption,
    required this.items,
    required this.mac,
  });

  final String title;
  final String caption;
  final List<PreviewLaunchItem> items;
  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(title, style: context.text.titleM),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(caption, style: context.text.caption)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        PreviewTable(
          header: const PreviewTableHeader(
            cells: [(8, 'Item'), (6, 'Where'), (3, 'State')],
          ),
          rows: [
            for (var i = 0; i < items.length; i++)
              _LaunchRow(mac: mac, item: items[i], last: i == items.length - 1),
          ],
        ),
      ],
    );
  }
}

class _LaunchRow extends StatelessWidget {
  const _LaunchRow({required this.mac, required this.item, required this.last});

  final PreviewMac mac;
  final PreviewLaunchItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return PreviewRow(
      last: last,
      onTap: () => mac.toggleLaunchItem(item),
      child: Row(
        children: [
          Expanded(
            flex: 8,
            child: Row(
              children: [
                Icon(
                  item.kind == PreviewItemKind.login
                      ? AppIcons.loginItems
                      : AppIcons.backgroundItems,
                  size: 15,
                  color: item.enabled ? colors.review : colors.textMuted,
                ),
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Text(
                    item.name,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleS,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              item.detail,
              overflow: TextOverflow.ellipsis,
              style: context.text.caption,
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: _Switch(on: item.enabled),
            ),
          ),
        ],
      ),
    );
  }
}

/// A macOS-shaped toggle. Not `Switch`, whose Material sizing and ripple read
/// as an Android app the moment it sits in a desktop table.
class _Switch extends StatelessWidget {
  const _Switch({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;

    return AnimatedContainer(
      duration: motion.fast,
      curve: motion.standard,
      width: 38,
      height: 22,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: on ? colors.safe : colors.surfaceRaised,
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: on ? colors.safe : colors.border),
      ),
      child: AnimatedAlign(
        duration: motion.fast,
        curve: motion.standard,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: on ? colors.textOnAccent : colors.textMuted,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _HeavyConsumers extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Heavy consumers', style: context.text.titleM),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'What is using the most CPU right now.',
                style: context.text.caption,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        PreviewTable(
          header: const PreviewTableHeader(
            cells: [(9, 'Process'), (4, 'CPU'), (4, 'Memory')],
          ),
          rows: [
            for (var i = 0; i < PreviewMac.processes.length; i++)
              PreviewRow(
                last: i == PreviewMac.processes.length - 1,
                child: Row(
                  children: [
                    Expanded(
                      flex: 9,
                      child: Text(
                        PreviewMac.processes[i].name,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleS,
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: Text(
                              '${PreviewMac.processes[i].cpu}%',
                              style: context.text.titleS.copyWith(
                                color:
                                    PreviewMac.processes[i].cpu > 30
                                        ? colors.risky
                                        : colors.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SizeBar(
                              fraction: PreviewMac.processes[i].cpu / 100,
                              color:
                                  PreviewMac.processes[i].cpu > 30
                                      ? colors.risky
                                      : colors.review,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          formatBytes(PreviewMac.processes[i].memoryBytes),
                          style: context.text.bodyM,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
