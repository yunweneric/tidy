import 'package:equatable/equatable.dart';
import 'package:tidy/core/models/launch_item.dart';
import 'package:tidy/features/performance/data/models/maintenance_task.dart';

sealed class PerformanceEvent extends Equatable {
  const PerformanceEvent();

  @override
  List<Object?> get props => const [];
}

/// Reads the launchd folders and the maintenance catalog.
class LoadPerformance extends PerformanceEvent {
  const LoadPerformance({this.silent = false});

  /// True for a refresh after an action, where blanking the list to a spinner
  /// would make a toggle feel like a page reload.
  final bool silent;

  @override
  List<Object?> get props => [silent];
}

class SetLaunchItemEnabled extends PerformanceEvent {
  const SetLaunchItemEnabled(this.item, {required this.enabled});

  final LaunchItem item;
  final bool enabled;

  @override
  List<Object?> get props => [item.path, enabled];
}

class RemoveLaunchItem extends PerformanceEvent {
  const RemoveLaunchItem(this.item);

  final LaunchItem item;

  @override
  List<Object?> get props => [item.path];
}

class RunMaintenanceTask extends PerformanceEvent {
  const RunMaintenanceTask(this.task);

  final MaintenanceTask task;

  @override
  List<Object?> get props => [task.id];
}

/// Clears the outcome line after the user has read it.
class DismissNotice extends PerformanceEvent {
  const DismissNotice();
}
