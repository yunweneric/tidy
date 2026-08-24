import 'dart:typed_data';

import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/features/performance/data/models/launch_item.dart';
import 'package:mac_uninstaller/features/performance/data/services/performance_bridge.dart';

/// Everything on this Mac that starts itself, and the two things we can do
/// about it: turn it off, or take it away.
///
/// The user/global split is not cosmetic — it is exactly the line between what
/// this app can change today and what needs the privileged helper, so the two
/// lists never mix an actionable row with an unactionable one.
class LaunchItemsService {
  /// Icons keyed by the owning `.app` path. Kept across refreshes because a
  /// bundle's icon does not change while the app is open, and re-rendering
  /// forty of them on every toggle is visible.
  final Map<String, Uint8List> _icons = {};

  Map<String, Uint8List> get icons => Map.unmodifiable(_icons);

  Future<List<LaunchItem>> load() async {
    final raw = await PerformanceBridge.launchItems();
    final items =
        raw.map(LaunchItem.fromMap).toList()..sort(_byUrgencyThenName);
    await _loadIcons(items);
    return items;
  }

  /// Anything in `~/Library/LaunchAgents`: yours, and editable now.
  List<LaunchItem> loginItems(List<LaunchItem> items) =>
      items.where((item) => item.scope == LaunchItemScope.user).toList();

  /// `/Library/LaunchAgents` and `/Library/LaunchDaemons`: set up for every
  /// account, root-owned, read-only until the helper lands.
  List<LaunchItem> backgroundItems(List<LaunchItem> items) =>
      items.where((item) => item.scope == LaunchItemScope.global).toList();

  Future<ActionOutcome> setEnabled(LaunchItem item, {required bool enabled}) {
    return PerformanceBridge.setLaunchItemEnabled(
      label: item.label,
      scope: item.scope.name,
      path: item.path,
      enabled: enabled,
    );
  }

  /// Stops the job, then moves its plist to the Trash.
  ///
  /// Order matters: booting it out first means launchd is never left holding a
  /// job whose definition has gone. Removal goes through [SystemBridge] rather
  /// than a native delete here so it passes the same `isRemovable` guard as
  /// every other deletion in the app.
  Future<ActionOutcome> remove(LaunchItem item) async {
    // A machine-wide item that cannot start anything goes through macOS's own
    // authorization prompt, which does the bootout and the move to Trash in one
    // elevated step. Everything else is user-space and needs no password.
    if (item.canRemoveWithAdmin) {
      return PerformanceBridge.removeLaunchItemElevated(
        path: item.path,
        label: item.label,
        kind: item.kind.name,
      );
    }

    if (!item.canRemove) {
      return const ActionOutcome(
        ok: false,
        message:
            'That item is set up for every user and still works, so Tidy '
            'leaves it alone.',
      );
    }

    await PerformanceBridge.unloadLaunchItem(
      label: item.label,
      scope: item.scope.name,
    );

    final result = await SystemBridge.trashItems([item.path]);
    if (result.isCompleteSuccess) return ActionOutcome.success;
    return ActionOutcome(ok: false, message: result.failures.first.error);
  }

  Future<void> _loadIcons(List<LaunchItem> items) async {
    final wanted = <String>{
      for (final item in items)
        if (item.appPath != null && !_icons.containsKey(item.appPath))
          item.appPath!,
    };
    if (wanted.isEmpty) return;

    final fetched = await SystemBridge.iconsForPaths(wanted.toList(), size: 32);
    _icons.addAll(fetched);
  }

  /// Broken items first — they are the only ones with a clear recommendation —
  /// then disabled, then everything else alphabetically.
  static int _byUrgencyThenName(LaunchItem a, LaunchItem b) {
    final rank = _rank(a).compareTo(_rank(b));
    if (rank != 0) return rank;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  static int _rank(LaunchItem item) => switch (item.health) {
    LaunchItemHealth.broken => 0,
    LaunchItemHealth.unreadable => 1,
    LaunchItemHealth.disabled => 2,
    LaunchItemHealth.active => 3,
  };
}
