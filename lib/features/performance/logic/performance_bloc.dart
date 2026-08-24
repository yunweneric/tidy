import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/features/performance/data/services/launch_items_service.dart';
import 'package:mac_uninstaller/features/performance/data/services/maintenance_service.dart';
import 'package:mac_uninstaller/features/performance/logic/performance_event.dart';
import 'package:mac_uninstaller/features/performance/logic/performance_state.dart';

/// Drives the three list-shaped Performance sections: login items, background
/// items and maintenance.
///
/// Heavy Consumers lives in its own bloc because it owns a polling timer, and
/// a timer that keeps ticking while the user reads a list of launch agents is a
/// battery cost with nothing to show for it.
class PerformanceBloc extends Bloc<PerformanceEvent, PerformanceState> {
  PerformanceBloc({
    required LaunchItemsService launchItems,
    required MaintenanceService maintenance,
  }) : _launchItems = launchItems,
       _maintenance = maintenance,
       super(const PerformanceState()) {
    on<LoadPerformance>(_onLoad);
    on<SetLaunchItemEnabled>(_onSetEnabled);
    on<RemoveLaunchItem>(_onRemove);
    on<RunMaintenanceTask>(_onRunTask);
    on<DismissNotice>((_, emit) => emit(state.copyWith(clearNotice: true)));
  }

  final LaunchItemsService _launchItems;
  final MaintenanceService _maintenance;

  Future<void> _onLoad(
    LoadPerformance event,
    Emitter<PerformanceState> emit,
  ) async {
    if (!event.silent) {
      emit(state.copyWith(status: PerformanceStatus.loading, clearError: true));
    }

    try {
      // Both reads are independent and each shells out once, so start them
      // together rather than awaiting one before the other begins.
      final itemsFuture = _launchItems.load();
      final tasksFuture = _maintenance.load();
      final items = await itemsFuture;
      final tasks = await tasksFuture;

      emit(
        state.copyWith(
          status: PerformanceStatus.ready,
          items: items,
          tasks: tasks,
          icons: _launchItems.icons,
          busyIds: const {},
          clearError: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: PerformanceStatus.failed,
          error: 'Tidy could not read what starts on this Mac.\n$e',
        ),
      );
    }
  }

  Future<void> _onSetEnabled(
    SetLaunchItemEnabled event,
    Emitter<PerformanceState> emit,
  ) async {
    emit(_busy(event.item.path, true).copyWith(clearNotice: true));

    final outcome = await _launchItems.setEnabled(
      event.item,
      enabled: event.enabled,
    );

    if (!outcome.ok) {
      emit(
        _busy(event.item.path, false).copyWith(
          notice: PerformanceNotice(
            message: outcome.message ?? 'macOS would not change that item.',
            ok: false,
          ),
        ),
      );
      return;
    }

    // Update the one row rather than reloading: a full refresh re-sorts the
    // list, and a row jumping away from under the switch you just clicked is
    // disorienting. The next explicit refresh puts it in its new place.
    final updated = [
      for (final item in state.items)
        if (item.path == event.item.path)
          item.copyWith(enabled: event.enabled)
        else
          item,
    ];

    emit(
      state.copyWith(
        items: updated,
        busyIds: {...state.busyIds}..remove(event.item.path),
        notice: PerformanceNotice(
          message:
              event.enabled
                  ? '${event.item.name} will start again at your next login.'
                  : '${event.item.name} is off. It stays off until you turn it back on.',
          ok: true,
        ),
      ),
    );
  }

  Future<void> _onRemove(
    RemoveLaunchItem event,
    Emitter<PerformanceState> emit,
  ) async {
    emit(_busy(event.item.path, true).copyWith(clearNotice: true));

    final outcome = await _launchItems.remove(event.item);

    if (!outcome.ok) {
      emit(
        _busy(event.item.path, false).copyWith(
          notice: PerformanceNotice(
            message: outcome.message ?? 'That item could not be removed.',
            ok: false,
          ),
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        items:
            state.items.where((item) => item.path != event.item.path).toList(),
        busyIds: {...state.busyIds}..remove(event.item.path),
        notice: PerformanceNotice(
          // Trashing frees nothing until the Trash is emptied, and the copy has
          // to say the recoverable thing rather than the reassuring one.
          message:
              '${event.item.name} moved to the Trash. Put it back from '
              'there if you need it.',
          ok: true,
        ),
      ),
    );
  }

  Future<void> _onRunTask(
    RunMaintenanceTask event,
    Emitter<PerformanceState> emit,
  ) async {
    emit(_busy(event.task.id, true).copyWith(clearNotice: true));

    final result = await _maintenance.run(event.task);

    emit(
      _busy(event.task.id, false).copyWith(
        notice: PerformanceNotice(message: result.message, ok: result.ok),
      ),
    );
  }

  PerformanceState _busy(String id, bool busy) {
    final ids = {...state.busyIds};
    if (busy) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    return state.copyWith(busyIds: ids);
  }
}
