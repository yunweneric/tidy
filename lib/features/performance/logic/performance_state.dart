import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:tidy/features/performance/data/models/launch_item.dart';
import 'package:tidy/features/performance/data/models/maintenance_task.dart';

enum PerformanceStatus { initial, loading, ready, failed }

/// A one-line result of the last action, good or bad.
///
/// Actions here are immediate and irreversible-ish — a disabled agent stays
/// disabled across reboots — so every one of them says what happened rather
/// than silently redrawing.
class PerformanceNotice extends Equatable {
  const PerformanceNotice({required this.message, required this.ok});

  final String message;
  final bool ok;

  @override
  List<Object?> get props => [message, ok];
}

class PerformanceState extends Equatable {
  const PerformanceState({
    this.status = PerformanceStatus.initial,
    this.items = const [],
    this.tasks = const [],
    this.icons = const {},
    this.busyIds = const {},
    this.notice,
    this.error,
  });

  final PerformanceStatus status;

  /// Every launchd job found, both scopes. The sections filter this rather than
  /// holding two lists that can drift apart.
  final List<LaunchItem> items;

  final List<MaintenanceTask> tasks;

  /// App icons keyed by bundle path.
  final Map<String, Uint8List> icons;

  /// Plist paths and task ids with an action in flight, so a row can show a
  /// spinner without the whole page locking up.
  final Set<String> busyIds;

  final PerformanceNotice? notice;
  final String? error;

  /// `~/Library/LaunchAgents` — yours, and changeable now.
  List<LaunchItem> get loginItems =>
      items.where((item) => item.scope == LaunchItemScope.user).toList();

  /// `/Library/Launch*` — machine-wide and root-owned.
  List<LaunchItem> get backgroundItems =>
      items.where((item) => item.scope == LaunchItemScope.global).toList();

  /// Items whose program is gone. The only finding here with an unambiguous
  /// recommendation, so it drives the sidebar-style count.
  int get brokenCount =>
      items.where((item) => item.health == LaunchItemHealth.broken).length;

  bool isBusy(String id) => busyIds.contains(id);

  PerformanceState copyWith({
    PerformanceStatus? status,
    List<LaunchItem>? items,
    List<MaintenanceTask>? tasks,
    Map<String, Uint8List>? icons,
    Set<String>? busyIds,
    PerformanceNotice? notice,
    String? error,
    bool clearNotice = false,
    bool clearError = false,
  }) {
    return PerformanceState(
      status: status ?? this.status,
      items: items ?? this.items,
      tasks: tasks ?? this.tasks,
      icons: icons ?? this.icons,
      busyIds: busyIds ?? this.busyIds,
      notice: clearNotice ? null : (notice ?? this.notice),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    status,
    items,
    tasks,
    busyIds,
    notice,
    error,
    icons.length,
  ];
}
