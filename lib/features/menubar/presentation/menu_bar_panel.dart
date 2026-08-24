import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/data/services/apps_service.dart';
import 'package:mac_uninstaller/features/apps/data/services/junk_scanner.dart';
import 'package:mac_uninstaller/features/apps/data/services/leftover_scanner.dart';
import 'package:mac_uninstaller/features/apps/data/services/scan_cache.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';
import 'package:mac_uninstaller/features/menubar/platform/popover_bridge.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/measure_size.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_app_row.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_disk_bar.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_section.dart';

/// Root of the menu bar popover engine.
class MenuBarPanelApp extends StatelessWidget {
  const MenuBarPanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MacUninstaller',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const MenuBarPanel(),
    );
  }
}

/// Compact panel shown from the menu bar: what is eating disk space, and a way
/// to remove it without opening the main window.
class MenuBarPanel extends StatefulWidget {
  const MenuBarPanel({super.key});

  @override
  State<MenuBarPanel> createState() => _MenuBarPanelState();
}

class _MenuBarPanelState extends State<MenuBarPanel> {
  /// How many space consumers the panel lists.
  static const int _topAppCount = 8;

  late final PopoverBridge _bridge = PopoverBridge(onPopoverOpened: _onPopoverOpened);
  final AppManagerService _service = AppManagerService();
  final ScanCache _cache = ScanCache();
  final JunkScanner _junkScanner = JunkScanner();
  final LeftoverScanner _leftoverScanner = LeftoverScanner();

  List<MacApp> _apps = const [];
  DiskUsage _disk = DiskUsage.empty;
  JunkReport _junk = JunkReport.empty;

  bool _loading = true;
  bool _busy = false;
  String? _status;

  /// Path of the app whose inline confirmation is showing.
  String? _confirmingPath;
  _PendingRemoval? _pending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Cached data paints immediately; the fresh scan lands a moment later.
  Future<void> _load() async {
    final cached = await _cache.read();
    if (cached != null && cached.apps.isNotEmpty && mounted) {
      setState(() {
        _apps = cached.apps;
        _loading = false;
      });
    }

    final disk = await SystemBridge.diskUsage();
    if (mounted) setState(() => _disk = disk);

    final apps = await _service.scanApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });

    // Icons only matter for the handful of rows on screen here.
    final top = _topApps(apps);
    final icons = await SystemBridge.iconsForPaths(
      top.map((app) => app.path).toList(),
      size: 32,
    );
    if (icons.isNotEmpty && mounted) {
      setState(() {
        _apps = [
          for (final app in _apps)
            icons[app.path] == null
                ? app
                : app.copyWith(iconBytes: icons[app.path]),
        ];
      });
    }
    await _cache.write(_apps);

    final junk = await _junkScanner.scan(installedApps: _apps);
    if (mounted) setState(() => _junk = junk);
  }

  void _onPopoverOpened() {
    // Re-read cheaply on every open so removals made in the main window show up.
    _cache.read().then((cached) {
      if (cached != null && mounted) setState(() => _apps = cached.apps);
    });
    SystemBridge.diskUsage().then((disk) {
      if (mounted) setState(() => _disk = disk);
    });
  }

  List<MacApp> _topApps(List<MacApp> apps) {
    final removable = apps.where((app) => !app.isSystem).toList()
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return removable.take(_topAppCount).toList();
  }

  // ------------------------------------------------------------------- actions

  /// Step 1 of removal: scan leftovers so the confirmation can say exactly what
  /// goes and how much it frees.
  Future<void> _startRemoval(MacApp app) async {
    setState(() {
      _confirmingPath = app.path;
      _pending = null;
    });

    final leftovers = await _leftoverScanner.scan(app);
    if (!mounted || _confirmingPath != app.path) return;

    setState(() {
      _pending = _PendingRemoval(
        app: app,
        paths: [app.path, ...leftovers.map((item) => item.path)],
        totalBytes:
            app.sizeBytes +
            leftovers.fold<int>(0, (sum, item) => sum + item.sizeBytes),
        leftoverCount: leftovers.length,
      );
    });
  }

  /// Step 2: actually move everything to the Trash.
  Future<void> _confirmRemoval() async {
    final pending = _pending;
    if (pending == null) return;

    setState(() {
      _busy = true;
      _confirmingPath = null;
      _pending = null;
    });

    final result = await SystemBridge.trashItems(pending.paths);
    if (!mounted) return;

    final removed = result.removed.toSet();
    if (removed.contains(pending.app.path)) {
      _apps = _apps.where((app) => app.path != pending.app.path).toList();
      await _cache.removeApps([pending.app.path]);
    }

    final disk = await SystemBridge.diskUsage();
    if (!mounted) return;

    setState(() {
      _disk = disk;
      _busy = false;
      _status = result.isCompleteSuccess
          ? '${formatBytes(pending.totalBytes)} moved to Trash'
          : '${result.failures.length} item(s) could not be removed';
    });
  }

  Future<void> _clearJunk() async {
    final paths = _junk.pathsFor(
      JunkKind.values.where((kind) => kind.safeByDefault),
    );
    if (paths.isEmpty) return;

    final expected = _junk.safeBytes;
    setState(() => _busy = true);

    final result = await SystemBridge.trashItems(paths);
    final junk = await _junkScanner.scan(installedApps: _apps);
    final disk = await SystemBridge.diskUsage();
    if (!mounted) return;

    setState(() {
      _junk = junk;
      _disk = disk;
      _busy = false;
      _status = result.isCompleteSuccess
          ? '${formatBytes(expected)} of junk moved to Trash'
          : '${result.failures.length} item(s) could not be removed';
    });
  }

  // --------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    // One scroll view wrapping everything, with the measurement inside it: the
    // column is laid out at its natural height (unbounded by the scroll view),
    // which is exactly the height the popover should adopt. Measuring a
    // height-filling widget instead would just report the popover's current
    // size back to itself and never grow.
    return Scaffold(
      backgroundColor: AppTheme.backgroundSidebar,
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
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: MenuBarDiskBar(disk: _disk, reclaimable: _junk.safeBytes),
              ),
              _buildJunkRow(),
              const SizedBox(height: 4),
              MenuBarSection(
                title: 'Largest apps',
                trailing: _loading ? 'scanning…' : '${_apps.length} installed',
              ),
              if (_loading && _apps.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                for (final app in _topApps(_apps))
                  MenuBarAppRow(
                    app: app,
                    confirming: _confirmingPath == app.path,
                    pendingLabel: _pendingLabelFor(app),
                    enabled: !_busy,
                    onRemovePressed: () => _startRemoval(app),
                    onCancel: () => setState(() {
                      _confirmingPath = null;
                      _pending = null;
                    }),
                    onConfirm: _pending == null ? null : _confirmRemoval,
                  ),
              const Divider(height: 1),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  String? _pendingLabelFor(MacApp app) {
    if (_confirmingPath != app.path) return null;
    final pending = _pending;
    if (pending == null) return 'Checking for leftovers…';
    return pending.leftoverCount == 0
        ? 'Frees ${formatBytes(pending.totalBytes)}'
        : 'App + ${pending.leftoverCount} leftover${pending.leftoverCount == 1 ? '' : 's'} · '
              'frees ${formatBytes(pending.totalBytes)}';
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.cleaning_services, size: 16, color: AppTheme.accentBlue),
          const SizedBox(width: 8),
          Text(
            'MacUninstaller',
            style: AppTheme.bodyPrimary.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          _IconAction(
            icon: Icons.refresh,
            tooltip: 'Rescan',
            onPressed: _busy
                ? null
                : () {
                    setState(() {
                      _loading = true;
                      _status = null;
                    });
                    _load();
                  },
          ),
          _IconAction(
            icon: Icons.open_in_new,
            tooltip: 'Open full app',
            onPressed: _bridge.openMainWindow,
          ),
        ],
      ),
    );
  }

  Widget _buildJunkRow() {
    final reclaimable = _junk.safeBytes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          const Icon(Icons.delete_sweep_outlined, size: 16, color: AppTheme.accentOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reclaimable == 0
                  ? 'No cache or log junk found'
                  : '${formatBytes(reclaimable)} in caches, logs & saved state',
              style: AppTheme.bodySecondary,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: reclaimable == 0 || _busy ? null : _clearJunk,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Clean', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _status ?? '${formatBytes(_disk.freeBytes)} free',
              style: AppTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _bridge.quitApp,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Quit', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// A removal the user has been shown but not yet confirmed.
class _PendingRemoval {
  const _PendingRemoval({
    required this.app,
    required this.paths,
    required this.totalBytes,
    required this.leftoverCount,
  });

  final MacApp app;
  final List<String> paths;
  final int totalBytes;
  final int leftoverCount;
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.tooltip, this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      color: AppTheme.textSecondary,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}
