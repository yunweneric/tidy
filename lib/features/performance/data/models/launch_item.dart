import 'package:equatable/equatable.dart';

/// What kind of launchd job this is.
enum LaunchItemKind {
  /// Runs as you, in your login session.
  agent,

  /// Runs as root, before anyone logs in.
  daemon,
}

/// Who it runs for.
enum LaunchItemScope {
  /// `~/Library/LaunchAgents` — yours, and ours to change.
  user,

  /// `/Library/Launch*` — set up for every account on the Mac, root-owned.
  global,
}

/// How healthy an item looks. Drives the chip on its row.
enum LaunchItemHealth {
  /// Enabled, and its program is where the plist says it is.
  active,

  /// Turned off. Still on disk, so it can be turned back on.
  disabled,

  /// Nothing can start from it: the program it points at is gone, or the file
  /// is an empty stub an uninstaller left behind. The one case here that is
  /// genuinely safe to remove without a judgement call.
  broken,

  /// The plist could not be parsed. Shown, never acted on.
  unreadable,
}

/// One launchd job — a login item or a background item.
class LaunchItem extends Equatable {
  const LaunchItem({
    required this.path,
    required this.label,
    required this.name,
    required this.kind,
    required this.scope,
    required this.enabled,
    required this.runAtLoad,
    required this.keepAlive,
    required this.programMissing,
    required this.programUnknown,
    required this.unreadable,
    required this.emptyStub,
    required this.requiresAdmin,
    this.program,
    this.appPath,
    this.startIntervalSeconds,
    this.hasSchedule = false,
    this.watchesPaths = false,
    this.modified,
  });

  factory LaunchItem.fromMap(Map<String, dynamic> map) {
    return LaunchItem(
      path: map['path'] as String? ?? '',
      label: map['label'] as String? ?? '',
      name: map['name'] as String? ?? map['label'] as String? ?? 'Unnamed item',
      kind: map['kind'] == 'daemon' ? LaunchItemKind.daemon : LaunchItemKind.agent,
      scope: map['scope'] == 'global' ? LaunchItemScope.global : LaunchItemScope.user,
      enabled: map['enabled'] as bool? ?? true,
      runAtLoad: map['runAtLoad'] as bool? ?? false,
      keepAlive: map['keepAlive'] as bool? ?? false,
      programMissing: map['programMissing'] as bool? ?? false,
      programUnknown: map['programUnknown'] as bool? ?? false,
      unreadable: map['unreadable'] as bool? ?? false,
      emptyStub: map['emptyStub'] as bool? ?? false,
      requiresAdmin: map['requiresAdmin'] as bool? ?? false,
      program: map['program'] as String?,
      appPath: map['appPath'] as String?,
      startIntervalSeconds: (map['startIntervalSeconds'] as num?)?.toInt(),
      hasSchedule: map['hasSchedule'] as bool? ?? false,
      watchesPaths: map['watchesPaths'] as bool? ?? false,
      modified: map['modified'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((map['modified'] as num).toInt() * 1000),
    );
  }

  /// The plist. Stable across refreshes, so it is the row's identity.
  final String path;

  /// launchd's own identifier — what `launchctl` is addressed with.
  final String label;

  /// Something a person can read: the owning app's name where there is one.
  final String name;

  final LaunchItemKind kind;
  final LaunchItemScope scope;

  final bool enabled;
  final bool runAtLoad;
  final bool keepAlive;

  /// The plist names an absolute path that is not there.
  final bool programMissing;

  /// The plist names a bare command rather than a path, so whether it resolves
  /// depends on `PATH` — unknowable without guessing, and guessing wrong would
  /// label a working item as broken.
  final bool programUnknown;

  final bool unreadable;

  /// The file parses, but there is nothing in it — what an uninstaller leaves
  /// when it empties a plist instead of deleting it. launchd can start nothing
  /// from it, so it counts as broken rather than as a healthy idle item.
  final bool emptyStub;

  /// Lives somewhere only root can write. Shown and explained, not editable
  /// until the privileged helper exists.
  final bool requiresAdmin;

  final String? program;

  /// The `.app` the program lives inside, when it does. Used for the icon.
  final String? appPath;

  final int? startIntervalSeconds;
  final bool hasSchedule;
  final bool watchesPaths;
  final DateTime? modified;

  LaunchItemHealth get health {
    if (unreadable) return LaunchItemHealth.unreadable;
    if (programMissing || emptyStub) return LaunchItemHealth.broken;
    if (!enabled) return LaunchItemHealth.disabled;
    return LaunchItemHealth.active;
  }

  /// True when this starts by itself as soon as you log in, rather than waiting
  /// to be asked. That is the distinction the Login Items list is about.
  bool get startsAtLogin => runAtLoad || keepAlive;

  /// Editable right now — user scope, and readable.
  bool get canToggle => !requiresAdmin && !unreadable && label.isNotEmpty;

  /// Removable right now. A broken item is the one we are comfortable
  /// suggesting; everything else is the user's call.
  bool get canRemove => !requiresAdmin && path.isNotEmpty;

  /// One plain line saying when this thing runs.
  String get trigger {
    if (emptyStub) return 'Empty file — it starts nothing';
    if (keepAlive) return 'Always running — macOS restarts it if it stops';
    if (runAtLoad) {
      return kind == LaunchItemKind.daemon
          ? 'Starts when the Mac boots'
          : 'Starts when you log in';
    }
    if (startIntervalSeconds != null) return 'Runs ${_everyPhrase(startIntervalSeconds!)}';
    if (hasSchedule) return 'Runs on a schedule';
    if (watchesPaths) return 'Runs when certain files change';
    return 'Runs only when something asks for it';
  }

  static String _everyPhrase(int seconds) {
    if (seconds < 60) return 'every $seconds seconds';
    if (seconds < 3600) return 'every ${(seconds / 60).round()} minutes';
    if (seconds < 86400) return 'every ${(seconds / 3600).round()} hours';
    return 'every ${(seconds / 86400).round()} days';
  }

  LaunchItem copyWith({bool? enabled}) {
    return LaunchItem(
      path: path,
      label: label,
      name: name,
      kind: kind,
      scope: scope,
      enabled: enabled ?? this.enabled,
      runAtLoad: runAtLoad,
      keepAlive: keepAlive,
      programMissing: programMissing,
      programUnknown: programUnknown,
      unreadable: unreadable,
      emptyStub: emptyStub,
      requiresAdmin: requiresAdmin,
      program: program,
      appPath: appPath,
      startIntervalSeconds: startIntervalSeconds,
      hasSchedule: hasSchedule,
      watchesPaths: watchesPaths,
      modified: modified,
    );
  }

  @override
  List<Object?> get props => [path, label, enabled, programMissing, emptyStub, unreadable];
}
