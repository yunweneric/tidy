import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/performance/data/models/process_sample.dart';
import 'package:mac_uninstaller/features/performance/logic/process_monitor_bloc.dart';
import 'package:mac_uninstaller/features/performance/presentation/widgets/notice_bar.dart';

/// Column geometry, declared once and used by the header and every row — a
/// header that declares its own flex values is how a table ends up with labels
/// that do not sit above their data.
@immutable
class _Columns {
  const _Columns._();

  static const int name = 4;
  static const double cpu = 96;
  static const double memory = 110;
  static const double actions = 96;
}

/// What is using the machine right now.
class HeavyConsumersSection extends StatelessWidget {
  const HeavyConsumersSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProcessMonitorBloc, ProcessMonitorState>(
      builder: (context, state) {
        final bloc = context.read<ProcessMonitorBloc>();
        final processes = state.ordered;

        if (!state.sampled) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Summary(snapshot: state.snapshot),
            if (state.notice != null) ...[
              const SizedBox(height: AppSpacing.md),
              NoticeBar(
                notice: state.notice!,
                onDismiss: () => bloc.add(const MonitorNoticeDismissed()),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: TidyCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    DataTableHeader(
                      columnLabels: const [],
                      trailingWidth: _Columns.actions,
                      columns: [
                        TableColumn(
                          'Process',
                          flex: _Columns.name,
                          sort: state.sort == ProcessSort.name
                              ? SortDirection.ascending
                              : SortDirection.none,
                          onTap: () =>
                              bloc.add(const ProcessSortChanged(ProcessSort.name)),
                        ),
                        TableColumn(
                          'CPU',
                          width: _Columns.cpu,
                          align: TextAlign.right,
                          sort: state.sort == ProcessSort.cpu
                              ? SortDirection.descending
                              : SortDirection.none,
                          onTap: () =>
                              bloc.add(const ProcessSortChanged(ProcessSort.cpu)),
                        ),
                        TableColumn(
                          'Memory',
                          width: _Columns.memory,
                          align: TextAlign.right,
                          sort: state.sort == ProcessSort.memory
                              ? SortDirection.descending
                              : SortDirection.none,
                          onTap: () =>
                              bloc.add(const ProcessSortChanged(ProcessSort.memory)),
                        ),
                      ],
                    ),
                    Expanded(
                      child: processes.isEmpty
                          ? const EmptyState(
                              icon: AppIcons.nothingFound,
                              title: 'Nothing of yours is running',
                              message:
                                  'Which is unusual — try refreshing, or check '
                                  'that Tidy can see your processes.',
                            )
                          : ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: processes.length,
                              itemBuilder: (context, index) => _ProcessRow(
                                process: processes[index],
                                icon: processes[index].bundlePath == null
                                    ? null
                                    : state.icons[processes[index].bundlePath],
                                busy: state.busyPids.contains(processes[index].pid),
                                isLast: index == processes.length - 1,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The two numbers worth stating, both scoped to what is actually on screen.
///
/// A machine-wide "CPU 34%" would need `host_processor_info` and would not
/// match the rows underneath it — the system processes we cannot measure are
/// missing from both. Better to total exactly what is listed and say so.
class _Summary extends StatelessWidget {
  const _Summary({required this.snapshot});

  final ProcessSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cpu = snapshot.totalCpuPercent;

    return Row(
      children: [
        Expanded(
          child: _Stat(
            icon: AppIcons.cpu,
            label: 'CPU, your processes',
            value: cpu == null ? '—' : '${cpu.toStringAsFixed(0)}%',
            // macOS counts a fully busy core as 100%, so this can and should
            // exceed 100 on a multi-core machine — Activity Monitor's %CPU
            // column works the same way. Saying so beats looking broken.
            hint: cpu == null
                ? 'Measuring…'
                : '100% is one core busy — this Mac has ${Platform.numberOfProcessors}',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _Stat(
            icon: AppIcons.memory,
            label: 'Memory, your processes',
            value: formatBytes(snapshot.totalMemoryBytes),
            hint: 'Real footprint, not shared pages counted twice',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _Stat(
            icon: AppIcons.locked,
            label: 'Not shown',
            value: '${snapshot.restrictedCount}',
            hint: 'macOS processes — reading these needs administrator rights',
            muted: true,
            accent: colors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    this.muted = false,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final bool muted;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = accent ?? colors.accent;

    return TidyCard(
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: muted ? 0.10 : 0.14),
              borderRadius: AppRadii.mdAll,
            ),
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.caption),
                Text(
                  value,
                  style: context.text.titleM.copyWith(
                    color: muted ? colors.textSecondary : colors.textPrimary,
                  ),
                ),
                Text(hint, style: context.text.caption, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessRow extends StatefulWidget {
  const _ProcessRow({
    required this.process,
    required this.icon,
    required this.busy,
    required this.isLast,
  });

  final ProcessSample process;
  final Uint8List? icon;
  final bool busy;
  final bool isLast;

  @override
  State<_ProcessRow> createState() => _ProcessRowState();
}

class _ProcessRowState extends State<_ProcessRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final process = widget.process;
    final cpu = process.cpuPercent;

    // Loud only when it is genuinely loud: a red number on anything above zero
    // would flag every idle app on the Mac.
    final cpuColor = cpu == null
        ? colors.textMuted
        : (cpu >= 60
              ? colors.risky
              : (cpu >= 20 ? colors.review : colors.textPrimary));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: context.motion.fast,
        curve: context.motion.standard,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _hovered ? colors.surfaceHover : Colors.transparent,
          border: widget.isLast
              ? null
              : Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: _Columns.name,
              child: Row(
                children: [
                  BundleIcon(
                    bytes: widget.icon,
                    size: 26,
                    fallback: process.isApp
                        ? AppIcons.appPlaceholder
                        : AppIcons.backgroundItems,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          process.name,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleS,
                        ),
                        Text('pid ${process.pid}', style: context.text.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _Columns.cpu,
              child: Text(
                cpu == null ? '—' : '${cpu.toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: context.text.bodyM.copyWith(color: cpuColor),
              ),
            ),
            SizedBox(
              width: _Columns.memory,
              child: Text(
                formatBytes(process.memoryBytes),
                textAlign: TextAlign.right,
                style: context.text.bodyM.copyWith(color: colors.textPrimary),
              ),
            ),
            SizedBox(width: _Columns.actions, child: _action(context)),
          ],
        ),
      ),
    );
  }

  Widget _action(BuildContext context) {
    final colors = context.colors;
    final process = widget.process;

    if (widget.busy) {
      return const Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (!process.quittable) {
      return Align(
        alignment: Alignment.centerRight,
        child: Icon(AppIcons.locked, size: 15, color: colors.textMuted),
      );
    }

    // Hover-only, like every other destructive row action in the app.
    return AnimatedOpacity(
      duration: context.motion.fast,
      opacity: _hovered ? 1 : 0,
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _hovered
              ? () => context.read<ProcessMonitorBloc>().add(
                  ProcessQuitRequested(process.pid),
                )
              : null,
          icon: Icon(AppIcons.quit, size: 14, color: colors.risky),
          label: Text(
            'Quit',
            style: context.text.label.copyWith(color: colors.risky),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            minimumSize: const Size(0, 28),
          ),
        ),
      ),
    );
  }
}
