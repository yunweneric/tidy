import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/features/apps/data/services/junk_scanner.dart';
import 'package:tidy/features/apps/data/services/scan_cache.dart';
import 'package:tidy/core/models/clipboard_entry.dart';
import 'package:tidy/features/clipboard/data/services/clipboard_service.dart';
import 'package:tidy/core/insights/health_insight.dart';
import 'package:tidy/core/widgets/usage_window_row.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_summary.dart';
import 'package:tidy/features/ai_usage/data/models/ai_window_style.dart';
import 'package:tidy/features/ai_usage/data/services/ai_usage_bridge.dart';
import 'package:tidy/features/menubar/domain/menu_bar_surface.dart';
import 'package:tidy/features/menubar/platform/popover_bridge.dart';
import 'package:tidy/features/menubar/presentation/widgets/measure_size.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_button.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_clip_row.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_insight_card.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_network.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_process_row.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_reclaim_row.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_section.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_tabs.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_vitals.dart';
import 'package:tidy/features/network/data/models/network_sample.dart';
import 'package:tidy/core/models/network_series.dart';
import 'package:tidy/features/network/data/models/network_units.dart';
import 'package:tidy/features/network/data/services/network_service.dart';
import 'package:tidy/core/vitals/process_sample.dart';
import 'package:tidy/core/vitals/system_vitals.dart';
import 'package:tidy/features/performance/data/services/performance_bridge.dart';
import 'package:tidy/features/performance/data/services/process_monitor_service.dart';
import 'package:tidy/core/models/trash_item.dart';
import 'package:tidy/features/recycle_bin/data/services/recycle_bin_service.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';

/// Root of the menu bar popover engine.
///
/// Owns the one [PopoverBridge] — a method channel holds a single handler, so
/// a second bridge anywhere in this engine would quietly steal the callbacks
/// from the first.
class MenuBarPanelApp extends StatefulWidget {
  const MenuBarPanelApp({super.key});

  @override
  State<MenuBarPanelApp> createState() => _MenuBarPanelAppState();
}

class _MenuBarPanelAppState extends State<MenuBarPanelApp> {
  late final PopoverBridge _bridge = PopoverBridge(
    onAppearanceChanged: (dark) {
      if (mounted) setState(() => _dark = dark);
    },
  );

  /// Null until macOS has answered. `ThemeMode.system` is not good enough here:
  /// this engine runs headless, and has been seen reporting a light platform
  /// brightness while the popover behind it is dark — which paints dark text
  /// onto a dark panel.
  bool? _dark;

  @override
  void initState() {
    super.initState();
    _bridge.isDarkAppearance().then((dark) {
      if (mounted) setState(() => _dark = dark);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      themeMode: switch (_dark) {
        true => ThemeMode.dark,
        false => ThemeMode.light,
        null => ThemeMode.system,
      },
      theme: TidyTheme.light(),
      darkTheme: TidyTheme.dark(),
      home: MenuBarPanel(bridge: _bridge),
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
  const MenuBarPanel({super.key, required this.bridge});

  final PopoverBridge bridge;

  @override
  State<MenuBarPanel> createState() => _MenuBarPanelState();
}

class _MenuBarPanelState extends State<MenuBarPanel> {
  /// How many live processes the panel lists. Enough to spot the culprit,
  /// short enough that the panel stays a glance rather than a table.
  static const int _consumerCount = 5;

  /// How many recent clips the dashboard's teaser lists. Enough to cover "the
  /// thing before the thing I have now", short enough that it stays a glance.
  static const int _clipCount = 6;

  /// How many the clipboard panel lists. Longer, because there the clips are
  /// not a teaser — they are what the user came for.
  static const int _clipboardPanelCount = 14;

  /// Matches the Performance page's cadence. Faster reads as noise, slower
  /// stops feeling live.
  static const Duration _tick = Duration(seconds: 2);

  PopoverBridge get _bridge => widget.bridge;

  final ScanCache _cache = locator<ScanCache>();
  final JunkScanner _junkScanner = locator<JunkScanner>();
  final ProcessMonitorService _monitor = locator<ProcessMonitorService>();
  final RecycleBinService _recycleBin = locator<RecycleBinService>();
  final ClipboardService _clipboard = locator<ClipboardService>();
  final NetworkService _network = locator<NetworkService>();

  SystemVitals _vitals = SystemVitals.empty;
  DiskUsage _disk = DiskUsage.empty;
  ProcessSnapshot _snapshot = ProcessSnapshot.empty;
  JunkReport _junk = JunkReport.empty;
  int _trashBytes = 0;

  /// False when macOS refused to list the Trash — it is behind Full Disk
  /// Access. An unreadable bin reported as an empty one tells the user there is
  /// nothing to reclaim when there may be gigabytes.
  bool _trashReadable = true;

  ProcessSort _sort = ProcessSort.cpu;
  Timer? _ticker;

  /// Which surface the panel is answering for.
  ///
  /// One Flutter view, several panels. An icon means something and the panel
  /// shows what its icon promised — a clipboard icon that opened a disk report
  /// would be a worse lie than having no clipboard icon at all. In the
  /// consolidated layout the tab strip is the promise instead.
  MenuBarSurface _surface = MenuBarSurface.fallback;

  /// How many icons are on the bar, which decides whether the tab strip shows.
  ///
  /// Arrives with every open rather than being read from settings: this engine
  /// has no `AppSettings` (`includeUi: false`), and the native side is the one
  /// that acted on the preference anyway — asking it what it did is a shorter
  /// path to the truth than reading the file it read.
  MenuBarLayout _layout = MenuBarLayout.consolidated;

  /// How to draw a usage window. Arrives with every open for the same reason
  /// the layout does — this engine has no `AppSettings` to read it from, and
  /// the native side is holding the value the user last chose.
  AiWindowStyle _windowStyle = AiWindowStyle.expanded;

  /// The menu bar's slice of the AI usage report, or null when there is none.
  ///
  /// Null renders as "nothing measured yet", which is not the same claim as a
  /// day with no usage. Computed in the main engine and served by the native
  /// store — see [AiUsageBridge] for why it cannot be computed here.
  AiUsageSummary? _summary;

  List<ClipboardEntry> _clips = const [];
  StreamSubscription<void>? _clipSubscription;

  /// The network readings arrive pushed rather than polled, so they get their
  /// own subscription instead of riding the two-second ticker.
  NetworkSample _traffic = NetworkSample.unknown;
  List<NetworkTick> _trafficTicks = const [];
  NetworkHeadline _trafficTotals = NetworkHeadline.empty;
  StreamSubscription<NetworkSample>? _trafficSubscription;

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
    _bridge.onPopoverOpened = _onPopoverOpened;
    _bridge.onPopoverClosed = _onPopoverClosed;
    // Sample once at launch so the first open is already populated, then let
    // the open/close callbacks own the timer.
    _monitor.start();
    _sample();
    _scanSpace();

    // The clipboard pushes rather than polling, so this costs nothing while
    // nothing is being copied.
    _clipSubscription = _clipboard.onChanged.listen((_) => _loadClips());
    _loadClips();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _clipSubscription?.cancel();
    _trafficSubscription?.cancel();
    _network.stopLive();
    _bridge.onPopoverOpened = null;
    _bridge.onPopoverClosed = null;
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
      _trashReadable = _isReadable(bin);
      _scanningSpace = false;
    });
  }

  /// Nothing listed at all counts as unreadable too: the home bin always
  /// exists, so an empty set of locations means macOS answered with a refusal
  /// rather than with a bin.
  static bool _isReadable(TrashSnapshot bin) =>
      bin.locations.isNotEmpty &&
      bin.locations.any((location) => location.readable);

  Future<void> _loadClips() async {
    final entries = await _clipboard.history();
    if (!mounted) return;
    setState(() => _clips = entries.take(_clipboardPanelCount).toList());
  }

  /// Clicking a clip puts it back on the pasteboard and gets out of the way.
  ///
  /// Closing is the point: the reason anyone opens this panel is to paste
  /// something next, and a panel still sitting over the document they are
  /// pasting into is a second click they should not have to make.
  Future<void> _copyClip(ClipboardEntry entry) async {
    final outcome = await _clipboard.copyToClipboard(entry);
    if (!mounted) return;

    _bridge.hideClipPreview();
    if (outcome.ok) {
      _bridge.close();
      return;
    }
    setState(() {
      _status = outcome.message ?? 'That could not be copied';
    });
  }

  /// The pointer moved onto a clip, or off one. The preview is a native window
  /// beside the panel — see `ClipPreviewPanel` for why it cannot live inside
  /// the popover.
  void _previewClip(ClipboardEntry entry, double? rowTop) {
    if (rowTop == null) {
      _bridge.hideClipPreview();
      return;
    }
    _bridge.showClipPreview(id: entry.id, top: rowTop);
  }

  /// The clipboard icon and ⌘⇧V both open the panel asking for "clipboard";
  /// the vitals icon asks for nothing. Each gets a whole panel of its own.
  void _onPopoverOpened(PopoverOpening opening) {
    _layout = MenuBarLayout.fromName(opening.layout);
    _windowStyle = AiWindowStyle.fromName(opening.aiWindowStyle);
    _showSurface(
      MenuBarSurface.tryParse(opening.section) ?? MenuBarSurface.fallback,
    );
  }

  /// A tab click in the consolidated layout.
  ///
  /// Tells the native side as well as switching locally. Swift owns the
  /// popover's width and the height it remembers per section, so a tab that
  /// only changed the Dart state would leave the panel the previous section's
  /// height until the next open.
  void _selectSurface(MenuBarSurface surface) {
    if (surface == _surface) return;
    _showSurface(surface);
    _bridge.setSection(surface.id);
  }

  /// Points the panel at [surface] and starts or stops what it needs.
  ///
  /// Shared by the open handler and the consolidated layout's tab strip, and
  /// that sharing is the point rather than tidiness: this is the only place
  /// that knows a surface costs a two-second ticker or a live native tap, so a
  /// tab that only set the field would leave the vitals sampling behind a
  /// clipboard list, forever.
  void _showSurface(MenuBarSurface surface) {
    setState(() => _surface = surface);
    _loadClips();

    _ticker?.cancel();
    _ticker = null;
    // Nothing on the other panels is sampled, so the two-second tick that
    // feeds the vitals has no reason to run behind them.
    if (surface == MenuBarSurface.dashboard) {
      _sample();
      _ticker = Timer.periodic(_tick, (_) => _sample());
    }

    // The dashboard carries a one-line traffic row and the network panel is
    // made of it, so both want the readings; the others do not.
    _setTrafficLive(
      surface == MenuBarSurface.dashboard || surface == MenuBarSurface.network,
    );
    if (surface == MenuBarSurface.network) _loadTrafficTotals();
    if (surface == MenuBarSurface.aiUsage) _loadAiUsage();
  }

  /// Reads the last summary the main engine published.
  ///
  /// A read, never a sweep. The sweep is 16 seconds over a gigabyte and a half
  /// on a cold start, and this engine exists to draw a panel in under a frame.
  Future<void> _loadAiUsage() async {
    final summary = await AiUsageBridge.read();
    if (!mounted) return;
    setState(() => _summary = summary);
  }

  /// Opens or closes the native tap.
  ///
  /// The sampler runs regardless — it feeds the menu bar readout and the
  /// history — so this costs nothing but the push into this isolate, which is
  /// the part worth switching off behind a closed popover.
  Future<void> _setTrafficLive(bool live) async {
    if (live == (_trafficSubscription != null)) return;

    if (!live) {
      await _trafficSubscription?.cancel();
      _trafficSubscription = null;
      await _network.stopLive();
      return;
    }

    _trafficSubscription = _network.onSample.listen(_onTraffic);
    final sample = await _network.startLive();
    if (sample.isKnown) _onTraffic(sample);
  }

  void _onTraffic(NetworkSample sample) {
    if (!mounted) return;
    // The first payload of a subscription carries the sampler's whole ring, so
    // the chart is populated before the next tick arrives.
    final ticks =
        sample.recent.isNotEmpty
            ? List<NetworkTick>.from(sample.recent)
            : <NetworkTick>[..._trafficTicks, sample.tick];
    if (ticks.length > 300) ticks.removeRange(0, ticks.length - 300);

    setState(() {
      _traffic = sample;
      _trafficTicks = ticks;
    });
  }

  Future<void> _loadTrafficTotals() async {
    final totals = await _network.headline();
    if (!mounted) return;
    setState(() => _trafficTotals = totals);
  }

  void _onPopoverClosed() {
    _bridge.hideClipPreview();
    _ticker?.cancel();
    _ticker = null;
    _setTrafficLive(false);
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
      _trashReadable = _isReadable(bin);
      _busy = false;
      _status =
          result.isCompleteSuccess
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
      _status =
          outcome.ok
              ? 'Asked ${process.name} to quit'
              : outcome.message ?? 'That process would not quit';
    });

    await _sample();
  }

  void _runInsightAction(HealthInsightAction action) {
    switch (action) {
      case HealthInsightAction.cleanJunk:
        _clearJunk();
      case HealthInsightAction.openApp:
        _bridge.openMainWindow();
    }
  }

  // --------------------------------------------------------------------- build

  List<ProcessSample> get _consumers =>
      ProcessMonitorService.sorted(
        _snapshot.processes,
        _sort,
      ).take(_consumerCount).toList();

  HealthInsight get _insight {
    final byCpu = ProcessMonitorService.sorted(
      _snapshot.processes,
      ProcessSort.cpu,
    );
    final byMemory = ProcessMonitorService.sorted(
      _snapshot.processes,
      ProcessSort.memory,
    );

    return HealthInsight.of(
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
      // Transparent on purpose. `MenuBarController` clears the Flutter view's
      // background so what sits behind the panel is the popover's own material
      // — the same blurred, appearance-following backdrop as a macOS menu.
      // Painting a surface here would cover it with a flat rectangle.
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        child: MeasureSize(
          onChange: (size) => _bridge.setHeight(size.height),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              // Only in the consolidated layout. In the separate layout each
              // icon already promised one surface, and a strip offering three
              // more would make the icon a lie.
              if (_layout.isConsolidated) ...[
                const Divider(height: 1),
                MenuBarTabs(selected: _surface, onChanged: _selectSurface),
              ],
              const Divider(height: 1),
              ...switch (_surface) {
                MenuBarSurface.dashboard => _dashboardBody(),
                MenuBarSurface.aiUsage => _aiUsageBody(),
                MenuBarSurface.clipboard => _clipboardBody(),
                MenuBarSurface.network => _networkBody(),
              },
              const Divider(height: 1),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  /// Everything the vitals icon promises: how the machine is doing, the one
  /// thing worth acting on, what is using it, what can be handed back.
  List<Widget> _dashboardBody() {
    return [
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
      _buildTraffic(),
      _buildConsumers(),
      _buildClips(),
      const Divider(height: 1),
      MenuBarSection(
        title: 'Reclaimable',
        trailing:
            _scanningSpace
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
        subtitle:
            _trashReadable
                ? 'Still taking up space until it is emptied'
                : 'macOS keeps the Trash behind Full Disk Access',
        bytes: _trashBytes,
        scanning: _scanningSpace,
        note: _trashReadable || _scanningSpace ? null : 'can’t read it',
        actionLabel: _trashReadable ? 'Review' : 'Grant',
        onAction:
            _trashReadable
                ? _bridge.openMainWindow
                : SystemBridge.openFullDiskAccessSettings,
      ),
    ];
  }

  /// Everything the network readout promises: what is moving now, over which
  /// link, and how much has gone this day and this month.
  ///
  /// No history charts here. A month of daily bars needs an axis and room to
  /// read it, which a 320pt popover does not have — that is what the page is
  /// for, and the button at the bottom goes straight to it.
  List<Widget> _networkBody() {
    // The units ride along with the reading: this engine is started with
    // `includeUi: false` and has no `AppSettings` to read them from.
    final units = _traffic.units;

    return [
      MenuBarNetworkNow(sample: _traffic, ticks: _trafficTicks, units: units),
      const SizedBox(height: AppSpacing.sm),
      const Divider(height: 1),
      const MenuBarSection(title: 'Recorded'),
      MenuBarNetworkTotal(
        label: 'Today',
        headline: _trafficTotals,
        month: false,
      ),
      MenuBarNetworkTotal(
        label: 'This month',
        headline: _trafficTotals,
        month: true,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md + 2,
          AppSpacing.sm,
          AppSpacing.md + 2,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _trafficTotals.startedAt == null
                    ? 'Recorded while ${Brand.name} is running'
                    : 'While ${Brand.name} has been running',
                style: context.text.caption,
              ),
            ),
            MenuBarButton(
              label: 'Open Network',
              tone: MenuBarButtonTone.filled,
              onPressed:
                  () => _bridge.openMainWindow(
                    route: AppDestination.network.path,
                  ),
            ),
          ],
        ),
      ),
    ];
  }

  /// What the AI tools have got through today, and what it would have cost.
  ///
  /// Every figure here is what the same tokens would cost at published API
  /// rates. **Not a bill** — both CLIs run on flat-fee subscriptions, and the
  /// page says so at length. A popover has room for one line of it, so that
  /// line is the last thing in the panel rather than the first thing cut.
  List<Widget> _aiUsageBody() {
    final summary = _summary;
    final text = context.text;
    final colors = context.colors;

    if (summary == null || summary.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + 2,
            vertical: AppSpacing.xl,
          ),
          child: Column(
            children: [
              Icon(AppIcons.aiUsage, size: 26, color: colors.textMuted),
              const SizedBox(height: AppSpacing.sm),
              Text(
                summary == null ? 'Nothing measured yet' : 'Nothing used today',
                style: text.titleS,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                // Two different facts, and the panel is careful which it
                // claims. No summary means the window has not read the logs
                // since Tidy started; an empty one means it read them and you
                // had not used the tools today.
                summary == null
                    ? 'Open ${Brand.name} once and the menu bar keeps up from '
                        'there.'
                    : 'That is a quiet day, not a failed reading.',
                textAlign: TextAlign.center,
                style: text.caption,
              ),
              const SizedBox(height: AppSpacing.md),
              MenuBarButton(
                label: 'Open AI Usage',
                tone: MenuBarButtonTone.filled,
                onPressed:
                    () => _bridge.openMainWindow(
                      route: AppDestination.aiUsage.path,
                    ),
              ),
            ],
          ),
        ),
      ];
    }

    // One reading for every row in this build, so two countdowns cannot
    // disagree by a minute because they were built either side of one.
    final now = DateTime.now();

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md + 2,
          AppSpacing.md,
          AppSpacing.md + 2,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TODAY',
                    style: text.overline.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    formatUsd(summary.costToday),
                    style: text.displayL.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${formatCount(summary.tokensToday)} tokens',
                  style: text.bodyM,
                ),
                Text(
                  '${summary.repliesToday} replies · '
                  '${summary.sessionsToday} '
                  '${summary.sessionsToday == 1 ? 'session' : 'sessions'}',
                  style: text.caption,
                ),
              ],
            ),
          ],
        ),
      ),
      // One card, a section per provider, a row per window — the shape of the
      // question people actually ask the icon: how much is left, and when does
      // it come back. What each row is allowed to claim differs by provider and
      // is decided in `AiUsageWindow`, not here.
      if (summary.windows.isNotEmpty) ...[
        const Divider(height: 1),
        const MenuBarSection(title: 'Usage'),
        for (final provider in summary.providersWithWindows) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md + 2,
              AppSpacing.xxs,
              AppSpacing.md + 2,
              AppSpacing.xxs,
            ),
            child: Text(
              provider.label,
              style: text.titleS.copyWith(color: colors.textPrimary),
            ),
          ),
          for (final window in summary.windowsFor(provider))
            UsageWindowRow(window: window, now: now, style: _windowStyle),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (summary.windows.any((window) => !window.isMeasured))
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md + 2,
              0,
              AppSpacing.md + 2,
              AppSpacing.sm,
            ),
            child: Text(
              // Said once, at the bottom, rather than on every row it applies
              // to. The rows already differ — a percentage against tokens — and
              // this is the sentence that explains why they do.
              'Claude Code publishes no limit, so its windows show what went '
              'through them rather than a share of an allowance.',
              style: text.caption,
            ),
          ),
      ],
      if (summary.topModels.isNotEmpty) ...[
        const Divider(height: 1),
        const MenuBarSection(title: 'Models'),
        for (final model in summary.topModels)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md + 2,
              AppSpacing.xxs,
              AppSpacing.md + 2,
              AppSpacing.xxs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    model.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyM,
                  ),
                ),
                Text(formatCount(model.tokens), style: text.caption),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 62,
                  child: Text(
                    // A dash, never a zero. Nobody publishes a per-token rate
                    // for the Codex models, and `$0.00` would say those tokens
                    // were free rather than unpriced.
                    model.priced ? formatUsd(model.cost) : '—',
                    textAlign: TextAlign.right,
                    style: text.bodyM.copyWith(
                      color:
                          model.priced ? colors.textPrimary : colors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md + 2,
          AppSpacing.sm,
          AppSpacing.md + 2,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                summary.hasUnpricedModels
                    ? 'At API rates, not a bill. Some models have no published '
                        'rate.'
                    : 'At API rates, not a bill.',
                style: text.caption,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            MenuBarButton(
              label: 'Open AI Usage',
              tone: MenuBarButtonTone.filled,
              onPressed:
                  () => _bridge.openMainWindow(
                    route: AppDestination.aiUsage.path,
                  ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Everything the clipboard icon promises: what you copied, most recent
  /// first, one click to put it back on the pasteboard.
  List<Widget> _clipboardBody() {
    if (_clips.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                AppIcons.clipboard,
                size: 22,
                color: context.colors.textMuted,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Nothing copied yet',
                style: context.text.label,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Anything you copy shows up here. If it stays empty, the '
                'recorder is off — turn it on in Settings.',
                style: context.text.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              MenuBarButton(
                label: 'Open Clipboard',
                tone: MenuBarButtonTone.filled,
                onPressed:
                    () => _bridge.openMainWindow(
                      route: AppDestination.clipboard.path,
                    ),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      MenuBarSection(
        title: 'Recent clips',
        action: MenuBarButton(
          label: 'Open',
          onPressed:
              () =>
                  _bridge.openMainWindow(route: AppDestination.clipboard.path),
        ),
      ),
      for (final entry in _clips)
        MenuBarClipRow(
          key: ValueKey(entry.id),
          entry: entry,
          onCopy: () => _copyClip(entry),
          onHover: (top) => _previewClip(entry, top),
        ),
    ];
  }

  /// One line of traffic on the dashboard, so the main panel answers "is
  /// something uploading right now" without switching icons.
  ///
  /// A line rather than the network panel's chart: the dashboard is already
  /// three vitals tiles, an insight, a process table and two reclaim rows, and
  /// a second chart in it would push the thing the user actually opened it for
  /// below the fold.
  Widget _buildTraffic() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        MenuBarSection(
          title: 'Network',
          action: MenuBarButton(
            label: 'Open',
            onPressed:
                () =>
                    _bridge.openMainWindow(route: AppDestination.network.path),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md + 2,
            0,
            AppSpacing.md + 2,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                AppIcons.downstream,
                size: 13,
                color: context.colors.downstream,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _traffic.isKnown
                    ? formatRate(
                      _traffic.downBytesPerSecond,
                      units: _traffic.units,
                    )
                    : '—',
                style: context.text.label,
              ),
              const SizedBox(width: AppSpacing.lg),
              Icon(AppIcons.upstream, size: 13, color: context.colors.upstream),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _traffic.isKnown
                    ? formatRate(
                      _traffic.upBytesPerSecond,
                      units: _traffic.units,
                    )
                    : '—',
                style: context.text.label,
              ),
              const Spacer(),
              Text(
                _traffic.busiest?.label ?? 'idle',
                style: context.text.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Recent clips.
  ///
  /// Absent rather than empty when there is nothing: the recorder is off until
  /// the user turns it on, and a permanently blank section in a panel this
  /// small would be advertising, not information.
  Widget _buildClips() {
    if (_clips.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        MenuBarSection(
          title: 'Recent clips',
          action: MenuBarButton(
            label: 'Open',
            onPressed:
                () => _bridge.openMainWindow(
                  route: AppDestination.clipboard.path,
                ),
          ),
        ),
        for (final entry in _clips.take(_clipCount))
          MenuBarClipRow(
            key: ValueKey(entry.id),
            entry: entry,
            onCopy: () => _copyClip(entry),
            onHover: (top) => _previewClip(entry, top),
          ),
      ],
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
          Text(
            _surface == MenuBarSurface.dashboard ? Brand.name : _surface.label,
            style: context.text.titleS,
          ),
          const SizedBox(width: AppSpacing.sm),
          // The dot is a verdict about the machine, and the clipboard panel
          // makes no claim about the machine.
          if (_surface == MenuBarSurface.dashboard)
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
            tooltip: _surface == MenuBarSurface.dashboard ? 'Rescan' : 'Reload',
            onPressed:
                _busy
                    ? null
                    : switch (_surface) {
                      MenuBarSurface.clipboard => _loadClips,
                      MenuBarSurface.network => _loadTrafficTotals,
                      MenuBarSurface.aiUsage => _loadAiUsage,
                      MenuBarSurface.dashboard => _refresh,
                    },
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
              icon:
                  process.bundlePath == null
                      ? null
                      : _monitor.icons[process.bundlePath],
              sort: _sort,
              confirming: _confirmingPid == process.pid,
              busy: _busyPids.contains(process.pid),
              enabled: !_busy,
              onQuitPressed: () => setState(() => _confirmingPid = process.pid),
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
    if (_surface == MenuBarSurface.clipboard) {
      if (_clips.isEmpty) return 'Clipboard history is empty';
      return '${_clips.length} recent ${_clips.length == 1 ? 'clip' : 'clips'}';
    }

    if (_surface == MenuBarSurface.network) {
      final busiest = _traffic.busiest;
      if (busiest == null) return 'Nothing moving right now';
      return 'Live over ${busiest.label}';
    }

    if (_surface == MenuBarSurface.aiUsage) {
      final summary = _summary;
      if (summary == null) return 'No reading yet';
      return 'Last 7 days · ${formatUsd(summary.costLastSevenDays)}';
    }

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
