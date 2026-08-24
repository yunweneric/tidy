import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/di/service_locator.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/features/apps/data/services/junk_scanner.dart';
import 'package:mac_uninstaller/features/apps/data/services/scan_cache.dart';
import 'package:mac_uninstaller/features/menubar/domain/menu_bar_insight.dart';
import 'package:mac_uninstaller/features/menubar/platform/popover_bridge.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/measure_size.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_button.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_insight_card.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_process_row.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_reclaim_row.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_section.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_vitals.dart';
import 'package:mac_uninstaller/features/performance/data/models/process_sample.dart';
import 'package:mac_uninstaller/features/performance/data/models/system_vitals.dart';
import 'package:mac_uninstaller/features/performance/data/services/performance_bridge.dart';
import 'package:mac_uninstaller/features/performance/data/services/process_monitor_service.dart';
import 'package:mac_uninstaller/features/recycle_bin/data/services/recycle_bin_service.dart';

/// Root of the menu bar popover engine.
class MenuBarPanelApp extends StatelessWidget {
  const MenuBarPanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The popover has no settings UI of its own, so it simply follows the
    // system appearance — which is also what the menu bar behind it does.
    return MaterialApp(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: TidyTheme.light(),
      darkTheme: TidyTheme.dark(),
      home: const MenuBarPanel(),
    );
  }
}

/// The panel behind the status item: how the machine is doing right now, the
/// one thing worth acting on, what is using it, and what can be handed back.
///
/// This deliberately does *not* list apps to uninstall. Uninstalling is a
/// considered decision about software you chose to install — it belongs in the
/// main window, next to leftovers, sizes and last-used dates. What a menu bar
/// is good at is the opposite: numbers that change while you work, and the one
/// action that answers them.
class MenuBarPanel extends StatefulWidget {
  const MenuBarPanel({super.key});

  @override
  State<MenuBarPanel> createState() => _MenuBarPanelState();
}

class _MenuBarPanelState extends State<MenuBarPanel> {
  /// How many live processes the panel lists. Enough to spot the culprit,
  /// short enough that the panel stays a glance rather than a table.
  static const int _consumerCount = 5;

  /// Matches the Performance page's cadence. Faster reads as noise, slower
  /// stops feeling live.
  static const Duration _tick = Duration(seconds: 2);

  late final PopoverBridge _bridge = PopoverBridge(
    onPopoverOpened: _onPopoverOpened,
    onPopoverClosed: _onPopoverClosed,
  );

  final ScanCache _cache = locator<ScanCache>();
  final JunkScanner _junkScanner = locator<JunkScanner>();
  final ProcessMonitorService _monitor = locator<ProcessMonitorService>();
  final RecycleBinService _recycleBin = locator<RecycleBinService>();

  SystemVitals _vitals = SystemVitals.empty;
  DiskUsage _disk = DiskUsage.empty;
  ProcessSnapshot _snapshot = ProcessSnapshot.empty;
  JunkReport _junk = JunkReport.empty;
  int _trashBytes = 0;

  ProcessSort _sort = ProcessSort.cpu;
  Timer? _ticker;

  /// The space scan — junk and Trash — is the slow half and runs on its own.
  bool _scanningSpace = true;
  bool _sampled = false;
  bool _busy = false;
  String? _status;
  DateTime? _updatedAt;

  /// The process whose inline quit confirmation is showing.
  int? _confirmingPid;
  final Set<int> _busyPids = {};

  @override
  void initState() {
    super.initState();
    // Sample once at launch so the first open is already populated, then let
    // the open/close callbacks own the timer.
    _monitor.start();
    _sample();
    _scanSpace();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ sampling

  /// One reading of everything that changes while you work.
  Future<void> _sample() async {
    final results = await Future.wait([
      PerformanceBridge.systemVitals(),
      _monitor.sample(),
      SystemBridge.diskUsage(),
    ]);
    if (!mounted) return;

    setState(() {
      _vitals = results[0] as SystemVitals;
      _snapshot = results[1] as ProcessSnapshot;
      _disk = results[2] as DiskUsage;
      _sampled = true;
      _updatedAt = DateTime.now();
    });
  }

  /// The expensive half: sizing every cache folder and every item in the
  /// Trash. Runs at launch and on an explicit refresh, never on the timer —
  /// a panel that walks the filesystem every two seconds is the problem, not
  /// the cleaner.
  Future<void> _scanSpace() async {
    final cached = await _cache.read();
    final apps = cached?.apps ?? const [];

    final junk = await _junkScanner.scan(installedApps: apps);
    if (mounted) setState(() => _junk = junk);

    final bin = await _recycleBin.load();
    if (!mounted) return;
    setState(() {
      _trashBytes = bin.totalBytes;
      _scanningSpace = false;
    });
  }

  void _onPopoverOpened() {
    _sample();
    _ticker?.cancel();
    _ticker = Timer.periodic(_tick, (_) => _sample());
  }

  void _onPopoverClosed() {
    _ticker?.cancel();
    _ticker = null;
    // Whatever was half-confirmed when the panel vanished is not still
    // confirmed the next time it opens.
    if (mounted && _confirmingPid != null) {
      setState(() => _confirmingPid = null);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _scanningSpace = true;
      _status = null;
    });
    await Future.wait([_sample(), _scanSpace()]);
  }

  // ------------------------------------------------------------------- actions

  Future<void> _clearJunk() async {
    final paths = _junk.pathsFor(
      JunkKind.values.where((kind) => kind.safeByDefault),
    );
    if (paths.isEmpty) return;

    final expected = _junk.safeBytes;
    setState(() => _busy = true);

    final result = await SystemBridge.trashItems(paths);
    final cached = await _cache.read();
    final junk = await _junkScanner.scan(
      installedApps: cached?.apps ?? const [],
    );
    final disk = await SystemBridge.diskUsage();
    final bin = await _recycleBin.load();
    if (!mounted) return;

    setState(() {
      _junk = junk;
      _disk = disk;
      _trashBytes = bin.totalBytes;
      _busy = false;
      _status = result.isCompleteSuccess
          ? '${formatBytes(expected)} moved to Trash'
          : '${result.failures.length} item(s) could not be removed';
    });
  }

  Future<void> _quit(ProcessSample process) async {
    setState(() {
      _confirmingPid = null;
      _busyPids.add(process.pid);
    });

    final outcome = await _monitor.quit(process.pid);
    if (!mounted) return;

    setState(() {
      _busyPids.remove(process.pid);
      _status = outcome.ok
          ? 'Asked ${process.name} to quit'
          : outcome.message ?? 'That process would not quit';
    });

    await _sample();
  }

  void _runInsightAction(MenuBarInsightAction action) {
    switch (action) {
      case MenuBarInsightAction.cleanJunk:
        _clearJunk();
      case MenuBarInsightAction.openApp:
        _bridge.openMainWindow();
    }
  }

  // --------------------------------------------------------------------- build

  List<ProcessSample> get _consumers => ProcessMonitorService.sorted(
    _snapshot.processes,
    _sort,
  ).take(_consumerCount).toList();

  MenuBarInsight get _insight {
    final byCpu = ProcessMonitorService.sorted(
      _snapshot.processes,
      ProcessSort.cpu,
    );
    final byMemory = ProcessMonitorService.sorted(
      _snapshot.processes,
      ProcessSort.memory,
    );

    return MenuBarInsight.of(
      vitals: _vitals,
      disk: _disk,
      junkBytes: _junk.safeBytes,
      trashBytes: _trashBytes,
      topCpu: byCpu.isEmpty ? null : byCpu.first,
      topMemory: byMemory.isEmpty ? null : byMemory.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    // One scroll view wrapping everything, with the measurement inside it: the
    // column is laid out at its natural height (unbounded by the scroll view),
    // which is exactly the height the popover should adopt. Measuring a
    // height-filling widget instead would just report the popover's current
    // size back to itself and never grow.
    return Scaffold(
      backgroundColor: context.colors.sidebar,
      body: SingleChildScrollView(
        child: MeasureSize(
          onChange: (size) => _bridge.setHeight(size.height),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md + 2,
                  AppSpacing.md,
                  AppSpacing.md + 2,
                  0,
                ),
                child: MenuBarVitals(vitals: _vitals, disk: _disk),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md + 2,
                  AppSpacing.sm + 2,
                  AppSpacing.md + 2,
                  0,
                ),
                child: MenuBarInsightCard(
                  insight: _insight,
                  enabled: !_busy,
                  onAction: _runInsightAction,
                ),
              ),
              _buildConsumers(),
              const Divider(height: 1),
              MenuBarSection(
                title: 'Reclaimable',
                trailing: _scanningSpace
                    ? 'scanning…'
                    : formatBytes(_junk.safeBytes + _trashBytes),
              ),
              MenuBarReclaimRow(
                icon: AppIcons.cleanup,
                title: 'Caches, logs & saved state',
                subtitle: 'Rebuilt automatically the next time an app runs',
                bytes: _junk.safeBytes,
                scanning: _scanningSpace && _junk.safeBytes == 0,
                actionLabel: 'Clean',
                onAction: _junk.safeBytes == 0 || _busy ? null : _clearJunk,
              ),
              MenuBarReclaimRow(
                icon: AppIcons.recycleBin,
                title: 'Trash',
                subtitle: 'Still taking up space until it is emptied',
                bytes: _trashBytes,
                scanning: _scanningSpace,
                actionLabel: 'Review',
                onAction: _bridge.openMainWindow,
              ),
              const Divider(height: 1),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final insight = _insight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md + 2,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Brand.mark, size: 15, color: context.colors.accent),
          const SizedBox(width: AppSpacing.sm),
          Text(Brand.name, style: context.text.titleS),
          const SizedBox(width: AppSpacing.sm),
          _StatusDot(level: insight.level),
          const Spacer(),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          MenuBarIconButton(
            icon: AppIcons.refresh,
            tooltip: 'Rescan',
            onPressed: _busy ? null : _refresh,
          ),
          MenuBarIconButton(
            icon: AppIcons.openExternal,
            tooltip: 'Open ${Brand.name}',
            onPressed: _bridge.openMainWindow,
          ),
        ],
      ),
    );
  }

  Widget _buildConsumers() {
    final consumers = _consumers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuBarSection(
          title: 'Using the most',
          action: _SortToggle(
            sort: _sort,
            onChanged: (sort) => setState(() => _sort = sort),
          ),
        ),
        if (!_sampled)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          for (final process in consumers)
            MenuBarProcessRow(
              process: process,
              icon: process.bundlePath == null
                  ? null
                  : _monitor.icons[process.bundlePath],
              sort: _sort,
              confirming: _confirmingPid == process.pid,
              busy: _busyPids.contains(process.pid),
              enabled: !_busy,
              onQuitPressed: () =>
                  setState(() => _confirmingPid = process.pid),
              onCancel: () => setState(() => _confirmingPid = null),
              onConfirm: () => _quit(process),
            ),
      ],
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md + 2,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _status ?? _footerLabel(),
              style: context.text.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          MenuBarButton(label: 'Quit', onPressed: _bridge.quitApp),
        ],
      ),
    );
  }

  String _footerLabel() {
    final parts = <String>[
      if (_vitals.isKnown) 'Up ${_vitals.uptimeLabel}',
      if (_snapshot.processes.isNotEmpty)
        '${_snapshot.processes.length} processes',
      if (_updatedAt != null) 'updated ${_clock(_updatedAt!)}',
    ];
    return parts.isEmpty ? 'Reading your Mac…' : parts.join(' · ');
  }

  static String _clock(DateTime at) {
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// A coloured dot next to the app name, so the panel's verdict is legible
/// before any of it has been read.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.level});

  final VitalLevel level;

  @override
  Widget build(BuildContext context) {
    final color = colorForLevel(context, level);

    return Tooltip(
      message: switch (level) {
        VitalLevel.good => 'Nothing needs attention',
        VitalLevel.watch => 'Worth a look',
        VitalLevel.urgent => 'Needs attention',
      },
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// CPU or memory, for the live list. Two options, so a pair of text buttons
/// rather than the app's full segmented control.
class _SortToggle extends StatelessWidget {
  const _SortToggle({required this.sort, required this.onChanged});

  final ProcessSort sort;
  final ValueChanged<ProcessSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in const [ProcessSort.cpu, ProcessSort.memory])
          _Option(
            label: option.label,
            selected: sort == option,
            onTap: () => onChanged(option),
          ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs + 1,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.surfaceRaised : Colors.transparent,
          borderRadius: AppRadii.smAll,
        ),
        child: Text(
          label,
          style: context.text.caption.copyWith(
            color: selected ? colors.textPrimary : colors.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
